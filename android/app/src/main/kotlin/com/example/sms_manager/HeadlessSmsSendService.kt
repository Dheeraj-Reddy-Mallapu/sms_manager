package com.example.sms_manager

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

class HeadlessSmsSendService : Service() {
    companion object {
        private const val TAG = "HeadlessSmsSendService"
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == android.telephony.TelephonyManager.ACTION_RESPOND_VIA_MESSAGE) {
            val address = intent.data?.schemeSpecificPart ?: ""
            val body = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
            
            // Extract subscriptionId if provided by the intent. Different OEMs might use different keys,
            // but the standard one is often "subscription" or "android.telephony.extra.SUBSCRIPTION_INDEX".
            val subIdFromIntent = intent.getIntExtra("subscription", -1).let { if (it == -1) null else it }
                ?: intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", -1).let { if (it == -1) null else it }

            if (address.isNotEmpty() && body.isNotEmpty()) {
                Thread {
                    try {
                        Log.d(TAG, "Sending headless SMS to $address")
                        SmsSender.sendSms(this, address, body, subIdFromIntent)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send headless SMS", e)
                    }
                }.start()
            }
        }
        return START_NOT_STICKY
    }
}
