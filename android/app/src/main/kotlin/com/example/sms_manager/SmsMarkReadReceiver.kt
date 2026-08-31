package com.example.sms_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ContentValues
import android.provider.Telephony
import androidx.core.app.NotificationManagerCompat

class SmsMarkReadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address")
        val notificationId = intent.getIntExtra("notification_id", -1)

        if (address != null) {
            try {
                // Mark all unread messages from this address as read in Telephony provider
                val values = ContentValues().apply {
                    put(Telephony.Sms.READ, 1)
                }
                context.contentResolver.update(
                    Telephony.Sms.Inbox.CONTENT_URI,
                    values,
                    "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.READ} = 0",
                    arrayOf(address)
                )
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (notificationId != -1) {
            NotificationManagerCompat.from(context).cancel(notificationId)
        }
    }
}
