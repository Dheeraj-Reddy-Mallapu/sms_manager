package com.example.sms_manager

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Default SMS Role ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ROLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefaultSmsApp"    -> result.success(isDefaultSmsApp())
                    "requestDefaultSmsRole" -> { requestDefaultSmsRole(); result.success(null) }
                    else                 -> result.notImplemented()
                }
            }

        // ── SMS Query Channel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

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
                        if (address == null || body == null) {
                            result.error("INVALID_ARGUMENT", "address and body required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    getSystemService(android.telephony.SmsManager::class.java)
                                } else {
                                    @Suppress("DEPRECATION")
                                    android.telephony.SmsManager.getDefault()
                                }

                                val parts = smsManager.divideMessage(body)
                                if (parts.size == 1) {
                                    smsManager.sendTextMessage(address, null, body, null, null)
                                } else {
                                    smsManager.sendMultipartTextMessage(address, null, parts, null, null)
                                }

                                val values = android.content.ContentValues().apply {
                                    put(Telephony.Sms.ADDRESS, address)
                                    put(Telephony.Sms.BODY,    body)
                                    put(Telephony.Sms.DATE,    System.currentTimeMillis())
                                    put(Telephony.Sms.READ,    1)
                                    put(Telephony.Sms.TYPE,    Telephony.Sms.MESSAGE_TYPE_SENT)
                                }
                                contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)
                                runOnUiThread { result.success(true) }
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
                                activeSubscriptions?.forEach { info ->
                                    simInfoList.add(mapOf(
                                        "subscriptionId" to info.subscriptionId,
                                        "simSlotIndex"   to info.simSlotIndex,
                                        "displayName"    to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                                        "number"         to (info.number ?: "")
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
