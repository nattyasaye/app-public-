import 'dart:convert';

import 'finance_models.dart';
import 'finance_sms_models.dart';
import 'finance_sms_parsers.dart';

/// Pure Dart Stage 6 SMS Inbox Filtering, Windowing, and Checkpoint Policy.
///
/// Zero Flutter UI, SQLite, MethodChannel, or network imports.
/// Reuses Stage 5 [FinanceSmsParsers] exclusively for provider body parsing
/// and deduplication.
class FinanceSmsInboxScanner {
  FinanceSmsInboxScanner._();

  static const Duration defaultInitialLookback = Duration(days: 7);
  static const Duration defaultCheckpointOverlap = Duration(minutes: 20);
  static const Duration defaultForegroundCatchUpThreshold = Duration(hours: 25);
  static const Duration defaultForegroundAttemptCooldown = Duration(minutes: 5);

  /// Computes the inclusive inbox read lower bound (`DATE >= sinceUtc`).
  ///
  /// When a prior checkpoint exists, subtracts [overlap] (default 20 minutes)
  /// to protect against Android SMS timestamp skew or interrupted runs while
  /// relying on Stage 5 deduplication to avoid duplicate drafts.
  /// When no checkpoint exists yet, performs a bounded [initialLookback] (7 days).
  static DateTime computeInboxReadWindowStartUtc({
    DateTime? checkpointUtc,
    required DateTime nowUtc,
    Duration initialLookback = defaultInitialLookback,
    Duration overlap = defaultCheckpointOverlap,
  }) {
    final normalizedNow = nowUtc.toUtc();
    if (checkpointUtc == null) {
      return normalizedNow.subtract(initialLookback);
    }
    return checkpointUtc.toUtc().subtract(overlap);
  }

  /// Computes a bounded inbox query window for an incoming `SMS_RECEIVED` event
  /// fallback scan so the newly received message is always included even if its
  /// timestamp is close to (or slightly earlier than) [checkpointUtc].
  static DateTime computeIncomingEventFallbackWindowStartUtc({
    required DateTime eventReceivedAtUtc,
    DateTime? checkpointUtc,
    Duration overlap = defaultCheckpointOverlap,
  }) {
    final eventWindowStart = eventReceivedAtUtc.toUtc().subtract(overlap);
    if (checkpointUtc == null) {
      return eventWindowStart;
    }
    final checkpointWindowStart = checkpointUtc.toUtc().subtract(overlap);
    return eventWindowStart.isBefore(checkpointWindowStart)
        ? eventWindowStart
        : checkpointWindowStart;
  }

  /// Determines whether opening or resuming Daywell should run a foreground
  /// catch-up inbox scan.
  ///
  /// Disabling the periodic WorkManager toggle (`dailyScanEnabled = false`)
  /// stops background scheduling only; manual scans and foreground catch-up
  /// remain enabled whenever `READ_SMS` permission is granted.
  static bool shouldRunForegroundCatchUp({
    required bool isPermissionGranted,
    required SmsScanCheckpointState checkpoint,
    required DateTime nowUtc,
    Duration catchUpThreshold = defaultForegroundCatchUpThreshold,
    Duration attemptCooldown = defaultForegroundAttemptCooldown,
  }) {
    if (!isPermissionGranted) {
      return false;
    }
    final normalizedNow = nowUtc.toUtc();
    final lastAttempt = checkpoint.lastScanAttemptUtc?.toUtc();
    if (lastAttempt != null &&
        normalizedNow.difference(lastAttempt) < attemptCooldown) {
      return false;
    }
    final lastSuccess = checkpoint.lastSuccessUtc?.toUtc();
    if (lastSuccess == null) {
      return true;
    }
    return normalizedNow.difference(lastSuccess) >= catchUpThreshold;
  }

