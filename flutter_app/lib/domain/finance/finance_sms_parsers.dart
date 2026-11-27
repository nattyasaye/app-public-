import 'dart:convert';
import 'dart:typed_data';

import '../../core/date/shared_date.dart';
import 'double_entry_engine.dart';
import 'finance_models.dart';
import 'finance_sms_models.dart';

/// Pure Dart SMS Draft Parsers & Deduplication Engine (Stage 5).
///
/// Zero Flutter UI, SQLite, or network imports.
/// SMS messages NEVER create ledger postings automatically.
class FinanceSmsParsers {
  FinanceSmsParsers._();

  static const List<int> _sha256K = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr32(int value, int bits) {
    final v = value & 0xffffffff;
    return ((v >> bits) | (v << (32 - bits))) & 0xffffffff;
  }

  /// Synchronous pure-Dart RFC 6234 SHA-256 matching Web `sha256HexSync`.
  static String sha256HexSync(String input) {
    final bytes = utf8.encode(input);
    final bitLen = bytes.length * 8;
    final bitLenHi = (bitLen ~/ 0x100000000) & 0xffffffff;
    final bitLenLo = bitLen & 0xffffffff;

    final paddedLen = ((bytes.length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, bytes.length, bytes);
    padded[bytes.length] = 0x80;

    final dataView = ByteData.sublistView(padded);
    dataView.setUint32(paddedLen - 8, bitLenHi, Endian.big);
    dataView.setUint32(paddedLen - 4, bitLenLo, Endian.big);

    final h = Uint32List.fromList(<int>[
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19,
    ]);
    final w = Uint32List(64);

    for (var offset = 0; offset < paddedLen; offset += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = dataView.getUint32(offset + i * 4, Endian.big);
      }
      for (var i = 16; i < 64; i++) {
        final s0 =
            _rotr32(w[i - 15], 7) ^ _rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 =
            _rotr32(w[i - 2], 17) ^ _rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h[0];
      var b = h[1];
      var c = h[2];
      var d = h[3];
      var e = h[4];
      var f = h[5];
      var g = h[6];
      var hh = h[7];

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (hh + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
        final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        hh = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h[0] = (h[0] + a) & 0xffffffff;
      h[1] = (h[1] + b) & 0xffffffff;
      h[2] = (h[2] + c) & 0xffffffff;
      h[3] = (h[3] + d) & 0xffffffff;
      h[4] = (h[4] + e) & 0xffffffff;
      h[5] = (h[5] + f) & 0xffffffff;
      h[6] = (h[6] + g) & 0xffffffff;
      h[7] = (h[7] + hh) & 0xffffffff;
    }

    final sb = StringBuffer();
    for (final word in h) {
      sb.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }

  static String normalizeSmsTextForFingerprint(String rawSmsText) {
    return rawSmsText.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String computeSmsFingerprint(String rawSmsText) {
    return sha256HexSync(normalizeSmsTextForFingerprint(rawSmsText));
  }

  /// Parses `"1,234.56"` -> `123456` using pure integer arithmetic.
  static int? parseSmsAmountToCents(String rawAmount) {
    final cleaned = rawAmount.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fracRaw = match.group(2) ?? '';
    final frac = int.tryParse(fracRaw.padRight(2, '0'));
    if (frac == null) return null;
    return whole * 100 + frac;
  }

  static String? maskAccountOrPhoneHint(String? rawHint) {
    if (rawHint == null) return null;
    final trimmed = rawHint.trim().replaceAll(RegExp(r'[.,;:]+$'), '');
    if (trimmed.isEmpty) return null;
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (compact.contains('*')) {
      final trailing = RegExp(r'\*+([0-9]+)$').firstMatch(compact)?.group(1);
      if (trailing != null && trailing.isNotEmpty) {
        final visible = trailing.length > 4
            ? trailing.substring(trailing.length - 4)
            : trailing;
        return '****$visible';
      }
      return compact;
    }
    final digitsOnly = compact.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 4) {
      return '****${digitsOnly.substring(digitsOnly.length - 4)}';
    }
    if (digitsOnly.length >= 2) {
      return '****$digitsOnly';
    }
    return trimmed;
  }

  /// Parses `DD/MM/YYYY HH:MM:SS` under Africa/Addis_Ababa (UTC+3, no DST).
  static ({String dateIso, DateTime timestampUtc})? parseAddisAbabaDateTime(
    String rawDateTime,
  ) {
    final match = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(rawDateTime.trim());
    if (match == null) return null;

    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }

    final checkDate = DateTime.utc(year, month, day);
    if (checkDate.year != year ||
        checkDate.month != month ||
        checkDate.day != day) {
      return null;
    }

    final utc = DateTime.utc(year, month, day, hour - 3, minute, second);
    final dateIso =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    return (dateIso: dateIso, timestampUtc: utc);
  }

  /// Offline receipt URL and reference extractor (never performs network calls).
  static ({String? receiptUrl, String? queryRef}) extractReceiptUrlAndRef(
    String rawSmsText,
  ) {
    final urlMatch =
        RegExp(r'''(https?://[^\s"'<>]+)''', caseSensitive: false)
            .firstMatch(rawSmsText);
    if (urlMatch == null) return (receiptUrl: null, queryRef: null);
    final receiptUrl =
        urlMatch.group(1)!.replaceAll(RegExp(r'[.,;\)\]]+$'), '');
    final queryMatch = RegExp(
      r'[?&](?:trx|id|ref)=([A-Za-z0-9._-]+)',
      caseSensitive: false,
    ).firstMatch(receiptUrl);
    if (queryMatch != null) {
      return (receiptUrl: receiptUrl, queryRef: queryMatch.group(1));
    }
    final pathMatch = RegExp(
      r'/receipt/([A-Za-z0-9._-]+)',
      caseSensitive: false,
    ).firstMatch(receiptUrl);
    return (receiptUrl: receiptUrl, queryRef: pathMatch?.group(1));
  }

  static String _buildDeterministicDraftId(
    SmsProvider provider,
    String fingerprint,
    String? ref,
  ) {
    final seed = ref != null && ref.isNotEmpty
        ? '${provider.dbValue}:$ref:$fingerprint'
        : fingerprint;
    final hash = sha256HexSync(seed);
    return 'sms-draft-${provider.dbValue}-${hash.substring(0, 16)}';
  }

  static String? _cleanCounterpartyName(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.,;]+$'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _extractTrailingDigitsHint(String? rawHint) {
    if (rawHint == null || rawHint.isEmpty) return null;
    final digits = rawHint.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    if (digits.length >= 2) return digits;
    return null;
  }

  static String? suggestEtbAccountForProvider(
    SmsProvider provider,
    List<AccountModel> accounts, {
    String? accountHint,
  }) {
    final spendable = accounts.where((a) {
      if (!DoubleEntryEngine.isActiveVerifiedEtbAccount(a)) return false;
      return (a.type == AccountType.asset &&
              !a.subType.isSavingsVault &&
              a.subType != AccountSubType.receivable) ||
          (a.type == AccountType.liability &&
              a.subType == AccountSubType.creditCard);
    }).toList(growable: false);
    if (spendable.isEmpty) return null;

    final keywords = switch (provider) {
      SmsProvider.cbe => const <String>['cbe', 'commercial bank'],
      SmsProvider.boa => const <String>['boa', 'abyssinia'],
      SmsProvider.telebirr => const <String>['telebirr'],
      SmsProvider.unknown => const <String>[],
    };

    final matches = spendable.where((acc) {
      final lower = acc.name.toLowerCase();
      return keywords.any(lower.contains);
    }).toList(growable: false);
    if (matches.length == 1) return matches.first.id;

    final trailingDigits = _extractTrailingDigitsHint(accountHint);
    if (trailingDigits != null) {
      final pool = matches.isNotEmpty ? matches : spendable;
      final digitMatches = pool
          .where((acc) => acc.name.contains(trailingDigits))
          .toList(growable: false);
      if (digitMatches.length == 1) return digitMatches.first.id;
    }

    if (provider == SmsProvider.telebirr) {
      final mobileAccounts = spendable
          .where((a) => a.subType == AccountSubType.mobileMoney)
          .toList(growable: false);
      if (mobileAccounts.length == 1) return mobileAccounts.first.id;
    }

    return null;
  }

  static String? suggestTransferDestinationAccount(
    FinanceSmsDraftModel draft,
    List<AccountModel> accounts,
  ) {
    final transferable = accounts.where((a) {
      if (!DoubleEntryEngine.isActiveVerifiedEtbAccount(a)) return false;
      if (draft.suggestedAccountId != null &&
          a.id == draft.suggestedAccountId) {
        return false;
      }
      return (a.type == AccountType.asset &&
              a.subType != AccountSubType.receivable) ||
          (a.type == AccountType.liability &&
              a.subType == AccountSubType.creditCard);
    }).toList(growable: false);
    if (transferable.isEmpty) return null;

    final trailingDigits = _extractTrailingDigitsHint(draft.counterpartyHint);
    if (trailingDigits != null) {
      final digitMatches = transferable
          .where((acc) => acc.name.contains(trailingDigits))
          .toList(growable: false);
      if (digitMatches.length == 1) return digitMatches.first.id;
    }

    final cpLower = draft.counterpartyName?.trim().toLowerCase();
    if (cpLower != null && cpLower.isNotEmpty) {
      final nameMatches = transferable.where((acc) {
        final accLower = acc.name.trim().toLowerCase();
        return accLower == cpLower ||
            cpLower.contains(accLower) ||
            accLower.contains(cpLower);
      }).toList(growable: false);
      if (nameMatches.length == 1) return nameMatches.first.id;
    }

    return null;
  }

  static String? suggestCategoryForDraft(
    SmsSuggestedTransactionType suggestedType,
    List<TransactionCategoryModel> categories,
  ) {
    final active =
        categories.where((c) => !c.isArchived).toList(growable: false);
    if (suggestedType == SmsSuggestedTransactionType.expense) {
      return active.where((c) => c.id == 'cat-other-exp').firstOrNull?.id ??
          active.where((c) => c.type == 'expense').firstOrNull?.id ??
          'cat-other-exp';
    }
    if (suggestedType == SmsSuggestedTransactionType.income) {
      return active.where((c) => c.id == 'cat-other-inc').firstOrNull?.id ??
          active.where((c) => c.type == 'income').firstOrNull?.id ??
          'cat-other-inc';
    }
    return null;
  }

  /// Returns a provider only when explicit brand names, official domains, or
  /// unambiguous provider-specific syntax cues match [rawSmsText].
  /// Generic phrases shared across Ethiopian banks (e.g. "was debited with ETB")
  /// return `null` here so an explicit inbox sender or user alias isn't overridden.
  static SmsProvider? detectStrongProviderCue(String rawSmsText) {
    final lower = rawSmsText.toLowerCase();
    // 1. Explicit provider brand names & official receipt domains take precedence
    if (lower.contains('telebirr') ||
        lower.contains('e-money account') ||
        lower.contains('transactioninfo.ethiotelecom.et')) {
      return SmsProvider.telebirr;
    }
    if (lower.contains('bank of abyssinia') ||
        lower.contains('cs.bankofabyssinia.com')) {
      return SmsProvider.boa;
    }
    if (lower.contains('commercial bank of ethiopia') ||
        lower.contains('apps.cbe.com.et') ||
        lower.contains('disaster recovery')) {
      return SmsProvider.cbe;
    }

    // 2. Exclusive provider syntax cues
    if (lower.contains('your transaction number is')) {
      return SmsProvider.telebirr;
    }
    if (lower.contains('is locked from your account') &&
        lower.contains('pos transaction')) {
      return SmsProvider.boa;
    }
    if (RegExp(
          r'you have successfully transferred etb\s+[0-9,.]+\s+from account',
          caseSensitive: false,
        ).hasMatch(rawSmsText) ||
        RegExp(
          r'you have received etb\s+[0-9,.]+\s+from account\s+[0-9*xX]+',
          caseSensitive: false,
        ).hasMatch(rawSmsText)) {
      return SmsProvider.cbe;
    }
    return null;
  }

  static SmsProvider? detectSmsProvider(
    String rawSmsText, {
    SmsProvider? providerHint,
  }) {
    final strongCue = detectStrongProviderCue(rawSmsText);
    if (strongCue != null) {
      return strongCue;
    }
    if (providerHint != null && providerHint != SmsProvider.unknown) {
      return providerHint;
    }
    final lower = rawSmsText.toLowerCase();
    if (lower.contains('was debited with etb') ||
        lower.contains('was credited with etb') ||
        lower.contains('has been debited with etb') ||
        lower.contains('has been credited with etb')) {
      return SmsProvider.boa;
    }
    return null;
  }

  static const List<String> _nonTransactionalNoiseMarkers = <String>[
    'pin or password is incorrect',
    'pin is incorrect',
    'invalid pin',
    'incorrect pin',
    'wrong pin',
    'wrong password',
    'pin locked',
    'pin blocked',
    'failed login',
    'password will expire',
    'never share your pin',
    'never share your password',
    'do not share your otp',
    'verification code',
    'one time password',
    'otp is',
    'security alert',
    'security tip',
    'download our',
    'special offer',
    'win a',
    'happy holiday',
    'promotion',
  ];

  static bool _hasCompletedTransactionMarker(String rawSmsText) {
    return RegExp(
          r'was (?:debited|credited) with etb',
          caseSensitive: false,
        ).hasMatch(rawSmsText) ||
        RegExp(
          r'you have successfully transferred etb',
          caseSensitive: false,
        ).hasMatch(rawSmsText) ||
        RegExp(
          r'you have (?:transferred|paid|received) etb',
          caseSensitive: false,
        ).hasMatch(rawSmsText) ||
        (RegExp(
              r'is locked from your account',
              caseSensitive: false,
            ).hasMatch(rawSmsText) &&
            RegExp(r'pos transaction', caseSensitive: false)
                .hasMatch(rawSmsText));
  }

  static bool _matchesNonTransactionalNoise(String rawSmsText) {
    if (_hasCompletedTransactionMarker(rawSmsText)) return false;
    final lower = rawSmsText.toLowerCase();
    return _nonTransactionalNoiseMarkers.any(lower.contains);
  }

  static String? _nonTransactionalIgnoreReason(
    SmsProvider provider,
    String rawSmsText,
  ) {
    if (_matchesNonTransactionalNoise(rawSmsText)) {
      return 'Ignored non-transactional ${provider.displayName} security/promotional notice.';
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // 1. Bank of Abyssinia (BOA) Parser
  // --------------------------------------------------------------------------

  static SmsParseOutcome parseBoaSms(
    String rawSmsText, {
    required DateTime receivedAtUtc,
    List<AccountModel> accounts = const [],
    List<TransactionCategoryModel> categories = const [],
  }) {
    final trimmed = rawSmsText.trim();
    final ignoreReason =
        _nonTransactionalIgnoreReason(SmsProvider.boa, trimmed);
    if (ignoreReason != null) {
      return SmsParseOutcome.ignored(
        provider: SmsProvider.boa,
        ignoreReason: ignoreReason,
      );
    }

    final fingerprint = computeSmsFingerprint(trimmed);
    final receipt = extractReceiptUrlAndRef(trimmed);
    final nowUtc = receivedAtUtc.toUtc();
    final fallbackAccountId =
        suggestEtbAccountForProvider(SmsProvider.boa, accounts);

    // POS Locked / Authorization notice — MUST NOT create a normal expense draft
    if (RegExp(r'is\s+locked\s+from\s+your\s+account', caseSensitive: false)
            .hasMatch(trimmed) ||
        RegExp(r'pos\s+transaction', caseSensitive: false).hasMatch(trimmed)) {
      final posMatch = RegExp(
        r'ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+is\s+locked\s+from\s+your\s+account\s+([0-9*xX]+).*?due\s+to\s+pos\s+transaction(?:\s+at\s+([^.\n]+))?(?:\.\s*your\s+available\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?))?',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(trimmed);

      final lockedAmount = posMatch?.group(1) != null
          ? (parseSmsAmountToCents(posMatch!.group(1)!) ?? 0)
          : 0;
      final availRaw = posMatch?.group(4) ??
          RegExp(
            r'available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
            caseSensitive: false,
          ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          availRaw != null ? parseSmsAmountToCents(availRaw) : null;
      final accountHint = maskAccountOrPhoneHint(posMatch?.group(2));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.boa,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.boa,
            fingerprint,
            receipt.queryRef,
          ),
          provider: SmsProvider.boa,
          fingerprint: fingerprint,
          transactionReference: receipt.queryRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.unknown,
          direction: SmsDirection.uncertain,
          principalCents: lockedAmount,
          accountHint: accountHint,
          counterpartyName: _cleanCounterpartyName(posMatch?.group(3)),
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: SmsParseConfidence.unrecognized,
          status: SmsDraftStatus.unrecognized,
          isNonLedgerNotice: true,
          parseNotes:
              'POS authorization lock notice — informational only; not a completed debit and cannot be posted as an expense.',
          suggestedAccountId: matchedAccountId,
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.boa,
      );
    }

    // BOA Debit
    final debitMatch = RegExp(
      r'your\s+account\s+([0-9*xX]+)\s+was\s+debited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+(?:for|to|at|by)\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (debitMatch != null) {
      final accountHint = maskAccountOrPhoneHint(debitMatch.group(1));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.boa,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final principalCents = parseSmsAmountToCents(debitMatch.group(2)!);
      final counterpartyName = _cleanCounterpartyName(debitMatch.group(3));
      final balanceRaw = RegExp(
        r'available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(
              SmsProvider.boa,
              fingerprint,
              receipt.queryRef,
            ),
            provider: SmsProvider.boa,
            fingerprint: fingerprint,
            transactionReference: receipt.queryRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.outgoing,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'BOA debit message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.boa,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.boa,
            fingerprint,
            receipt.queryRef,
          ),
          provider: SmsProvider.boa,
          fingerprint: fingerprint,
          transactionReference: receipt.queryRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.expense,
          direction: SmsDirection.outgoing,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: (receipt.queryRef != null || reportedBalance != null)
              ? SmsParseConfidence.high
              : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.expense,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.boa,
      );
    }

    // BOA Credit
    final creditMatch = RegExp(
      r'your\s+account\s+([0-9*xX]+)\s+was\s+credited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+by\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (creditMatch != null) {
      final accountHint = maskAccountOrPhoneHint(creditMatch.group(1));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.boa,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final principalCents = parseSmsAmountToCents(creditMatch.group(2)!);
      final counterpartyName = _cleanCounterpartyName(creditMatch.group(3));
      final balanceRaw = RegExp(
        r'available\s+balance(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(
              SmsProvider.boa,
              fingerprint,
              receipt.queryRef,
            ),
            provider: SmsProvider.boa,
            fingerprint: fingerprint,
            transactionReference: receipt.queryRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.incoming,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'BOA credit message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.boa,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.boa,
            fingerprint,
            receipt.queryRef,
          ),
          provider: SmsProvider.boa,
          fingerprint: fingerprint,
          transactionReference: receipt.queryRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.income,
          direction: SmsDirection.incoming,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: (receipt.queryRef != null || reportedBalance != null)
              ? SmsParseConfidence.high
              : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.income,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.boa,
      );
    }

