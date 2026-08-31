package com.example.sms_manager

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Telephony
import android.util.Log

object SmsFetcher {
    private const val TAG = "SmsFetcher"

    /**
     * Fetches thread summaries using a SINGLE pass through content://sms.
     *
     * Strategy: query all SMS sorted by date DESC, iterate in Kotlin to collect
     * the first (latest) message per thread_id. This is O(messages until we have
     * `limit` unique threads) — far faster than N+2 queries per thread.
     *
     * After collecting thread data, we do ONE batch contact lookup for all
     * unique addresses, entirely on the native side (no MethodChannel round trips).
     */
    fun fetchThreads(context: Context, limit: Int, offset: Int): List<Map<String, Any?>> {
        // ── Step 1: Single pass through SMS to collect latest msg per thread ──
        val threadOrder = mutableListOf<Long>()           // insertion-ordered thread IDs
        val threadData  = mutableMapOf<Long, MutableMap<String, Any?>>()

        val smsCursor = context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.THREAD_ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.READ
            ),
            null, null,
            "${Telephony.Sms.DATE} DESC"
        )

        smsCursor?.use { c ->
            val idIdx       = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val threadIdIdx = c.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)
            val addressIdx  = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIdx     = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIdx     = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val readIdx     = c.getColumnIndexOrThrow(Telephony.Sms.READ)

            Log.d(TAG, "SMS cursor has ${c.count} total rows")

            while (c.moveToNext()) {
                val tid = c.getLong(threadIdIdx)

                if (tid !in threadData) {
                    threadOrder.add(tid)
                    threadData[tid] = mutableMapOf(
                        "id"           to tid,
                        "recipientIds" to "",
                        "address"      to (c.getString(addressIdx) ?: ""),
                        "snippet"      to (c.getString(bodyIdx)    ?: ""),
                        "date"         to c.getLong(dateIdx),
                        "read"         to c.getInt(readIdx),  // 0=unread for this msg
                        "messageCount" to 0,
                        "hasUnread"    to (c.getInt(readIdx) == 0)
                    )
                } else {
                    // Track unread: if ANY message in this thread is unread, mark thread unread
                    if (c.getInt(readIdx) == 0) {
                        threadData[tid]!!["hasUnread"] = true
                    }
                    threadData[tid]!!["messageCount"] = (threadData[tid]!!["messageCount"] as Int) + 1
                }

                // Stop early once we've seen enough threads (offset + limit)
                if (threadOrder.size >= offset + limit && threadData.values.all {
                    (it["messageCount"] as Int) > 0 || threadOrder.indexOf(it["id"]) < threadOrder.size - 1
                }) {
                    // We've collected all threads we need; but continue to count remaining messages
                    // Stop only if we are well past our needed threads to avoid counting thousands of msgs
                    if (threadOrder.size >= offset + limit + 20) break
                }
            }
        } ?: Log.e(TAG, "SMS content resolver returned null")

        // ── Step 2: Apply offset/limit ──
        val pagedThreadIds = threadOrder.drop(offset).take(limit)
        Log.d(TAG, "fetchThreads: ${threadOrder.size} unique threads found, returning ${pagedThreadIds.size}")

        // ── Step 3: Finalize read status (use hasUnread flag) ──
        pagedThreadIds.forEach { tid ->
            val data = threadData[tid]!!
            data["read"] = if (data["hasUnread"] as Boolean) 0 else 1
            data.remove("hasUnread")
        }

        // ── Step 4: Batch contact lookup for all unique addresses ──
        val addresses = pagedThreadIds
            .mapNotNull { tid -> threadData[tid]!!["address"] as? String }
            .filter { it.isNotEmpty() }
            .distinct()

        val contactMap = batchLookupContacts(context, addresses)
        Log.d(TAG, "Contact lookup: ${contactMap.size}/${addresses.size} resolved")

        // ── Step 5: Assemble final result ──
        return pagedThreadIds.map { tid ->
            val data    = threadData[tid]!!
            val address = data["address"] as? String ?: ""
            val contact = contactMap[address]
            data["contactName"]     = contact?.get("name")
            data["contactPhotoUri"] = contact?.get("photoUri")
            data
        }
    }

    /**
     * Batch-resolves phone numbers → contact info using ContactsContract.
     * All lookups happen here in Kotlin — zero MethodChannel round trips per contact.
     */
    fun batchLookupContacts(context: Context, addresses: List<String>): Map<String, Map<String, String?>> {
        val result = mutableMapOf<String, Map<String, String?>>()
        for (address in addresses) {
            try {
                val uri = Uri.withAppendedPath(
                    ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                    Uri.encode(address)
                )
                context.contentResolver.query(
                    uri,
                    arrayOf(
                        ContactsContract.PhoneLookup.DISPLAY_NAME,
                        ContactsContract.PhoneLookup.PHOTO_URI
                    ),
                    null, null, null
                )?.use { c ->
                    if (c.moveToFirst()) {
                        result[address] = mapOf(
                            "name"     to c.getString(0),
                            "photoUri" to c.getString(1)
                        )
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Contact lookup failed for $address: ${e.message}")
            }
        }
        return result
    }

    /**
     * Fetches messages for a single thread. Uses LIMIT/OFFSET in sortOrder —
     * this is safe on content://sms (unlike the OEM-fragmented Threads provider).
     */
    fun fetchMessages(context: Context, threadId: Long, limit: Int, offset: Int): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.THREAD_ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.READ,
                Telephony.Sms.TYPE
            ),
            "${Telephony.Sms.THREAD_ID} = ?",
            arrayOf(threadId.toString()),
            "${Telephony.Sms.DATE} DESC LIMIT $limit OFFSET $offset"
        )?.use { c ->
            Log.d(TAG, "fetchMessages(thread=$threadId): ${c.count} rows")
            val idIdx       = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val threadIdIdx = c.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)
            val addressIdx  = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIdx     = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIdx     = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val readIdx     = c.getColumnIndexOrThrow(Telephony.Sms.READ)
            val typeIdx     = c.getColumnIndexOrThrow(Telephony.Sms.TYPE)

            while (c.moveToNext()) {
                messages.add(mapOf(
                    "id"       to c.getLong(idIdx),
                    "threadId" to c.getLong(threadIdIdx),
                    "address"  to (c.getString(addressIdx) ?: ""),
                    "body"     to (c.getString(bodyIdx)    ?: ""),
                    "date"     to c.getLong(dateIdx),
                    "read"     to c.getInt(readIdx),
                    "type"     to c.getInt(typeIdx)
                ))
            }
        } ?: Log.e(TAG, "fetchMessages: null cursor for threadId=$threadId")

        return messages
    }
}
