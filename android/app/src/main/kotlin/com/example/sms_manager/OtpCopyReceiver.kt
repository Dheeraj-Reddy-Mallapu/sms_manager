package com.example.sms_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipboardManager
import android.content.ClipData
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat

class OtpCopyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val otp = intent.getStringExtra("otp")
        val notificationId = intent.getIntExtra("notification_id", -1)

        if (otp != null) {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("OTP", otp)
            clipboard.setPrimaryClip(clip)
            
            Toast.makeText(context, "OTP copied: $otp", Toast.LENGTH_SHORT).show()

            // Optionally dismiss the notification after copying
            if (notificationId != -1) {
                NotificationManagerCompat.from(context).cancel(notificationId)
            }
        }
    }
}
