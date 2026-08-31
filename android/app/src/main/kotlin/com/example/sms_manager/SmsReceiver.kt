package com.example.sms_manager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import android.net.Uri
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

class SmsReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "SmsReceiver"
        const val CHANNEL_ID = "sms_incoming"
        const val KEY_REPLY_TEXT = "sms_reply_text"
        const val ACTION_REPLY = "com.example.sms_manager.ACTION_REPLY"

        // EventChannel sink — set by MainActivity
        var incomingSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val address = messages[0].displayOriginatingAddress ?: ""
        val body = messages.joinToString("") { it.displayMessageBody ?: "" }
        val timestamp = System.currentTimeMillis()

        Log.d(TAG, "Incoming SMS from $address: ${body.take(40)}")

        // ── 1. Save to system Telephony provider ──
        val values = android.content.ContentValues().apply {
            put(Telephony.Sms.ADDRESS, address)
            put(Telephony.Sms.BODY, body)
            put(Telephony.Sms.DATE, timestamp)
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
        }
        context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)

        // ── 2. Resolve contact name ──
        val contactName = resolveContactName(context, address)
        val displayName = contactName ?: address

        // ── 3. Notify Flutter via EventChannel (if app is in foreground) ──
        incomingSink?.let { sink ->
            try {
                sink.success(mapOf(
                    "address"     to address,
                    "body"        to body,
                    "date"        to timestamp,
                    "contactName" to contactName
                ))
            } catch (e: Exception) {
                Log.w(TAG, "EventChannel push failed: ${e.message}")
            }
        }

        // ── 4. Show push notification ──
        showNotification(context, address, displayName, body, timestamp)
    }

    private fun resolveContactName(context: Context, address: String): String? {
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(address)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Contact resolve failed: ${e.message}")
            null
        }
    }

    private fun showNotification(
        context: Context,
        address: String,
        displayName: String,
        body: String,
        timestamp: Long
    ) {
        createNotificationChannel(context)

        // Tap action → open app
        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("threadAddress", address)
        }
        val openPending = PendingIntent.getActivity(
            context, address.hashCode(), openIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Inline Reply action
        val remoteInput = RemoteInput.Builder(KEY_REPLY_TEXT)
            .setLabel("Reply")
            .build()
        val replyIntent = Intent(context, SmsReplyReceiver::class.java).apply {
            putExtra("address", address)
        }
        val replyPending = PendingIntent.getBroadcast(
            context, address.hashCode() + 1, replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send, "Reply", replyPending
        ).addRemoteInput(remoteInput).build()

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(displayName)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setWhen(timestamp)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(openPending)
            .addAction(replyAction)
            .build()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            NotificationManagerCompat.from(context).areNotificationsEnabled()
        ) {
            NotificationManagerCompat.from(context).notify(address.hashCode(), notification)
        }
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Incoming Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for new SMS messages"
                enableVibration(true)
                enableLights(true)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
