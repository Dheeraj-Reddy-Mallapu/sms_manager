package com.example.sms_manager

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.util.Log

class SmsDeliveredReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "SmsDeliveredReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.example.sms_manager.SMS_DELIVERED") return

        val messageUriString = intent.getStringExtra("message_uri") ?: return
        val messageUri = Uri.parse(messageUriString)
        
        val isSuccess = resultCode == Activity.RESULT_OK
        val newStatus = if (isSuccess) Telephony.Sms.STATUS_COMPLETE else Telephony.Sms.STATUS_FAILED

        Log.d(TAG, "SMS Delivered Result: $resultCode, updating $messageUri to status $newStatus")

        val values = android.content.ContentValues().apply {
            put(Telephony.Sms.STATUS, newStatus)
        }

        try {
            context.contentResolver.update(messageUri, values, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update SMS status in provider: ${e.message}")
        }
    }
}
