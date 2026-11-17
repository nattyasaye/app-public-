import 'package:flutter/material.dart';

import '../../../core/date/shared_date.dart';
import '../../../domain/finance/double_entry_engine.dart';
import '../../../domain/finance/finance_models.dart';

/// Integer-safe formatting and parsing helpers for Daywell Finance UI.
class FinanceUiFormatters {
  const FinanceUiFormatters._();

  static String formatEtbCents(
    int cents, {
    bool includePlusSign = false,
    bool showCurrency = true,
  }) {
    final isNegative = cents < 0;
    final absCents = cents.abs();
    final whole = absCents ~/ 100;
    final frac = (absCents % 100).toString().padLeft(2, '0');
    final wholeFormatted = _formatWithCommas(whole);
    final sign = isNegative ? '-' : (includePlusSign && cents > 0 ? '+' : '');
    final suffix = showCurrency ? ' ETB' : '';
    return '$sign$wholeFormatted.$frac$suffix';
  }

  static String currencyDisplayLabel(String? currencyCode) {
    final tier = DoubleEntryEngine.classifyCurrencyCode(currencyCode);
    switch (tier) {
      case CurrencyValidationTier.verifiedEtb:
        return 'ETB';
      case CurrencyValidationTier.verifiedNonEtb:
        return DoubleEntryEngine.normalizeCurrencyCode(currencyCode);
      case CurrencyValidationTier.unverified:
        return 'Unverified';
    }
  }

  static String formatCurrencyCents(
    int cents, {
    String? currencyCode,
    bool includePlusSign = false,
    bool showCurrency = true,
  }) {
    final base = formatEtbCents(
      cents,
      includePlusSign: includePlusSign,
      showCurrency: false,
    );
    if (!showCurrency) return base;
    final tier = DoubleEntryEngine.classifyCurrencyCode(currencyCode);
    switch (tier) {
      case CurrencyValidationTier.verifiedEtb:
        return '$base ETB';
      case CurrencyValidationTier.verifiedNonEtb:
        return '$base ${DoubleEntryEngine.normalizeCurrencyCode(currencyCode)}';
      case CurrencyValidationTier.unverified:
        return '$base (Unverified)';
    }
  }

  static String _formatWithCommas(int number) {
    final raw = number.toString();
    if (raw.length <= 3) return raw;
    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final posFromEnd = raw.length - i;
      if (i > 0 && posFromEnd % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(raw[i]);
    }
    return buffer.toString();
  }

  /// Decimal-safe parser avoiding floating point rounding drift (ETB -> cents).
  static int? parseEtbToCents(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fracRaw = match.group(2) ?? '';
    if (fracRaw.length > 2) return null;
    final fracPadded = fracRaw.padRight(2, '0');
    final frac = fracPadded.isEmpty ? 0 : int.tryParse(fracPadded);
    if (frac == null) return null;
    return (whole * 100) + frac;
  }

  static String formatCentsAsInput(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }

  static String accountSubTypeLabel(AccountSubType subType) {
    switch (subType) {
      case AccountSubType.cash:
        return 'Cash';
      case AccountSubType.bank:
        return 'Bank Account';
      case AccountSubType.mobileMoney:
        return 'Mobile Money';
      case AccountSubType.savingsVault:
        return 'Savings Vault';
      case AccountSubType.creditCard:
        return 'Credit Card';
      case AccountSubType.receivable:
        return 'Receivable Control';
      case AccountSubType.payable:
        return 'Payable Control';
      case AccountSubType.openingEquity:
        return 'Opening Equity';
      case AccountSubType.nominalIncome:
        return 'Income Control';
      case AccountSubType.nominalExpense:
        return 'Expense Control';
      case AccountSubType.legacyClearing:
        return 'Legacy Clearing';
    }
  }

  static IconData accountSubTypeIcon(AccountSubType subType) {
    switch (subType) {
      case AccountSubType.cash:
        return Icons.payments_outlined;
      case AccountSubType.bank:
        return Icons.account_balance_outlined;
      case AccountSubType.mobileMoney:
        return Icons.smartphone_outlined;
      case AccountSubType.savingsVault:
        return Icons.savings_outlined;
      case AccountSubType.creditCard:
        return Icons.credit_card_outlined;
      case AccountSubType.receivable:
        return Icons.call_received_outlined;
      case AccountSubType.payable:
        return Icons.call_made_outlined;
      case AccountSubType.openingEquity:
      case AccountSubType.nominalIncome:
      case AccountSubType.nominalExpense:
      case AccountSubType.legacyClearing:
        return Icons.account_tree_outlined;
    }
  }

  static Color parseColorHex(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      if (value != null) return Color(value);
    } else if (cleaned.length == 8) {
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  static Future<CalendarDate?> pickCalendarDate(
    BuildContext context, {
    required CalendarDate initialDate,
    CalendarDate? firstDate,
    CalendarDate? lastDate,
  }) async {
    final first = firstDate ?? CalendarDate(year: 2015, month: 1, day: 1);
    final last = lastDate ?? CalendarDate(year: 2040, month: 12, day: 31);
    final clampedInitial = initialDate.jdn < first.jdn
        ? first
        : (initialDate.jdn > last.jdn ? last : initialDate);

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        clampedInitial.year,
        clampedInitial.month,
        clampedInitial.day,
      ),
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
    );
    if (picked == null) return null;
    return CalendarDate.fromDateComponents(picked);
  }

  static String formatCategoryBreadcrumb(
    String? categoryId,
    Map<String, TransactionCategoryModel> categoryById,
  ) {
    if (categoryId == null) return 'Uncategorized';
    final category = categoryById[categoryId];
    if (category == null) return categoryId;
    final parentId = category.parentId;
    if (parentId != null && categoryById.containsKey(parentId)) {
      return '${categoryById[parentId]!.name} > ${category.name}';
    }
    return category.name;
  }

  static List<DropdownMenuItem<String>> buildCategoryDropdownItems(
    List<TransactionCategoryModel> categories, {
    required String type,
    bool includeArchived = false,
  }) {
    final filtered = categories
        .where(
          (c) => c.type == type && (includeArchived || !c.isArchived),
        )
        .toList()
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });

    final parents = filtered
        .where((c) =>
            c.parentId == null || !filtered.any((p) => p.id == c.parentId))
        .toList();

    final items = <DropdownMenuItem<String>>[];
    for (final parent in parents) {
      items.add(
        DropdownMenuItem<String>(
          value: parent.id,
          child: Text(
            parent.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      final children = filtered.where((c) => c.parentId == parent.id);
      for (final child in children) {
        items.add(
          DropdownMenuItem<String>(
            value: child.id,
            child: Text(
              '  └ ${child.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
    return items;
  }

  static String formatEntryTypeLabel(EntryType type) {
    switch (type) {
      case EntryType.standard:
        return 'Standard';
      case EntryType.transfer:
        return 'Transfer';
      case EntryType.splitExpense:
        return 'Split';
      case EntryType.debtIssuance:
        return 'Debt';
      case EntryType.settlement:
        return 'Settlement';
      case EntryType.adjustment:
        return 'Adjustment';
      case EntryType.writeOff:
        return 'Write-Off';
    }
  }
}
