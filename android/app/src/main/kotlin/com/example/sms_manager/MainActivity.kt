package com.example.sms_manager

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val ROLE_CHANNEL     = "sms_manager/default_role"
        private const val QUERY_CHANNEL    = "sms_manager/query"
        private const val INCOMING_CHANNEL = "sms_manager/incoming"
        private const val REQUEST_CODE_SET_DEFAULT = 1001

        // Track currently active conversation thread ID to suppress notifications
        var activeThreadId: Long? = null
    }

    // Holds the pending result for requestDefaultSmsRole so we can resolve it
    // after the user responds to the system dialog (in onActivityResult).
    private var pendingRoleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Default SMS Role ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ROLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefaultSmsApp" -> result.success(isDefaultSmsApp())
                    "requestDefaultSmsRole" -> {
                        if (isDefaultSmsApp()) {
                            // Already default — resolve immediately, no dialog needed
                            result.success(true)
                        } else {
                            // Store the result; it will be resolved in onActivityResult
                            pendingRoleResult = result
                            requestDefaultSmsRole()
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── SMS Query Channel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "setActiveThread" -> {
                        val threadId = call.argument<Any>("threadId")?.toString()?.toLongOrNull()
                        activeThreadId = threadId
                        result.success(true)
                    }

                    "fetchThreads" -> {
                        val limit  = call.argument<Any>("limit")?.toString()?.toIntOrNull()  ?: 500
                        val offset = call.argument<Any>("offset")?.toString()?.toIntOrNull() ?: 0
                        Thread {
                            try {
                                val threads = SmsFetcher.fetchThreads(this, limit, offset)
                                runOnUiThread { result.success(threads) }
                            } catch (e: Exception) {
                                Log.e(TAG, "fetchThreads error", e)
                                runOnUiThread { result.error("FETCH_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "fetchThreadsSince" -> {
                        val timestamp = call.argument<Any>("timestamp")?.toString()?.toLongOrNull() ?: 0L
                        val limit     = call.argument<Any>("limit")?.toString()?.toIntOrNull()  ?: 1000
                        Thread {
                            try {
                                val threads = SmsFetcher.fetchThreadsSince(this, timestamp, limit)
                                runOnUiThread { result.success(threads) }
                            } catch (e: Exception) {
                                Log.e(TAG, "fetchThreadsSince error", e)
                                runOnUiThread { result.error("FETCH_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "fetchMessages" -> {
                        val threadId = call.argument<Any>("threadId")?.toString()?.toLongOrNull()
                        val limit    = call.argument<Any>("limit")?.toString()?.toIntOrNull()  ?: 200
                        val offset   = call.argument<Any>("offset")?.toString()?.toIntOrNull() ?: 0
                        if (threadId == null) {
                            result.error("INVALID_ARGUMENT", "threadId required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val msgs = SmsFetcher.fetchMessages(this, threadId, limit, offset)
                                runOnUiThread { result.success(msgs) }
                            } catch (e: Exception) {
                                Log.e(TAG, "fetchMessages error", e)
                                runOnUiThread { result.error("FETCH_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "sendSms" -> {
                        val address = call.argument<String>("address")
                        val body    = call.argument<String>("body")
                        val subscriptionId = call.argument<Int>("subscriptionId")
                        if (address == null || body == null) {
                            result.error("INVALID_ARGUMENT", "address and body required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val smsManager = if (subscriptionId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                        getSystemService(android.telephony.SmsManager::class.java).createForSubscriptionId(subscriptionId)
                                    } else {
                                        @Suppress("DEPRECATION")
                                        android.telephony.SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                                    }
                                } else {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                        getSystemService(android.telephony.SmsManager::class.java)
                                    } else {
                                        @Suppress("DEPRECATION")
                                        android.telephony.SmsManager.getDefault()
                                    }
                                }

                                val values = android.content.ContentValues().apply {
                                    put(Telephony.Sms.ADDRESS, address)
                                    put(Telephony.Sms.BODY,    body)
                                    put(Telephony.Sms.DATE,    System.currentTimeMillis())
                                    put(Telephony.Sms.READ,    1)
                                    put(Telephony.Sms.TYPE,    Telephony.Sms.MESSAGE_TYPE_OUTBOX) // Insert as OUTBOX initially!
                                    if (subscriptionId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                                        put(Telephony.Sms.SUBSCRIPTION_ID, subscriptionId)
                                    }
                                }
                                val uri = contentResolver.insert(Telephony.Sms.Outbox.CONTENT_URI, values)

                                val intent = android.content.Intent(this@MainActivity, SmsSentReceiver::class.java)
                                intent.action = "com.example.sms_manager.SMS_SENT"
                                intent.putExtra("message_uri", uri?.toString() ?: "")
                                // Use a unique request code (msgId) to prevent PendingIntents from overwriting each other
                                val requestCode = uri?.lastPathSegment?.toIntOrNull() ?: System.currentTimeMillis().toInt()
                                val sentIntent = android.app.PendingIntent.getBroadcast(
                                    this@MainActivity,
                                    requestCode,
                                    intent,
                                    android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                                )

                                val deliveryIntentObj = android.content.Intent(this@MainActivity, SmsDeliveredReceiver::class.java)
                                deliveryIntentObj.action = "com.example.sms_manager.SMS_DELIVERED"
                                deliveryIntentObj.putExtra("message_uri", uri?.toString() ?: "")
                                val deliveryIntent = android.app.PendingIntent.getBroadcast(
                                    this@MainActivity,
                                    requestCode,
                                    deliveryIntentObj,
                                    android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                                )

                                val parts = smsManager.divideMessage(body)
                                if (parts.size == 1) {
                                    smsManager.sendTextMessage(address, null, body, sentIntent, deliveryIntent)
                                } else {
                                    val sentIntents = ArrayList<android.app.PendingIntent>()
                                    val deliveryIntents = ArrayList<android.app.PendingIntent>()
                                    for (i in parts.indices) {
                                        sentIntents.add(sentIntent)
                                        deliveryIntents.add(deliveryIntent)
                                    }
                                    smsManager.sendMultipartTextMessage(address, null, parts, sentIntents, deliveryIntents)
                                }
                                
                                val nativeId = uri?.lastPathSegment?.toIntOrNull() ?: -1
                                runOnUiThread { result.success(nativeId) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SEND_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "getSimInfo" -> {
                        try {
                            val simInfoList = mutableListOf<Map<String, Any?>>()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                                val subManager = getSystemService(android.telephony.SubscriptionManager::class.java)
                                val activeSubscriptions = try {
                                    subManager?.activeSubscriptionInfoList
                                } catch (e: SecurityException) {
                                    null
                                }
                                val defaultSmsSubId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    android.telephony.SmsManager.getDefaultSmsSubscriptionId()
                                } else {
                                    -1
                                }
                                activeSubscriptions?.forEach { info ->
                                    simInfoList.add(mapOf(
                                        "subscriptionId" to info.subscriptionId,
                                        "simSlotIndex"   to info.simSlotIndex,
                                        "displayName"    to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                                        "number"         to (info.number ?: ""),
                                        "isDefault"      to (info.subscriptionId == defaultSmsSubId)
                                    ))
                                }
                            }
                            result.success(simInfoList)
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }

                    "markAsRead" -> {
                        val threadId = call.argument<Any>("threadId")?.toString()?.toLongOrNull()
                        if (threadId == null) {
                            result.error("INVALID_ARGUMENT", "threadId required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val values = android.content.ContentValues().apply {
                                    put(Telephony.Sms.READ, 1)
                                }
                                val updated = contentResolver.update(
                                    Telephony.Sms.CONTENT_URI, values,
                                    "${Telephony.Sms.THREAD_ID} = ? AND ${Telephony.Sms.READ} = 0",
                                    arrayOf(threadId.toString())
                                )
                                runOnUiThread { result.success(updated > 0) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("UPDATE_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "markAllAsRead" -> {
                        Thread {
                            try {
                                val values = android.content.ContentValues().apply {
                                    put(Telephony.Sms.READ, 1)
                                }
                                val updated = contentResolver.update(
                                    Telephony.Sms.CONTENT_URI, values,
                                    "${Telephony.Sms.READ} = 0",
                                    null
                                )
                                runOnUiThread { result.success(updated > 0) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("UPDATE_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "deleteMessage" -> {
                        val messageId = call.argument<Any>("messageId")?.toString()?.toLongOrNull()
                        if (messageId == null) {
                            result.error("INVALID_ARGUMENT", "messageId required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val deleted = contentResolver.delete(
                                    Telephony.Sms.CONTENT_URI,
                                    "${Telephony.Sms._ID} = ?",
                                    arrayOf(messageId.toString())
                                )
                                runOnUiThread { result.success(deleted > 0) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("DELETE_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "deleteThread" -> {
                        val threadId = call.argument<Any>("threadId")?.toString()?.toLongOrNull()
                        if (threadId == null) {
                            result.error("INVALID_ARGUMENT", "threadId required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val deleted = contentResolver.delete(
                                    Telephony.Threads.CONTENT_URI,
                                    "${Telephony.Threads._ID} = ?",
                                    arrayOf(threadId.toString())
                                )
                                runOnUiThread { result.success(deleted > 0) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("DELETE_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "openContactCard" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "address required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = android.net.Uri.withAppendedPath(
                                android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                                android.net.Uri.encode(address)
                            )
                            val cursor = contentResolver.query(
                                uri,
                                arrayOf(android.provider.ContactsContract.PhoneLookup._ID),
                                null, null, null
                            )
                            var contactId: String? = null
                            cursor?.use {
                                if (it.moveToFirst()) {
                                    contactId = it.getString(0)
                                }
                            }
                            if (contactId != null) {
                                val contactUri = android.content.ContentUris.withAppendedId(
                                    android.provider.ContactsContract.Contacts.CONTENT_URI,
                                    contactId!!.toLong()
                                )
                                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, contactUri)
                                intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(intent)
                                result.success(true)
                            } else {
                                // Fallback: try to add contact
                                val intent = android.content.Intent(android.content.Intent.ACTION_INSERT)
                                intent.type = android.provider.ContactsContract.RawContacts.CONTENT_TYPE
                                intent.putExtra(android.provider.ContactsContract.Intents.Insert.PHONE, address)
                                intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(intent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("CONTACT_ERROR", e.message, null)
                        }
                    }

                    "dialNumber" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "address required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = android.content.Intent(android.content.Intent.ACTION_DIAL)
                            intent.data = android.net.Uri.parse("tel:$address")
                            intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DIAL_ERROR", e.message, null)
                        }
                    }

                    "getContactPhoto" -> {
                        val uriStr = call.argument<String>("uri")
                        if (uriStr != null) {
                            Thread {
                                try {
                                    val uri = android.net.Uri.parse(uriStr)
                                    contentResolver.openInputStream(uri)?.use { stream ->
                                        val bytes = stream.readBytes()
                                        runOnUiThread { result.success(bytes) }
                                    } ?: runOnUiThread { result.success(null) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.success(null) }
                                }
                            }.start()
                        } else {
                            result.success(null)
                        }
                    }

                    // Legacy single contact lookup (kept for compatibility)
                    "getContactByAddress" -> {
                        val address = call.argument<String>("address")
                        if (address == null) {
                            result.error("INVALID_ARGUMENT", "address required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val contacts = SmsFetcher.batchLookupContacts(this, listOf(address))
                                val contact = contacts[address]
                                runOnUiThread {
                                    result.success(mapOf(
                                        "name"     to contact?.get("name"),
                                        "photoUri" to contact?.get("photoUri")
                                    ))
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("CONTACT_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "getOrCreateThreadId" -> {
                        val address = call.argument<String>("address")
                        if (address == null) {
                            result.error("INVALID_ARGUMENT", "address required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val threadId = android.provider.Telephony.Threads.getOrCreateThreadId(this, address)
                                runOnUiThread { result.success(threadId) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("THREAD_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "searchContacts" -> {
                        val query = call.argument<String>("query")
                        if (query == null) {
                            result.error("INVALID_ARGUMENT", "query required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val contacts = mutableListOf<Map<String, String>>()
                                val uri = android.net.Uri.withAppendedPath(
                                    android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_FILTER_URI,
                                    android.net.Uri.encode(query)
                                )
                                val cursor = contentResolver.query(
                                    uri,
                                    arrayOf(
                                        android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                                        android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
                                        android.provider.ContactsContract.CommonDataKinds.Phone.PHOTO_URI
                                    ),
                                    null, null,
                                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC LIMIT 20"
                                )
                                cursor?.use {
                                    val nameIdx = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                                    val numberIdx = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER)
                                    val photoIdx = it.getColumnIndex(android.provider.ContactsContract.CommonDataKinds.Phone.PHOTO_URI)
                                    while (it.moveToNext()) {
                                        val name = if (nameIdx >= 0) it.getString(nameIdx) ?: "" else ""
                                        val number = if (numberIdx >= 0) it.getString(numberIdx) ?: "" else ""
                                        val photo = if (photoIdx >= 0) it.getString(photoIdx) ?: "" else ""
                                        if (number.isNotEmpty()) {
                                            contacts.add(mapOf(
                                                "name" to name,
                                                "number" to number,
                                                "photoUri" to photo
                                            ))
                                        }
                                    }
                                }
                                runOnUiThread { result.success(contacts) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("CONTACT_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Incoming SMS EventChannel ─────────────────────────────────────────
        // SmsReceiver pushes events here when a new SMS arrives
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INCOMING_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "Incoming SMS EventChannel: listening")
                    SmsReceiver.incomingSink = events
                }
                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "Incoming SMS EventChannel: cancelled")
                    SmsReceiver.incomingSink = null
                }
            })

        // ── System SMS Database Observer ─────────────────────────────────────────
        // Listens to Android's internal SMS database and pushes a debounce event
        // whenever any app sends, receives, reads, or deletes an SMS.
        var systemChangesSink: EventChannel.EventSink? = null
        val dbChangeHandler = Handler(Looper.getMainLooper())
        
        val smsContentObserver = object : android.database.ContentObserver(dbChangeHandler) {
            private val notifyRunnable = Runnable {
                Log.d(TAG, "SmsContentObserver: DB changed, notifying Flutter")
                systemChangesSink?.success("changed")
            }
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                // Debounce rapidly firing DB triggers
                dbChangeHandler.removeCallbacks(notifyRunnable)
                dbChangeHandler.postDelayed(notifyRunnable, 500)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "sms_manager/system_changes")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "System changes EventChannel: listening")
                    systemChangesSink = events
                    try {
                        contentResolver.registerContentObserver(
                            Uri.parse("content://sms"), true, smsContentObserver
                        )
                        contentResolver.registerContentObserver(
                            Uri.parse("content://mms-sms/conversations"), true, smsContentObserver
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to register ContentObserver", e)
                    }
                }
                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "System changes EventChannel: cancelled")
                    systemChangesSink = null
                    contentResolver.unregisterContentObserver(smsContentObserver)
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SET_DEFAULT) {
            // The system dialog for setting default SMS app just finished.
            // Check if we are now the default SMS app and resolve the pending result.
            pendingRoleResult?.success(isDefaultSmsApp())
            pendingRoleResult = null
        }
    }

    private fun isDefaultSmsApp(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            roleManager.isRoleHeld(RoleManager.ROLE_SMS)
        } else {
            Telephony.Sms.getDefaultSmsPackage(this) == packageName
        }
    }

    private fun requestDefaultSmsRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_SMS) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_SMS)
            ) {
                startActivityForResult(
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS),
                    REQUEST_CODE_SET_DEFAULT
                )
            }
        } else {
            if (Telephony.Sms.getDefaultSmsPackage(this) != packageName) {
                val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                    putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
                }
                startActivityForResult(intent, REQUEST_CODE_SET_DEFAULT)
            }
        }
    }
}
