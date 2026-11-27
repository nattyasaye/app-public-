package com.example.personalmanagement

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Minimal-work BroadcastReceiver for Android's `SMS_RECEIVED` broadcast.
 *
 * Security & privacy invariants:
 * - Never performs database I/O, heavy parsing, or periodic scheduling inside `onReceive`.
 * - Never logs raw SMS bodies or full phone numbers.
 * - Never modifies, deletes, or alters read/unread status of any SMS.
 * - Hands off each received message payload to a unique WorkManager [SmsImmediateScanWorker]
 *   request without altering the daily periodic WorkManager schedule.
 */
class SmsReceivedBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!SmsInboxBridge.hasReceiveSmsPermission(context)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val fallbackTimestamp = System.currentTimeMillis()

        if (messages.isNullOrEmpty()) {
            if (SmsInboxBridge.hasReadSmsPermission(context)) {
                SmsInboxBridge.enqueueImmediateSmsProcessing(
                    context = context,
                    sender = "",
                    body = "",
                    receivedAtUtcMillis = fallbackTimestamp,
                    fallbackToInbox = true
                )
            }
            return
        }

        // Reassemble concatenated multi-part SMS PDUs sharing the same sender & SMSC timestamp.
        val grouped = LinkedHashMap<Pair<String, Long>, StringBuilder>()
        for (part in messages) {
            val sender = part.displayOriginatingAddress
                ?.takeIf { it.isNotBlank() }
                ?: (part.originatingAddress ?: "")
            val timestampMs = if (part.timestampMillis > 0L) {
                part.timestampMillis
            } else {
                fallbackTimestamp
            }
            val partBody = part.displayMessageBody ?: part.messageBody ?: ""
            val key = Pair(sender, timestampMs)
            grouped.getOrPut(key) { StringBuilder() }.append(partBody)
        }

        var enqueuedAny = false
        for ((key, bodyBuilder) in grouped) {
            val combinedBody = bodyBuilder.toString()
            if (combinedBody.isBlank()) continue
            enqueuedAny = true
            SmsInboxBridge.enqueueImmediateSmsProcessing(
                context = context,
                sender = key.first,
                body = combinedBody,
                receivedAtUtcMillis = key.second,
                fallbackToInbox = false
            )
        }

        if (!enqueuedAny && SmsInboxBridge.hasReadSmsPermission(context)) {
            SmsInboxBridge.enqueueImmediateSmsProcessing(
                context = context,
                sender = "",
                body = "",
                receivedAtUtcMillis = fallbackTimestamp,
                fallbackToInbox = true
            )
        }
    }
}
