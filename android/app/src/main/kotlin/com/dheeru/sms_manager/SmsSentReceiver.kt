package com.dheeru.sms_manager

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.util.Log

class SmsSentReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "SmsSentReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.dheeru.sms_manager.SMS_SENT") return

        val messageUriString = intent.getStringExtra("message_uri") ?: return
        val messageUri = Uri.parse(messageUriString)
        
        val isSuccess = resultCode == Activity.RESULT_OK
        val newType = if (isSuccess) Telephony.Sms.MESSAGE_TYPE_SENT else Telephony.Sms.MESSAGE_TYPE_FAILED

        Log.d(TAG, "SMS Sent Result: $resultCode, updating $messageUri to type $newType")

        val values = android.content.ContentValues().apply {
            put(Telephony.Sms.TYPE, newType)
        }

        try {
            context.contentResolver.update(messageUri, values, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update SMS status in provider: ${e.message}")
        }
    }
}
