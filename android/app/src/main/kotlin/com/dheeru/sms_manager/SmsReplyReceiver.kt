package com.dheeru.sms_manager

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
            // Send SMS via our unified SmsSender which handles multipart and delivery tracking
            SmsSender.sendSms(context, address, replyText, null)

            // Dismiss the notification
            NotificationManagerCompat.from(context).cancel(address.hashCode())
        } catch (e: Exception) {
            Log.e("SmsReplyReceiver", "Failed to send reply: ${e.message}")
        }
    }
}
