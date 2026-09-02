package com.dheeru.sms_manager

import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log

object SmsSender {
    private const val TAG = "SmsSender"

    fun sendSms(context: Context, address: String, body: String, subscriptionId: Int?): Int {
        try {
            val smsManager = if (subscriptionId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(android.telephony.SmsManager::class.java).createForSubscriptionId(subscriptionId)
                } else {
                    @Suppress("DEPRECATION")
                    android.telephony.SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(android.telephony.SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    android.telephony.SmsManager.getDefault()
                }
            }

            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, address)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_OUTBOX)
                if (subscriptionId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    put(Telephony.Sms.SUBSCRIPTION_ID, subscriptionId)
                }
            }
            
            val uri = context.contentResolver.insert(Telephony.Sms.Outbox.CONTENT_URI, values)

            val intent = Intent(context, SmsSentReceiver::class.java)
            intent.action = "com.dheeru.sms_manager.SMS_SENT"
            intent.putExtra("message_uri", uri?.toString() ?: "")
            
            val requestCode = uri?.lastPathSegment?.toIntOrNull() ?: System.currentTimeMillis().toInt()
            val sentIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val deliveryIntentObj = Intent(context, SmsDeliveredReceiver::class.java)
            deliveryIntentObj.action = "com.dheeru.sms_manager.SMS_DELIVERED"
            deliveryIntentObj.putExtra("message_uri", uri?.toString() ?: "")
            val deliveryIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                deliveryIntentObj,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val parts = smsManager.divideMessage(body)
            if (parts.size == 1) {
                smsManager.sendTextMessage(address, null, body, sentIntent, deliveryIntent)
            } else {
                val sentIntents = ArrayList<PendingIntent>()
                val deliveryIntents = ArrayList<PendingIntent>()
                for (i in parts.indices) {
                    sentIntents.add(sentIntent)
                    deliveryIntents.add(deliveryIntent)
                }
                smsManager.sendMultipartTextMessage(address, null, parts, sentIntents, deliveryIntents)
            }

            return uri?.lastPathSegment?.toIntOrNull() ?: -1
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS natively", e)
            throw e
        }
    }
}
