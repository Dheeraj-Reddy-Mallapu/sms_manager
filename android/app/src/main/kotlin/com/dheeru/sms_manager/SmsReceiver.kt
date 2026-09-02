package com.dheeru.sms_manager

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
        const val ACTION_REPLY = "com.dheeru.sms_manager.ACTION_REPLY"

        // EventChannel sink — set by MainActivity
        var incomingSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val pendingResult = goAsync()
        
        Thread {
            try {
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

                // ── 2. Resolve contact name & photo ──
                val contactInfo = resolveContactInfo(context, address)
                val contactName = contactInfo.first
                val contactPhotoUri = contactInfo.second
                val displayName = contactName ?: address

                // ── 3. Notify Flutter via EventChannel ──
                incomingSink?.let { sink ->
                    try {
                        sink.success(mapOf(
                            "address"     to address,
                            "body"        to body,
                            "date"        to timestamp,
                            "contactName" to contactName,
                            "contactPhotoUri" to contactPhotoUri
                        ))
                    } catch (e: Exception) {
                        Log.w(TAG, "EventChannel push failed: ${e.message}")
                    }
                }

                // ── 4. Show push notification ──
                val threadId = Telephony.Threads.getOrCreateThreadId(context, address)
                if (MainActivity.activeThreadId != threadId) {
                    showNotification(context, address, displayName, contactPhotoUri, body, timestamp, threadId)
                } else {
                    Log.d(TAG, "Suppressing notification: user is viewing thread $threadId")
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun resolveContactInfo(context: Context, address: String): Pair<String?, String?> {
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(address)
            )
            context.contentResolver.query(
                uri,
                arrayOf(
                    ContactsContract.PhoneLookup.DISPLAY_NAME,
                    ContactsContract.PhoneLookup.PHOTO_URI
                ),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    Pair(c.getString(0), c.getString(1))
                } else Pair(null, null)
            } ?: Pair(null, null)
        } catch (e: Exception) {
            Log.w(TAG, "Contact resolve failed: ${e.message}")
            Pair(null, null)
        }
    }

    private fun showNotification(
        context: Context,
        address: String,
        displayName: String,
        contactPhotoUri: String?,
        body: String,
        timestamp: Long,
        threadId: Long
    ) {
        createNotificationChannel(context)

        // Fetch Large Icon (Contact Photo or Brand Logo)
        var largeIcon: android.graphics.Bitmap? = null
        if (contactPhotoUri != null) {
            try {
                val uri = android.net.Uri.parse(contactPhotoUri)
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    largeIcon = android.graphics.BitmapFactory.decodeStream(stream)
                }
            } catch (e: Exception) {
                // Ignore
            }
        } else {
            // Try fetching brand logo if no contact photo
            val brandUrl = getBrandLogoUrl(displayName)
            if (brandUrl != null) {
                try {
                    val url = java.net.URL(brandUrl)
                    val connection = url.openConnection()
                    connection.doInput = true
                    connection.connect()
                    connection.getInputStream().use { stream ->
                        largeIcon = android.graphics.BitmapFactory.decodeStream(stream)
                    }
                } catch (e: Exception) {
                    // Ignore
                }
            }
        }

        // 1. Check for OTP
        var otpCode: String? = null
        val lowerBody = body.lowercase()
        val keywords = listOf("otp", "code", "pin", "verification", "password", "passcode", "auth")
        
        if (keywords.any { lowerBody.contains(it) }) {
            // Check for Google style G-123456
            val googleMatch = Regex("""G-(\d{6})""").find(body)
            if (googleMatch != null) {
                otpCode = googleMatch.value
            } else {
                // Check for dash separated like 123-456
                val dashMatch = Regex("""\b(\d{3})-(\d{3})\b""").find(body)
                if (dashMatch != null) {
                    otpCode = dashMatch.value
                } else {
                    // Standard 4 to 8 digits, using negative lookbehind to ignore currencies or dates if possible
                    // Avoid matching something like $1234 or ₹1234
                    val standardMatch = Regex("""(?<![${'$'}₹£€])\b(\d{4,8})\b""").find(body)
                    if (standardMatch != null) {
                        otpCode = standardMatch.value
                    }
                }
            }
        }

        // Tap action → open app
        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = Intent.ACTION_VIEW
            data = Uri.parse("app://smsmanager/conversation/$threadId")
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

        // Mark as Read action
        val markReadIntent = Intent(context, SmsMarkReadReceiver::class.java).apply {
            putExtra("address", address)
            putExtra("notification_id", address.hashCode())
        }
        val markReadPending = PendingIntent.getBroadcast(
            context, address.hashCode() + 3, markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val markReadAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_view, "Mark as read", markReadPending
        ).build()

        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher) // Use app logo
            .setContentTitle(displayName)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body)) // Shows multi-line text
            .setWhen(timestamp)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(openPending)
            .addAction(markReadAction)
            .addAction(replyAction)

        // Add OTP Copy action if detected
        if (otpCode != null) {
            val copyIntent = Intent(context, OtpCopyReceiver::class.java).apply {
                putExtra("otp", otpCode)
                putExtra("notification_id", address.hashCode())
            }
            val copyPending = PendingIntent.getBroadcast(
                context, address.hashCode() + 2, copyIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val copyAction = NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_edit, "Copy $otpCode", copyPending
            ).build()
            
            notificationBuilder.addAction(copyAction)
        }

        if (largeIcon != null) {
            notificationBuilder.setLargeIcon(largeIcon)
        }

        val notification = notificationBuilder.build()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            NotificationManagerCompat.from(context).areNotificationsEnabled()
        ) {
            NotificationManagerCompat.from(context).notify(address.hashCode(), notification)
        }
    }

    private fun getBrandLogoUrl(name: String): String? {
        val lower = name.lowercase()
        if (lower.contains("amazon")) return "https://logo.clearbit.com/amazon.com"
        if (lower.contains("flipkart")) return "https://logo.clearbit.com/flipkart.com"
        if (lower.contains("google")) return "https://logo.clearbit.com/google.com"
        if (lower.contains("netflix")) return "https://logo.clearbit.com/netflix.com"
        if (lower.contains("swiggy")) return "https://logo.clearbit.com/swiggy.com"
        if (lower.contains("zomato")) return "https://logo.clearbit.com/zomato.com"
        if (lower.contains("uber")) return "https://logo.clearbit.com/uber.com"
        if (lower.contains("ola")) return "https://logo.clearbit.com/olacabs.com"
        if (lower.contains("hdfc")) return "https://logo.clearbit.com/hdfcbank.com"
        if (lower.contains("sbi")) return "https://logo.clearbit.com/onlinesbi.sbi"
        if (lower.contains("icici")) return "https://logo.clearbit.com/icicibank.com"
        if (lower.contains("apple")) return "https://logo.clearbit.com/apple.com"
        if (lower.contains("facebook") || lower.contains("fb")) return "https://logo.clearbit.com/facebook.com"
        if (lower.contains("instagram")) return "https://logo.clearbit.com/instagram.com"
        if (lower.contains("whatsapp")) return "https://logo.clearbit.com/whatsapp.com"
        if (lower.contains("twitter") || lower.contains(" x ")) return "https://logo.clearbit.com/x.com"
        if (lower.contains("myntra")) return "https://logo.clearbit.com/myntra.com"
        if (lower.contains("paytm")) return "https://logo.clearbit.com/paytm.com"
        if (lower.contains("phonepe")) return "https://logo.clearbit.com/phonepe.com"
        if (lower.contains("jio")) return "https://logo.clearbit.com/jio.com"
        if (lower.contains("airtel")) return "https://logo.clearbit.com/airtel.in"
        if (lower.contains("vi") || lower.contains("vodafone")) return "https://logo.clearbit.com/myvi.in"
        return null
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