    return SmsParseOutcome.draft(
      FinanceSmsDraftModel(
        id: _buildDeterministicDraftId(
          SmsProvider.boa,
          fingerprint,
          receipt.queryRef,
        ),
        provider: SmsProvider.boa,
        fingerprint: fingerprint,
        transactionReference: receipt.queryRef,
        receiptUrl: receipt.receiptUrl,
        suggestedType: SmsSuggestedTransactionType.unknown,
        direction: SmsDirection.uncertain,
        principalCents: 0,
        receivedAtUtc: nowUtc,
        confidence: SmsParseConfidence.unrecognized,
        status: SmsDraftStatus.unrecognized,
        isNonLedgerNotice: true,
        parseNotes:
            'Unrecognized Bank of Abyssinia message format; saved for review without posting.',
        rawSmsText: trimmed,
        createdAt: nowUtc,
        updatedAt: nowUtc,
      ),
      provider: SmsProvider.boa,
    );
  }

  // --------------------------------------------------------------------------
  // 2. Commercial Bank of Ethiopia (CBE) Parser
  // --------------------------------------------------------------------------

  static SmsParseOutcome parseCbeSms(
    String rawSmsText, {
    required DateTime receivedAtUtc,
    List<AccountModel> accounts = const [],
    List<TransactionCategoryModel> categories = const [],
  }) {
    final trimmed = rawSmsText.trim();
    final ignoreReason =
        _nonTransactionalIgnoreReason(SmsProvider.cbe, trimmed);
    if (ignoreReason != null) {
      return SmsParseOutcome.ignored(
        provider: SmsProvider.cbe,
        ignoreReason: ignoreReason,
      );
    }

    final fingerprint = computeSmsFingerprint(trimmed);
    final receipt = extractReceiptUrlAndRef(trimmed);
    final refTokenMatch = RegExp(
      r'(?:ref(?:erence)?(?:\s*no\.?)?|trx)\s*[:#]?\s*([A-Za-z0-9_-]{6,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final txRef = receipt.queryRef ?? refTokenMatch?.group(1);
    final nowUtc = receivedAtUtc.toUtc();
    final fallbackAccountId =
        suggestEtbAccountForProvider(SmsProvider.cbe, accounts);

    // CBE Outgoing
    final outgoingMatch = RegExp(
      r'you\s+have\s+successfully\s+transferred\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+account\s+([0-9*xX]+)\s+to\s+(?:account\s+)?([0-9*xX]+)(?:\s*\(([^)]+)\))?',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (outgoingMatch != null) {
      final principalCents = parseSmsAmountToCents(outgoingMatch.group(1)!);
      final accountHint = maskAccountOrPhoneHint(outgoingMatch.group(2));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.cbe,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final counterpartyHint = maskAccountOrPhoneHint(outgoingMatch.group(3));
      final counterpartyName = _cleanCounterpartyName(outgoingMatch.group(4));

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
            provider: SmsProvider.cbe,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.outgoing,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'CBE outgoing message could not parse a positive principal ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.cbe,
        );
      }

      final serviceRaw = RegExp(
        r'service\s+charge\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final vatRaw = RegExp(
        r'VAT(?:\s*\(\s*\d+(?:\.\d+)?%\s*\))?\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final disasterRaw = RegExp(
        r'Disaster\s+Recovery(?:\s+Fund)?(?:\s*\(\s*\d+(?:\.\d+)?%\s*\))?\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final totalRaw = RegExp(
        r'with\s+total\s+of\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final balanceRaw = RegExp(
        r'your\s+current\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);

      final serviceFeeCents =
          serviceRaw != null ? (parseSmsAmountToCents(serviceRaw) ?? 0) : 0;
      final vatCents =
          vatRaw != null ? (parseSmsAmountToCents(vatRaw) ?? 0) : 0;
      final otherChargesCents =
          disasterRaw != null ? (parseSmsAmountToCents(disasterRaw) ?? 0) : 0;
      final computedTotal =
          principalCents + serviceFeeCents + vatCents + otherChargesCents;
      final reportedTotal =
          totalRaw != null ? parseSmsAmountToCents(totalRaw) : null;
      final hasAmountMismatch =
          reportedTotal != null && reportedTotal != computedTotal;
      final totalAmountCents = reportedTotal ?? computedTotal;
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      final notes = <String>[];
      if (hasAmountMismatch) {
        notes.add(
          'Amount mismatch: principal + fees (${(computedTotal / 100).toStringAsFixed(2)} ETB) differs from reported total (${(reportedTotal / 100).toStringAsFixed(2)} ETB). Verify before approving.',
        );
      }
      notes.add(
        'Outgoing CBE transfer can be approved as an Expense or an Internal Transfer.',
      );

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
          provider: SmsProvider.cbe,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.expense,
          direction: SmsDirection.outgoing,
          principalCents: principalCents,
          serviceFeeCents: serviceFeeCents,
          vatCents: vatCents,
          otherChargesCents: otherChargesCents,
          totalAmountCents: totalAmountCents,
          hasAmountMismatch: hasAmountMismatch,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          counterpartyHint: counterpartyHint,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: hasAmountMismatch
              ? SmsParseConfidence.medium
              : SmsParseConfidence.high,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          parseNotes: notes.join(' '),
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.expense,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.cbe,
      );
    }

    // CBE Incoming
    final incomingMatch = RegExp(
      r'you\s+have\s+received\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+account\s+([0-9*xX]+)(?:\s*\(([^)]+)\))?\s+to\s+your\s+account\s+([0-9*xX]+)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (incomingMatch != null) {
      final principalCents = parseSmsAmountToCents(incomingMatch.group(1)!);
      final counterpartyHint = maskAccountOrPhoneHint(incomingMatch.group(2));
      final counterpartyName = _cleanCounterpartyName(incomingMatch.group(3));
      final accountHint = maskAccountOrPhoneHint(incomingMatch.group(4));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.cbe,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final balanceRaw = RegExp(
        r'your\s+current\s+balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
            provider: SmsProvider.cbe,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.incoming,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'CBE incoming message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.cbe,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
          provider: SmsProvider.cbe,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.income,
          direction: SmsDirection.incoming,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          counterpartyHint: counterpartyHint,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: SmsParseConfidence.high,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.income,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.cbe,
      );
    }

    // CBE Account Debit alert ("Your account ... was/has been debited with ETB ...")
    final debitAccountMatch = RegExp(
      r'your\s+account\s+([0-9*xX]+)\s+(?:was|has\s+been)\s+debited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+(?:for|to|at|by)\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (debitAccountMatch != null) {
      final accountHint = maskAccountOrPhoneHint(debitAccountMatch.group(1));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.cbe,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final principalCents = parseSmsAmountToCents(debitAccountMatch.group(2)!);
      final counterpartyName =
          _cleanCounterpartyName(debitAccountMatch.group(3));
      final balanceRaw = RegExp(
        r'(?:(?:your\s+)?current\s+balance|available\s+balance)(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
            provider: SmsProvider.cbe,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.outgoing,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'CBE debit message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.cbe,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
          provider: SmsProvider.cbe,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.expense,
          direction: SmsDirection.outgoing,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: (txRef != null || reportedBalance != null)
              ? SmsParseConfidence.high
              : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.expense,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.cbe,
      );
    }

    // CBE Account Credit alert ("Your account ... was/has been credited with ETB ...")
    final creditAccountMatch = RegExp(
      r'your\s+account\s+([0-9*xX]+)\s+(?:was|has\s+been)\s+credited\s+with\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)(?:\s+(?:by|from)\s+([^.\n]+?))?(?=\.(?:\s|$)|,\s|https?:|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (creditAccountMatch != null) {
      final accountHint = maskAccountOrPhoneHint(creditAccountMatch.group(1));
      final matchedAccountId = suggestEtbAccountForProvider(
            SmsProvider.cbe,
            accounts,
            accountHint: accountHint,
          ) ??
          fallbackAccountId;
      final principalCents =
          parseSmsAmountToCents(creditAccountMatch.group(2)!);
      final counterpartyName =
          _cleanCounterpartyName(creditAccountMatch.group(3));
      final balanceRaw = RegExp(
        r'(?:(?:your\s+)?current\s+balance|available\s+balance)(?:\s+is|:)\s*ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
            provider: SmsProvider.cbe,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.incoming,
            principalCents: 0,
            accountHint: accountHint,
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'CBE credit message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.cbe,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
          provider: SmsProvider.cbe,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.income,
          direction: SmsDirection.incoming,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: accountHint,
          counterpartyName: counterpartyName,
          reportedBalanceCents: reportedBalance,
          receivedAtUtc: nowUtc,
          confidence: (txRef != null || reportedBalance != null)
              ? SmsParseConfidence.high
              : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.income,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.cbe,
      );
    }

    return SmsParseOutcome.draft(
      FinanceSmsDraftModel(
        id: _buildDeterministicDraftId(SmsProvider.cbe, fingerprint, txRef),
        provider: SmsProvider.cbe,
        fingerprint: fingerprint,
        transactionReference: txRef,
        receiptUrl: receipt.receiptUrl,
        suggestedType: SmsSuggestedTransactionType.unknown,
        direction: SmsDirection.uncertain,
        principalCents: 0,
        receivedAtUtc: nowUtc,
        confidence: SmsParseConfidence.unrecognized,
        status: SmsDraftStatus.unrecognized,
        isNonLedgerNotice: true,
        parseNotes:
            'Unrecognized CBE message format; saved for review without posting.',
        rawSmsText: trimmed,
        createdAt: nowUtc,
        updatedAt: nowUtc,
      ),
      provider: SmsProvider.cbe,
    );
  }

  // --------------------------------------------------------------------------
  // 3. Telebirr Parser
  // --------------------------------------------------------------------------

  static SmsParseOutcome parseTelebirrSms(
    String rawSmsText, {
    required DateTime receivedAtUtc,
    List<AccountModel> accounts = const [],
    List<TransactionCategoryModel> categories = const [],
  }) {
    final trimmed = rawSmsText.trim();
    final ignoreReason =
        _nonTransactionalIgnoreReason(SmsProvider.telebirr, trimmed);
    if (ignoreReason != null) {
      return SmsParseOutcome.ignored(
        provider: SmsProvider.telebirr,
        ignoreReason: ignoreReason,
      );
    }

    final fingerprint = computeSmsFingerprint(trimmed);
    final receipt = extractReceiptUrlAndRef(trimmed);
    final txNoMatch = RegExp(
      r'your\s+transaction\s+number\s+is\s+([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final txRef = txNoMatch?.group(1) ?? receipt.queryRef;
    final nowUtc = receivedAtUtc.toUtc();
    final matchedAccountId =
        suggestEtbAccountForProvider(SmsProvider.telebirr, accounts);

    // Telebirr Outgoing
    final outgoingMatch = RegExp(
      r'you\s+have\s+(?:transferred|paid)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+to\s+(?:(.+?)\s*\(([^)]+)\)|(.+?))\s+on\s+(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (outgoingMatch != null) {
      final principalCents = parseSmsAmountToCents(outgoingMatch.group(1)!);
      final counterpartyName = _cleanCounterpartyName(
        outgoingMatch.group(2) ?? outgoingMatch.group(4),
      );
      final counterpartyHint = maskAccountOrPhoneHint(outgoingMatch.group(3));
      final parsedDt = parseAddisAbabaDateTime(outgoingMatch.group(5)!);

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(
              SmsProvider.telebirr,
              fingerprint,
              txRef,
            ),
            provider: SmsProvider.telebirr,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.outgoing,
            principalCents: 0,
            accountHint: 'Telebirr',
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'Telebirr outgoing message could not parse a positive principal ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.telebirr,
        );
      }

      final serviceRaw = RegExp(
        r'(?:the\s+)?service\s+fee\s+(?:is|of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final vatRaw = RegExp(
        r'(?:\d+(?:\.\d+)?%\s+)?VAT(?:\s+on\s+(?:the\s+)?service\s+fee)?\s+(?:is|of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final totalPaidRaw = RegExp(
        r'(?:with\s+)?(?:the\s+)?total(?:\s+(?:paid|deducted|amount))?(?:\s+is|\s+of)\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final balanceRaw = RegExp(
        r'your\s+current\s+(?:E-Money\s+Account\s+)?balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);

      final serviceFeeCents =
          serviceRaw != null ? (parseSmsAmountToCents(serviceRaw) ?? 0) : 0;
      final vatCents =
          vatRaw != null ? (parseSmsAmountToCents(vatRaw) ?? 0) : 0;
      final computedTotal = principalCents + serviceFeeCents + vatCents;
      final reportedTotal =
          totalPaidRaw != null ? parseSmsAmountToCents(totalPaidRaw) : null;
      final hasAmountMismatch =
          reportedTotal != null && reportedTotal != computedTotal;
      final totalAmountCents = reportedTotal ?? computedTotal;
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.telebirr,
            fingerprint,
            txRef,
          ),
          provider: SmsProvider.telebirr,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.expense,
          direction: SmsDirection.outgoing,
          principalCents: principalCents,
          serviceFeeCents: serviceFeeCents,
          vatCents: vatCents,
          totalAmountCents: totalAmountCents,
          hasAmountMismatch: hasAmountMismatch,
          accountHint: 'Telebirr',
          counterpartyName: counterpartyName,
          counterpartyHint: counterpartyHint,
          reportedBalanceCents: reportedBalance,
          transactionTimestampUtc: parsedDt?.timestampUtc,
          transactionDateIso: parsedDt?.dateIso,
          receivedAtUtc: nowUtc,
          confidence: hasAmountMismatch
              ? SmsParseConfidence.medium
              : (txRef != null && parsedDt != null)
                  ? SmsParseConfidence.high
                  : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          parseNotes: hasAmountMismatch
              ? 'Amount mismatch: principal + fees (${(computedTotal / 100).toStringAsFixed(2)} ETB) differs from reported total (${(reportedTotal / 100).toStringAsFixed(2)} ETB). Verify before approving.'
              : null,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.expense,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.telebirr,
      );
    }

    // Telebirr Incoming
    final incomingMatch = RegExp(
      r'you\s+have\s+received\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)\s+from\s+(?:(.+?)\s*\(([^)]+)\)|(.+?))\s+on\s+(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2})',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(trimmed);

    if (incomingMatch != null) {
      final principalCents = parseSmsAmountToCents(incomingMatch.group(1)!);
      final counterpartyName = _cleanCounterpartyName(
        incomingMatch.group(2) ?? incomingMatch.group(4),
      );
      final counterpartyHint = maskAccountOrPhoneHint(incomingMatch.group(3));
      final parsedDt = parseAddisAbabaDateTime(incomingMatch.group(5)!);
      final balanceRaw = RegExp(
        r'your\s+current\s+(?:E-Money\s+Account\s+)?balance\s+is\s+ETB\s+([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ).firstMatch(trimmed)?.group(1);
      final reportedBalance =
          balanceRaw != null ? parseSmsAmountToCents(balanceRaw) : null;

      if (principalCents == null || principalCents <= 0) {
        return SmsParseOutcome.draft(
          FinanceSmsDraftModel(
            id: _buildDeterministicDraftId(
              SmsProvider.telebirr,
              fingerprint,
              txRef,
            ),
            provider: SmsProvider.telebirr,
            fingerprint: fingerprint,
            transactionReference: txRef,
            receiptUrl: receipt.receiptUrl,
            suggestedType: SmsSuggestedTransactionType.unknown,
            direction: SmsDirection.incoming,
            principalCents: 0,
            accountHint: 'Telebirr',
            receivedAtUtc: nowUtc,
            confidence: SmsParseConfidence.unrecognized,
            status: SmsDraftStatus.unrecognized,
            isNonLedgerNotice: true,
            parseNotes:
                'Telebirr incoming message could not parse a positive ETB amount.',
            rawSmsText: trimmed,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          provider: SmsProvider.telebirr,
        );
      }

      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.telebirr,
            fingerprint,
            txRef,
          ),
          provider: SmsProvider.telebirr,
          fingerprint: fingerprint,
          transactionReference: txRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.income,
          direction: SmsDirection.incoming,
          principalCents: principalCents,
          totalAmountCents: principalCents,
          accountHint: 'Telebirr',
          counterpartyName: counterpartyName,
          counterpartyHint: counterpartyHint,
          reportedBalanceCents: reportedBalance,
          transactionTimestampUtc: parsedDt?.timestampUtc,
          transactionDateIso: parsedDt?.dateIso,
          receivedAtUtc: nowUtc,
          confidence: (txRef != null && parsedDt != null)
              ? SmsParseConfidence.high
              : SmsParseConfidence.medium,
          status: SmsDraftStatus.needsReview,
          isNonLedgerNotice: false,
          suggestedAccountId: matchedAccountId,
          suggestedCategoryId: suggestCategoryForDraft(
            SmsSuggestedTransactionType.income,
            categories,
          ),
          rawSmsText: trimmed,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        ),
        provider: SmsProvider.telebirr,
      );
    }

    return SmsParseOutcome.draft(
      FinanceSmsDraftModel(
        id: _buildDeterministicDraftId(
          SmsProvider.telebirr,
          fingerprint,
          txRef,
        ),
        provider: SmsProvider.telebirr,
        fingerprint: fingerprint,
        transactionReference: txRef,
        receiptUrl: receipt.receiptUrl,
        suggestedType: SmsSuggestedTransactionType.unknown,
        direction: SmsDirection.uncertain,
        principalCents: 0,
        accountHint: 'Telebirr',
        receivedAtUtc: nowUtc,
        confidence: SmsParseConfidence.unrecognized,
        status: SmsDraftStatus.unrecognized,
        isNonLedgerNotice: true,
        parseNotes:
            'Unrecognized Telebirr message format; saved for review without posting.',
        rawSmsText: trimmed,
        createdAt: nowUtc,
        updatedAt: nowUtc,
      ),
      provider: SmsProvider.telebirr,
    );
  }

  // --------------------------------------------------------------------------
  // Orchestrator & Deduplication
  // --------------------------------------------------------------------------

  static SmsParseOutcome parseFinancialSmsMessage(
    String rawSmsText, {
    SmsProvider? providerHint,
    DateTime? receivedAtUtc,
    List<AccountModel> accounts = const [],
    List<TransactionCategoryModel> categories = const [],
  }) {
    final trimmed = rawSmsText.trim();
    if (trimmed.isEmpty) {
      return const SmsParseOutcome.ignored(ignoreReason: 'Empty SMS message.');
    }

    final effectiveReceivedAt =
        (receivedAtUtc ?? EthiopiaClock.nowUtc()).toUtc();
    final detected = detectSmsProvider(trimmed, providerHint: providerHint);

    if (detected == null || detected == SmsProvider.unknown) {
      if (_matchesNonTransactionalNoise(trimmed)) {
        return const SmsParseOutcome.ignored(
          ignoreReason: 'Ignored non-transactional security/PIN/OTP message.',
        );
      }
      final fingerprint = computeSmsFingerprint(trimmed);
      final receipt = extractReceiptUrlAndRef(trimmed);
      return SmsParseOutcome.draft(
        FinanceSmsDraftModel(
          id: _buildDeterministicDraftId(
            SmsProvider.unknown,
            fingerprint,
            receipt.queryRef,
          ),
          provider: SmsProvider.unknown,
          fingerprint: fingerprint,
          transactionReference: receipt.queryRef,
          receiptUrl: receipt.receiptUrl,
          suggestedType: SmsSuggestedTransactionType.unknown,
          direction: SmsDirection.uncertain,
          principalCents: 0,
          receivedAtUtc: effectiveReceivedAt,
          confidence: SmsParseConfidence.unrecognized,
          status: SmsDraftStatus.unrecognized,
          isNonLedgerNotice: true,
          parseNotes:
              'Unable to identify provider (CBE, Telebirr, or BOA). Select a provider or verify message text.',
          rawSmsText: trimmed,
          createdAt: effectiveReceivedAt,
          updatedAt: effectiveReceivedAt,
        ),
        provider: SmsProvider.unknown,
      );
    }

    switch (detected) {
      case SmsProvider.boa:
        return parseBoaSms(
          trimmed,
          receivedAtUtc: effectiveReceivedAt,
          accounts: accounts,
          categories: categories,
        );
      case SmsProvider.cbe:
        return parseCbeSms(
          trimmed,
          receivedAtUtc: effectiveReceivedAt,
          accounts: accounts,
          categories: categories,
        );
      case SmsProvider.telebirr:
        return parseTelebirrSms(
          trimmed,
          receivedAtUtc: effectiveReceivedAt,
          accounts: accounts,
          categories: categories,
        );
      case SmsProvider.unknown:
        return const SmsParseOutcome.ignored(
          ignoreReason: 'Unknown SMS provider.',
        );
    }
  }

  static SmsDeduplicationResult findDuplicateDraft(
    FinanceSmsDraftModel candidate,
    List<FinanceSmsDraftModel> existingDrafts,
  ) {
    final candidateRef = candidate.transactionReference?.trim().toLowerCase();
    if (candidateRef != null && candidateRef.isNotEmpty) {
      for (final existing in existingDrafts) {
        if (existing.provider == candidate.provider &&
            existing.transactionReference?.trim().toLowerCase() ==
                candidateRef) {
          return SmsDeduplicationResult(
            isDuplicate: true,
            existingDraft: existing,
            matchedBy: 'provider_reference',
          );
        }
      }
    }

    for (final existing in existingDrafts) {
      if (existing.fingerprint == candidate.fingerprint) {
        return SmsDeduplicationResult(
          isDuplicate: true,
          existingDraft: existing,
          matchedBy: 'fingerprint',
        );
      }
    }

    return const SmsDeduplicationResult(isDuplicate: false);
  }

  static String buildDefaultDraftDescription(FinanceSmsDraftModel draft) {
    final providerLabel = draft.provider.displayName;
    final refPart = draft.transactionReference != null &&
            draft.transactionReference!.isNotEmpty
        ? ' (${draft.transactionReference})'
        : '';
    if (draft.counterpartyName != null && draft.counterpartyName!.isNotEmpty) {
      if (draft.direction == SmsDirection.incoming) {
        return '$providerLabel from ${draft.counterpartyName}$refPart';
      }
      return '$providerLabel to ${draft.counterpartyName}$refPart';
    }
    if (draft.direction == SmsDirection.incoming) {
      return '$providerLabel credit$refPart';
    }
    if (draft.direction == SmsDirection.outgoing) {
      return '$providerLabel debit$refPart';
    }
    return '$providerLabel SMS$refPart';
  }

  static CalendarDate resolveDefaultDraftOccurrenceDate(
    FinanceSmsDraftModel draft,
  ) {
    final explicit = draft.transactionDateIso != null
        ? CalendarDate.tryParse(draft.transactionDateIso)
        : null;
    if (explicit != null) return explicit;
    final addis = draft.receivedAtUtc.toUtc().add(const Duration(hours: 3));
    return CalendarDate.fromYmd(addis.year, addis.month, addis.day);
  }

  static String? validateDraftApproval({
    required FinanceSmsDraftModel draft,
    required SmsSuggestedTransactionType finalType,
    required String accountId,
    String? destinationAccountId,
  }) {
    if (draft.status == SmsDraftStatus.approved) {
      return 'This SMS draft has already been approved and posted to the ledger.';
    }
    if (draft.status == SmsDraftStatus.dismissed) {
      return 'Dismissed SMS drafts cannot be approved directly.';
    }
    if (draft.status == SmsDraftStatus.unrecognized ||
        draft.isNonLedgerNotice ||
        finalType == SmsSuggestedTransactionType.unknown) {
      return draft.parseNotes ??
          'Informational or unrecognized SMS notices cannot be posted automatically.';
    }
    if (draft.principalCents <= 0) {
      return 'Draft principal amount must be greater than zero ETB.';
    }
    if (accountId.trim().isEmpty) {
      return 'Select an active ETB account before approving.';
    }
    if (finalType == SmsSuggestedTransactionType.transfer) {
      if (destinationAccountId == null || destinationAccountId.trim().isEmpty) {
        return 'Select a destination ETB account for the transfer.';
      }
      if (destinationAccountId.trim() == accountId.trim()) {
        return 'Source and destination accounts must be distinct.';
      }
    }
    return null;
  }

  static String _formatCentsFixed(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }

  static String formatFeeBreakdownNote(
    FinanceSmsDraftModel draft,
    String defaultLabel,
  ) {
    final parts = <String>[];
    if (draft.serviceFeeCents > 0) {
      parts.add('Service fee: ETB ${_formatCentsFixed(draft.serviceFeeCents)}');
    }
    if (draft.vatCents > 0) {
      parts.add('VAT: ETB ${_formatCentsFixed(draft.vatCents)}');
    }
    if (draft.otherChargesCents > 0) {
      parts.add(
        'Disaster Recovery / Other: ETB ${_formatCentsFixed(draft.otherChargesCents)}',
      );
    }
    if (parts.isEmpty) return defaultLabel;
    return '$defaultLabel (${parts.join(', ')})';
  }
}
