package com.example.sms_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput

/**
 * Handles inline reply actions from the notification shade.
 * Sends the SMS and dismisses the notification.
 */
class SmsReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address") ?: return
        val remoteInput = RemoteInput.getResultsFromIntent(intent)
        val replyText = remoteInput?.getCharSequence(SmsReceiver.KEY_REPLY_TEXT)?.toString() ?: return

        Log.d("SmsReplyReceiver", "Inline reply to $address: ${replyText.take(30)}")

        try {
            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                context.getSystemService(android.telephony.SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                android.telephony.SmsManager.getDefault()
            }
            smsManager.sendTextMessage(address, null, replyText, null, null)

            // Save to sent box
            val values = android.content.ContentValues().apply {
                put(Telephony.Sms.ADDRESS, address)
                put(Telephony.Sms.BODY, replyText)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
            }
            context.contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)

            // Dismiss the notification
            NotificationManagerCompat.from(context).cancel(address.hashCode())
        } catch (e: Exception) {
            Log.e("SmsReplyReceiver", "Failed to send reply: ${e.message}")
        }
    }
}