  static String normalizeSenderKey(String rawSender) {
    return rawSender.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _tokenizeSenderKey(String rawSender) {
    return rawSender
        .trim()
        .replaceAll(RegExp(r'[_\-./]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  static String _compactSenderKey(String rawSender) {
    return rawSender
        .trim()
        .replaceAll(RegExp(r'[\s\-\(\)]+'), '')
        .toLowerCase();
  }

  static Map<String, SmsProvider> parseSenderAliasesJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <String, SmsProvider>{};
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const <String, SmsProvider>{};
      final out = <String, SmsProvider>{};
      decoded.forEach((key, value) {
        final normalized = normalizeSenderKey(key.toString());
        final provider = SmsProvider.fromDbValue(value?.toString());
        if (normalized.isNotEmpty && provider != SmsProvider.unknown) {
          out[normalized] = provider;
        }
      });
      return Map<String, SmsProvider>.unmodifiable(out);
    } catch (_) {
      return const <String, SmsProvider>{};
    }
  }

  static String encodeSenderAliasesJson(Map<String, SmsProvider> aliases) {
    final clean = <String, String>{};
    aliases.forEach((key, value) {
      final normalized = normalizeSenderKey(key);
      if (normalized.isNotEmpty && value != SmsProvider.unknown) {
        clean[normalized] = value.dbValue;
      }
    });
    return jsonEncode(clean);
  }

  static SmsProvider? _lookupAlias(
    String senderAddress,
    Map<String, SmsProvider> userAliases,
  ) {
    if (userAliases.isEmpty) return null;
    final normalized = normalizeSenderKey(senderAddress);
    final compact = _compactSenderKey(senderAddress);
    for (final entry in userAliases.entries) {
      final keyNorm = normalizeSenderKey(entry.key);
      final keyCompact = _compactSenderKey(entry.key);
      if (entry.value == SmsProvider.unknown) continue;
      if (keyNorm == normalized ||
          (keyCompact.isNotEmpty && keyCompact == compact)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Detects personal mobile / international phone numbers (8+ digits or
  /// leading `+` with 7+ digits) so person-to-person SMS messages are skipped
  /// unless explicitly mapped in [userAliases].
  static bool isLikelyPersonalPhoneNumber(String rawSender) {
    final trimmed = rawSender.trim();
    if (trimmed.isEmpty) return false;
    final compact = trimmed.replaceAll(RegExp(r'[\s\-\(\)\.]+'), '');
    if (compact.startsWith('+')) {
      final digits = compact.substring(1);
      return RegExp(r'^\d{7,15}$').hasMatch(digits);
    }
    return RegExp(r'^\d{8,15}$').hasMatch(compact);
  }

  static const List<String> _knownCompetingProviderKeywords = <String>[
    'dashen',
    'awash',
    'zemen',
    'wegagen',
    'hibret',
    'nib',
    'enat',
    'oromia',
    'bunna',
    'berhan',
    'abay',
    'amole',
    'mpesa',
    'm-pesa',
    'chapa',
    'santim',
    'kacha',
    'coop',
    'siinqee',
    'tsedey',
    'hijra',
    'zamzam',
    'cbebirr',
  ];

  static bool _isKnownCompetingProviderSender(String rawSender) {
    final norm = _tokenizeSenderKey(rawSender);
    if (norm.isEmpty) return false;
    final compact = norm.replaceAll(' ', '');
    return _knownCompetingProviderKeywords.any(
      (kw) => norm.contains(kw) || compact.contains(kw.replaceAll('-', '')),
    );
  }

  static SmsProvider? detectExplicitProviderBrandInBody(String rawSmsText) {
    final lower = rawSmsText.toLowerCase();
    if (lower.contains('telebirr') ||
        lower.contains('transactioninfo.ethiotelecom.et') ||
        lower.contains('e-money account')) {
      return SmsProvider.telebirr;
    }
    if (lower.contains('bank of abyssinia') ||
        lower.contains('cs.bankofabyssinia.com')) {
      return SmsProvider.boa;
    }
    if (lower.contains('commercial bank of ethiopia') ||
        lower.contains('apps.cbe.com.et')) {
      return SmsProvider.cbe;
    }
    return null;
  }

  static SmsProvider? detectProviderFromCanonicalSenderName(String rawSender) {
    final norm = _tokenizeSenderKey(rawSender);
    if (norm.isEmpty) return null;

    if (norm == 'telebirr' ||
        norm == 'ethiotelecom' ||
        RegExp(r'\btelebirr\b').hasMatch(norm)) {
      return SmsProvider.telebirr;
    }

    if (norm == 'boa' ||
        norm == 'bank of abyssinia' ||
        norm == 'bankofabyssinia' ||
        norm == 'abyssinia' ||
        RegExp(r'\b(boa|abyssinia)\b').hasMatch(norm)) {
      return SmsProvider.boa;
    }

    // Keep "cbebirr" excluded from direct CBE brand auto-match unless user-aliased
    // or explicitly matched by CBE body markers.
    if (norm == 'cbe' ||
        norm == 'commercial bank of ethiopia' ||
        norm == 'commercialbankofethiopia' ||
        RegExp(r'\bcbe\b').hasMatch(norm) ||
        norm.contains('commercial bank of ethiopia')) {
      return SmsProvider.cbe;
    }

    return null;
  }

  static SmsSenderIdentification identifyTargetSenderAndProvider(
    String senderAddress,
    String rawBody, {
    Map<String, SmsProvider> userAliases = const <String, SmsProvider>{},
  }) {
    final strongBodyProvider =
        FinanceSmsParsers.detectStrongProviderCue(rawBody);
    final bodyProvider = FinanceSmsParsers.detectSmsProvider(rawBody);
    final explicitBodyBrand = detectExplicitProviderBrandInBody(rawBody);

    final aliasedProvider = _lookupAlias(senderAddress, userAliases);
    if (aliasedProvider != null) {
      if (strongBodyProvider != null && strongBodyProvider != aliasedProvider) {
        return const SmsSenderIdentification.rejected(
          'Conflicting sender alias and SMS message provider.',
        );
      }
      return SmsSenderIdentification.accepted(
        provider: aliasedProvider,
        matchedBy: 'sender_alias',
      );
    }

    final canonicalSenderProvider =
        detectProviderFromCanonicalSenderName(senderAddress);
    if (canonicalSenderProvider != null) {
      if (strongBodyProvider != null &&
          strongBodyProvider != canonicalSenderProvider) {
        return const SmsSenderIdentification.rejected(
          'Conflicting named sender and SMS message provider.',
        );
      }
      return SmsSenderIdentification.accepted(
        provider: canonicalSenderProvider,
        matchedBy: 'canonical_sender',
      );
    }

    if (isLikelyPersonalPhoneNumber(senderAddress)) {
      return const SmsSenderIdentification.rejected(
        'Skipped personal phone number sender.',
      );
    }

    if (_isKnownCompetingProviderSender(senderAddress)) {
      return const SmsSenderIdentification.rejected(
        'Skipped competing financial provider sender.',
      );
    }

    final trimmedSender = senderAddress.trim();
    if (trimmedSender.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(trimmedSender)) {
      if (explicitBodyBrand != null) {
        return SmsSenderIdentification.accepted(
          provider: explicitBodyBrand,
          matchedBy: 'explicit_body_brand',
        );
      }
      return const SmsSenderIdentification.rejected(
        'Skipped non-target named sender.',
      );
    }

    if (bodyProvider != null) {
      return SmsSenderIdentification.accepted(
        provider: bodyProvider,
        matchedBy: 'message_body',
      );
    }

    return const SmsSenderIdentification.rejected(
      'Sender and body did not match CBE, Telebirr, or BOA.',
    );
  }

  static final List<RegExp> _failedOrDeclinedPatterns = <RegExp>[
    RegExp(r'\btransaction\s+(?:has\s+)?failed\b', caseSensitive: false),
    RegExp(r'\b(?:payment|transfer)\s+(?:has\s+)?failed\b', caseSensitive: false),
    RegExp(r'\btransaction\s+(?:was\s+)?declined\b', caseSensitive: false),
    RegExp(r'\bdeclined\s+due\s+to\b', caseSensitive: false),
    RegExp(r'\binsufficient\s+(?:balance|funds)\b', caseSensitive: false),
    RegExp(r'\bnot\s+enough\s+balance\b', caseSensitive: false),
    RegExp(r'\bunsuccessful\s+transaction\b', caseSensitive: false),
    RegExp(r'\b(?:could\s+not|unable\s+to)\s+(?:process|complete)\b',
        caseSensitive: false),
    RegExp(r'\btransaction\s+(?:is\s+)?(?:cancelled|canceled|rejected)\b',
        caseSensitive: false),
  ];

  static bool isFailedOrDeclinedSms(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return false;
    final isBoaPosLock =
        RegExp(r'is\s+locked\s+from\s+your\s+account', caseSensitive: false)
                .hasMatch(trimmed) &&
            RegExp(r'pos\s+transaction', caseSensitive: false)
                .hasMatch(trimmed);
    if (isBoaPosLock) return false;
    return _failedOrDeclinedPatterns.any((re) => re.hasMatch(trimmed));
  }

  /// Evaluates a single Android inbox SMS without logging raw text or sender PII.
  /// Returns a draft outcome (either `needs_review` or `unrecognized`) only for
  /// validated CBE, Telebirr, or BOA messages, or `ignored` safely otherwise.
  static SmsParseOutcome evaluateInboxMessage(
    SmsInboxMessage message, {
    Map<String, SmsProvider> userAliases = const <String, SmsProvider>{},
    List<AccountModel> accounts = const <AccountModel>[],
    List<TransactionCategoryModel> categories = const <TransactionCategoryModel>[],
  }) {
    final trimmedBody = message.body.trim();
    if (trimmedBody.isEmpty) {
      return const SmsParseOutcome.ignored(ignoreReason: 'Empty SMS message.');
    }

    final identification = identifyTargetSenderAndProvider(
      message.senderAddress,
      trimmedBody,
      userAliases: userAliases,
    );
    if (!identification.isTargetFinancialMessage ||
        identification.provider == null) {
      return SmsParseOutcome.ignored(
        ignoreReason:
            identification.rejectReason ?? 'Ignored non-target SMS sender.',
      );
    }

    if (isFailedOrDeclinedSms(trimmedBody)) {
      return SmsParseOutcome.ignored(
        provider: identification.provider,
        ignoreReason: 'Ignored failed, declined, or insufficient-balance notice.',
      );
    }

    return FinanceSmsParsers.parseFinancialSmsMessage(
      trimmedBody,
      providerHint: identification.provider,
      receivedAtUtc: message.receivedAtUtc,
      accounts: accounts,
      categories: categories,
    );
  }

  /// Deterministic chronological ascending sort by inbox `receivedAtUtc`.
  static List<SmsInboxMessage> sortMessagesChronologically(
    List<SmsInboxMessage> messages,
  ) {
    final sorted = List<SmsInboxMessage>.from(messages);
    sorted.sort((a, b) {
      final timeCmp = a.receivedAtUtc.compareTo(b.receivedAtUtc);
      if (timeCmp != 0) return timeCmp;
      final aInt = int.tryParse(a.deviceMessageId);
      final bInt = int.tryParse(b.deviceMessageId);
      if (aInt != null && bInt != null) {
        return aInt.compareTo(bInt);
      }
      return a.deviceMessageId.compareTo(b.deviceMessageId);
    });
    return List<SmsInboxMessage>.unmodifiable(sorted);
  }
}
