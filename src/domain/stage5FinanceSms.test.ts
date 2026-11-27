import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';
import {
  Account,
  calculateAccountBalance,
  DoubleEntryValidationError,
  FOUNDATION_DEFAULT_EXPENSE_CATEGORIES,
  FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  JournalEntry,
  Posting,
  summarizeDirectExpense,
  TransactionCategory,
} from './doubleEntryFinance';
import {
  calculateAvailableToSpendBreakdownV7,
  calculateCanonicalCategorySpendV7,
  calculatePeriodComparisonReportV7,
  ensureSystemControlAccounts,
  resolveReportPeriodWithComparisonV7,
  SharedSavingsGoal,
} from './financeV7Engine';
import { SYSTEM_CONTROL_ACCOUNT_IDS } from './sharedFoundation';
import {
  buildApprovedSmsLedgerEntry,
  canApproveSmsDraft,
  extractReceiptUrlAndRef,
  FinanceSmsDraft,
  findDuplicateSmsDraft,
  maskAccountOrPhoneHint,
  parseAddisAbabaDateTime,
  parseFinancialSmsMessage,
  parseSmsAmountToCents,
  resolveDefaultDraftOccurrenceDate,
  sha256HexSync,
  totalDraftFeesCents,
} from './financeSms';
import {
  FINANCE_SMS_DRAFTS_STORAGE_KEY,
  FINANCE_SMS_PENDING_APPROVAL_KEY,
  FinanceSmsService,
  splitSmsBatchInput,
} from '../services/financeSmsService';
import { SharedStateBridge } from '../services/sharedStateBridge';
import { DataPortabilityService } from '../services/dataPortabilityService';

function withMockBrowserStorage(
  fn: (store: Map<string, string>) => void | Promise<void>
): Promise<void> {
  const store = new Map<string, string>();
  const prevWindow = (globalThis as any).window;
  const prevLocalStorage = (globalThis as any).localStorage;

  const mockStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => void store.set(k, String(v)),
    removeItem: (k: string) => void store.delete(k),
    clear: () => void store.clear(),
  };

  (globalThis as any).localStorage = mockStorage;
  (globalThis as any).window = {
    dispatchEvent: () => true,
    CustomEvent: class CustomEvent {
      type: string;
      detail: unknown;
      constructor(type: string, init?: { detail?: unknown }) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
  };

  return Promise.resolve(fn(store)).finally(() => {
    (globalThis as any).window = prevWindow;
    (globalThis as any).localStorage = prevLocalStorage;
  });
}

function makeTestAccounts(): Account[] {
  return ensureSystemControlAccounts([
    {
      id: 'acc-cbe',
      name: 'CBE Checking 5678',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 2000000, // 20,000.00 ETB
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-boa',
      name: 'BOA Savings 4321',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'ETB',
      openingBalanceCents: 1500000, // 15,000.00 ETB
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-telebirr',
      name: 'Telebirr Wallet',
      type: 'asset',
      subType: 'mobile_money',
      currencyCode: 'ETB',
      openingBalanceCents: 500000, // 5,000.00 ETB
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-vault',
      name: 'House Vault',
      type: 'asset',
      subType: 'savings_vault',
      currencyCode: 'ETB',
      openingBalanceCents: 100000, // 1,000.00 ETB
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
    {
      id: 'acc-usd',
      name: 'USD Account',
      type: 'asset',
      subType: 'bank',
      currencyCode: 'USD',
      openingBalanceCents: 50000,
      openingBalanceDate: '2026-01-01',
      isArchived: false,
      createdAt: '2026-01-01T00:00:00Z',
    },
  ]);
}

function makeTestCategories(): TransactionCategory[] {
  return [
    ...FOUNDATION_DEFAULT_EXPENSE_CATEGORIES.filter((c) => c.id !== 'cat-fees'),
    ...FOUNDATION_DEFAULT_INCOME_CATEGORIES,
  ];
}

describe('STAGE 5 — FINANCE SMS DRAFT FOUNDATION & PROVIDER PARSERS', () => {
  it('1. Low-level helpers: integer cents, SHA-256 fingerprint, masking, Addis Ababa UTC+3, offline receipt extraction', () => {
    assert.strictEqual(parseSmsAmountToCents('2,000.00'), 200000);
    assert.strictEqual(parseSmsAmountToCents('0.13'), 13);
    assert.strictEqual(parseSmsAmountToCents('1500'), 150000);
    assert.strictEqual(parseSmsAmountToCents('abc'), null);

    // RFC 6234 SHA-256 vector for "abc"
    assert.strictEqual(
      sha256HexSync('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    );

    assert.strictEqual(maskAccountOrPhoneHint('100012345678'), '****5678');
    assert.strictEqual(maskAccountOrPhoneHint('251911223344'), '****3344');
    assert.strictEqual(maskAccountOrPhoneHint('1****4321'), '****4321');

    // 22/11/2026 01:30:00 in Addis Ababa (UTC+3) is 2026-11-21T22:30:00.000Z,
    // while civil date in Ethiopia remains 2026-11-22!
    const dt = parseAddisAbabaDateTime('22/11/2026 01:30:00');
    assert.ok(dt);
    assert.strictEqual(dt.dateIso, '2026-11-22');
    assert.strictEqual(dt.timestampUtcIso, '2026-11-21T22:30:00.000Z');

    const boaUrl = extractReceiptUrlAndRef(
      'View receipt https://cs.bankofabyssinia.com/slip/?trx=FT26330ABCD1.'
    );
    assert.strictEqual(boaUrl.receiptUrl, 'https://cs.bankofabyssinia.com/slip/?trx=FT26330ABCD1');
    assert.strictEqual(boaUrl.queryRef, 'FT26330ABCD1');
  });

  it('2. Bank of Abyssinia (BOA): debit, credit, POS lock authorization hold (never expense), and non-transactional ignore', () => {
    const accounts = makeTestAccounts();
    const categories = makeTestCategories();
    const receivedAtUtc = '2026-11-22T10:00:00.000Z';

    // BOA Debit with receipt URL
    const debitSms =
      'Dear customer, your account 1****4321 was debited with ETB 450.50 for Merchant Payment. Available Balance: ETB 14,549.50. Receipt: https://cs.bankofabyssinia.com/slip/?trx=FT26326BOA01';
    const debitOut = parseFinancialSmsMessage(debitSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(debitOut.kind, 'draft');
    assert.strictEqual(debitOut.draft?.provider, 'boa');
    assert.strictEqual(debitOut.draft?.status, 'needs_review');
    assert.strictEqual(debitOut.draft?.suggestedType, 'expense');
    assert.strictEqual(debitOut.draft?.direction, 'outgoing');
    assert.strictEqual(debitOut.draft?.principalCents, 45050);
    assert.strictEqual(debitOut.draft?.reportedBalanceCents, 1454950);
    assert.strictEqual(debitOut.draft?.accountHint, '****4321');
    assert.strictEqual(debitOut.draft?.counterpartyName, 'Merchant Payment');
    assert.strictEqual(debitOut.draft?.transactionReference, 'FT26326BOA01');
    assert.strictEqual(debitOut.draft?.suggestedAccountId, 'acc-boa');
    assert.strictEqual(debitOut.draft?.isNonLedgerNotice, false);

    // BOA Credit
    const creditSms =
      'Your account 1****4321 was credited with ETB 3,200.00 by Abebe Kebede. Available Balance: ETB 17,749.50. https://cs.bankofabyssinia.com/slip/?trx=FT26326BOA02';
    const creditOut = parseFinancialSmsMessage(creditSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(creditOut.kind, 'draft');
    assert.strictEqual(creditOut.draft?.provider, 'boa');
    assert.strictEqual(creditOut.draft?.suggestedType, 'income');
    assert.strictEqual(creditOut.draft?.direction, 'incoming');
    assert.strictEqual(creditOut.draft?.principalCents, 320000);
    assert.strictEqual(creditOut.draft?.counterpartyName, 'Abebe Kebede');
    assert.strictEqual(creditOut.draft?.reportedBalanceCents, 1774950);
    assert.strictEqual(creditOut.draft?.transactionReference, 'FT26326BOA02');

    // BOA POS Locked authorization — MUST NOT become a normal expense draft!
    const posSms =
      'Dear customer, ETB 240.00 is Locked From Your Account 1****4321 Due to POS TRANSACTION at KALDIS COFFEE. Your Available Balance is ETB 17,509.50.';
    const posOut = parseFinancialSmsMessage(posSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(posOut.kind, 'draft');
    assert.strictEqual(posOut.draft?.provider, 'boa');
    assert.strictEqual(posOut.draft?.status, 'unrecognized');
    assert.strictEqual(posOut.draft?.suggestedType, 'unknown');
    assert.strictEqual(posOut.draft?.isNonLedgerNotice, true);
    assert.strictEqual(posOut.draft?.principalCents, 24000);
    assert.strictEqual(posOut.draft?.counterpartyName, 'KALDIS COFFEE');
    assert.strictEqual(posOut.draft?.reportedBalanceCents, 1750950);
    assert.strictEqual(canApproveSmsDraft(posOut.draft!).ok, false);

    // BOA Security/Promo notice — safely ignored
    const promoOut = parseFinancialSmsMessage(
      'Bank of Abyssinia security alert: Never share your PIN or password with anyone.',
      { receivedAtUtc, accounts, categories }
    );
    assert.strictEqual(promoOut.kind, 'ignored_non_transactional');
  });

  it('3. Commercial Bank of Ethiopia (CBE): outgoing fee breakdown preservation, mismatch flag, and incoming credit', () => {
    const accounts = makeTestAccounts();
    const categories = makeTestCategories();
    const receivedAtUtc = '2026-11-22T12:00:00.000Z';

    // Exact principal vs fees separation (ETB 2,000.00 + ETB 1.20 fees = ETB 2,001.20)
    const cbeOutSms =
      'Dear Customer, You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit Bekele). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80. https://apps.cbe.com.et:100/?id=FT26326CBE01';
    const outRes = parseFinancialSmsMessage(cbeOutSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(outRes.kind, 'draft');
    const draft = outRes.draft!;
    assert.strictEqual(draft.provider, 'cbe');
    assert.strictEqual(draft.status, 'needs_review');
    assert.strictEqual(draft.direction, 'outgoing');
    assert.strictEqual(draft.suggestedType, 'expense');
    assert.strictEqual(draft.principalCents, 200000);
    assert.strictEqual(draft.serviceFeeCents, 87);
    assert.strictEqual(draft.vatCents, 13);
    assert.strictEqual(draft.otherChargesCents, 20);
    assert.strictEqual(totalDraftFeesCents(draft), 120);
    assert.strictEqual(draft.totalAmountCents, 200120);
    assert.strictEqual(draft.hasAmountMismatch, false);
    assert.strictEqual(draft.reportedBalanceCents, 1799880);
    assert.strictEqual(draft.accountHint, '****5678');
    assert.strictEqual(draft.counterpartyHint, '****9900');
    assert.strictEqual(draft.counterpartyName, 'Dawit Bekele');
    assert.strictEqual(draft.transactionReference, 'FT26326CBE01');
    assert.strictEqual(draft.suggestedAccountId, 'acc-cbe');

    // Amount mismatch check
    const cbeMismatchSms =
      'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit Bekele). Service charge of ETB 1.00 and VAT(15%) of ETB 0.15 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,005.00. Your current balance is ETB 17,995.00.';
    const mismatchRes = parseFinancialSmsMessage(cbeMismatchSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(mismatchRes.draft?.hasAmountMismatch, true);
    assert.strictEqual(mismatchRes.draft?.confidence, 'medium');

    // CBE Incoming
    const cbeInSms =
      'Dear Customer, You have received ETB 8,500.00 from account 1****2211 (Acme Trading) to your account 1****5678. Your current balance is ETB 26,498.80. https://apps.cbe.com.et:100/?id=FT26326CBE02';
    const inRes = parseFinancialSmsMessage(cbeInSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(inRes.draft?.provider, 'cbe');
    assert.strictEqual(inRes.draft?.suggestedType, 'income');
    assert.strictEqual(inRes.draft?.direction, 'incoming');
    assert.strictEqual(inRes.draft?.principalCents, 850000);
    assert.strictEqual(inRes.draft?.counterpartyName, 'Acme Trading');
    assert.strictEqual(inRes.draft?.accountHint, '****5678');
    assert.strictEqual(inRes.draft?.counterpartyHint, '****2211');
  });

  it('4. Telebirr: outgoing paid/transferred, fee + 15% VAT, Ethiopia UTC+3 datetime, incoming, and OTP ignore', () => {
    const accounts = makeTestAccounts();
    const categories = makeTestCategories();
    const receivedAtUtc = '2026-11-22T09:00:00.000Z';

    const tbOutSms =
      'Dear Customer, You have paid ETB 500.00 to Ethio Telecom (251911223344) on 22/11/2026 08:15:30. Your transaction number is TB26326XYZ9. Service fee is ETB 2.00 and 15% VAT on service fee is ETB 0.30 with total paid is ETB 502.30. Your current E-Money Account balance is ETB 4,497.70. https://transactioninfo.ethiotelecom.et/receipt/TB26326XYZ9';
    const outRes = parseFinancialSmsMessage(tbOutSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(outRes.kind, 'draft');
    const draft = outRes.draft!;
    assert.strictEqual(draft.provider, 'telebirr');
    assert.strictEqual(draft.suggestedType, 'expense');
    assert.strictEqual(draft.direction, 'outgoing');
    assert.strictEqual(draft.principalCents, 50000);
    assert.strictEqual(draft.serviceFeeCents, 200);
    assert.strictEqual(draft.vatCents, 30);
    assert.strictEqual(totalDraftFeesCents(draft), 230);
    assert.strictEqual(draft.totalAmountCents, 50230);
    assert.strictEqual(draft.hasAmountMismatch, false);
    assert.strictEqual(draft.reportedBalanceCents, 449770);
    assert.strictEqual(draft.counterpartyName, 'Ethio Telecom');
    assert.strictEqual(draft.counterpartyHint, '****3344');
    assert.strictEqual(draft.transactionReference, 'TB26326XYZ9');
    assert.strictEqual(draft.transactionDateIso, '2026-11-22');
    assert.strictEqual(draft.transactionTimestampIso, '2026-11-22T05:15:30.000Z');
    assert.strictEqual(draft.suggestedAccountId, 'acc-telebirr');

    // Telebirr Incoming without phone parentheses
    const tbInSms =
      'You have received ETB 1,250.00 from Sara Tadesse on 22/11/2026 11:00:00. Your transaction number is TB26326INC1. Your current E-Money Account balance is ETB 5,747.70.';
    const inRes = parseFinancialSmsMessage(tbInSms, {
      receivedAtUtc,
      accounts,
      categories,
    });
    assert.strictEqual(inRes.draft?.provider, 'telebirr');
    assert.strictEqual(inRes.draft?.suggestedType, 'income');
    assert.strictEqual(inRes.draft?.direction, 'incoming');
    assert.strictEqual(inRes.draft?.principalCents, 125000);
    assert.strictEqual(inRes.draft?.counterpartyName, 'Sara Tadesse');
    assert.strictEqual(inRes.draft?.transactionReference, 'TB26326INC1');

    // Telebirr OTP & failed PIN notices ignored (with or without provider brand)
    const otpOut = parseFinancialSmsMessage(
      'Telebirr: Your One Time Password OTP is 123456. Do not share your OTP with anyone.',
      { receivedAtUtc, accounts, categories }
    );
    assert.strictEqual(otpOut.kind, 'ignored_non_transactional');

    const failedPinTelebirr = parseFinancialSmsMessage(
      'Telebirr: Your PIN is incorrect. Please check and try again.',
      { receivedAtUtc, accounts, categories }
    );
    assert.strictEqual(failedPinTelebirr.kind, 'ignored_non_transactional');

    const failedPinGeneric = parseFinancialSmsMessage(
      'Your PIN is incorrect. Remaining attempts: 2.',
      { receivedAtUtc, accounts, categories }
    );
    assert.strictEqual(failedPinGeneric.kind, 'ignored_non_transactional');
  });

  it('5. Deduplication & non-resurfacing: provider+ref and fingerprint block duplicates including dismissed and approved drafts', async () => {
    await withMockBrowserStorage(() => {
      const accounts = makeTestAccounts();
      const categories = makeTestCategories();
      const cbeSms1 =
        'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80. https://apps.cbe.com.et:100/?id=FT999DEDUP';
      const boaNoRefSms =
        'Your account 1****4321 was debited with ETB 100.00 for Coffee. Available Balance: ETB 14,900.00.';

      const first = FinanceSmsService.importSmsMessages({
        rawMessages: [cbeSms1, boaNoRefSms],
        receivedAtUtc: '2026-11-22T10:00:00.000Z',
        accounts,
        categories,
      });
      assert.strictEqual(first.summary.importedCount, 2);
      assert.strictEqual(first.drafts.length, 2);

      // Dismiss BOA draft and verify re-importing normalized text does NOT resurrect it
      const boaDraft = first.drafts.find((d) => d.provider === 'boa')!;
      FinanceSmsService.dismissDraft({ draftId: boaDraft.id });

      const reimport = FinanceSmsService.importSmsMessages({
        rawMessages: [
          // Same CBE ref with slightly altered trailing punctuation
          'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80.   https://apps.cbe.com.et:100/?id=FT999DEDUP',
          // Same BOA text with different whitespace/casing -> matches normalized fingerprint
          '  your account   1****4321 was debited with ETB 100.00 for coffee. available balance: ETB 14,900.00. ',
        ],
        receivedAtUtc: '2026-11-22T11:00:00.000Z',
        accounts,
        categories,
      });
      assert.strictEqual(reimport.summary.importedCount, 0);
      assert.strictEqual(reimport.summary.duplicateCount, 2);
      assert.strictEqual(reimport.drafts.length, 2);
      assert.strictEqual(
        reimport.drafts.find((d) => d.id === boaDraft.id)?.status,
        'dismissed'
      );

      // Same reference across DIFFERENT providers is NOT treated as duplicate
      const candidateOtherProvider: FinanceSmsDraft = {
        ...first.drafts.find((d) => d.provider === 'cbe')!,
        id: 'other-provider-id',
        provider: 'telebirr',
        fingerprint: 'completely-different-fp',
      };
      const crossProviderDup = findDuplicateSmsDraft(candidateOtherProvider, reimport.drafts);
      assert.strictEqual(crossProviderDup.isDuplicate, false);

      // Two separate transactions with IDENTICAL amounts (ETB 500.00) but distinct refs are BOTH retained
      const sameAmountImport = FinanceSmsService.importSmsMessages({
        rawMessages: [
          'You have paid ETB 500.00 to Coffee House (251911000001) on 22/11/2026 09:00:00. Your transaction number is TB500A. Your current E-Money Account balance is ETB 4,500.00.',
          'You have paid ETB 500.00 to Coffee House (251911000001) on 22/11/2026 14:00:00. Your transaction number is TB500B. Your current E-Money Account balance is ETB 4,000.00.',
        ],
        receivedAtUtc: '2026-11-22T14:05:00.000Z',
        accounts,
        categories,
      });
      assert.strictEqual(sameAmountImport.summary.importedCount, 2);
      assert.strictEqual(sameAmountImport.summary.duplicateCount, 0);
      assert.strictEqual(
        sameAmountImport.drafts.filter((d) => d.principalCents === 50000).length,
        2
      );
    });
  });

  it('6. Pre-approval isolation + Explicit approval ledger integrity + Backup/Export privacy exclusion', async () => {
    await withMockBrowserStorage(async (store) => {
      const accounts = makeTestAccounts();
      const categories = makeTestCategories();
      const entries: JournalEntry[] = [];
      const postings: Posting[] = [];

      const snapshotBefore = () => {
        const cbeBal = calculateAccountBalance(
          accounts.find((a) => a.id === 'acc-cbe')!,
          postings,
          undefined,
          entries
        );
        const breakdown = calculateAvailableToSpendBreakdownV7({
          accounts,
          postings,
          entries,
          debts: [],
          commitments: [],
          commitmentSettlements: [],
          savingsGoals: [],
          planningPeriodEndIso: '2026-11-30',
        });
        const catSpend = calculateCanonicalCategorySpendV7({
          entries,
          postings,
          accounts,
          categories,
          startDate: '2026-11-01',
          endDate: '2026-11-30',
        });
        const period = resolveReportPeriodWithComparisonV7({
          mode: 'thisMonth',
          todayIso: '2026-11-22',
        });
        const comparison = calculatePeriodComparisonReportV7({
          period,
          accounts,
          categories,
          entries,
          postings,
        });
        return { cbeBal, breakdown, catSpend, comparison };
      };

      const before = snapshotBefore();

      const rawBatch = [
        'You have successfully transferred ETB 2,000.00 from account 1****5678 to account 1****9900 (Dawit). Service charge of ETB 0.87 and VAT(15%) of ETB 0.13 and Disaster Recovery(5%) of ETB 0.20 with total of ETB 2,001.20. Your current balance is ETB 17,998.80. https://apps.cbe.com.et:100/?id=FT26326PRIV1',
        '---',
        'ETB 240.00 is Locked From Your Account 1****4321 Due to POS TRANSACTION at KALDIS. Your Available Balance is ETB 14,760.00.',
        '---',
        'You have received ETB 3,000.00 from Abebe on 22/11/2026 10:00:00. Your transaction number is TB26326PRIV2. Your current E-Money Account balance is ETB 8,000.00.',
      ].join('\n');

      const split = splitSmsBatchInput(rawBatch);
      assert.strictEqual(split.length, 3);

      const imported = FinanceSmsService.importSmsMessages({
        rawMessages: split,
        receivedAtUtc: '2026-11-22T09:00:00.000Z',
        accounts,
        categories,
      });
      assert.strictEqual(imported.summary.importedCount, 2);
      assert.strictEqual(imported.summary.unrecognizedCount, 1);

      // Verify ZERO ledger/balance/report effect prior to explicit approval
      const afterImport = snapshotBefore();
      assert.strictEqual(entries.length, 0);
      assert.strictEqual(postings.length, 0);
      assert.deepStrictEqual(afterImport, before);
      assert.ok(store.has(FINANCE_SMS_DRAFTS_STORAGE_KEY));

      // POS lock draft CANNOT be approved
      const posDraft = imported.drafts.find((d) => d.isNonLedgerNotice)!;
      assert.throws(() => {
        FinanceSmsService.approveDraft({
          draftId: posDraft.id,
          finalType: 'expense',
          accountId: 'acc-boa',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'POS Hold',
          accounts,
          categories,
        });
      }, DoubleEntryValidationError);

      // Explicitly approve CBE outgoing as Expense (principal 200,000 on cat-food, fees 120 on cat-fees)
      const cbeDraft = imported.drafts.find((d) => d.provider === 'cbe')!;
      const cbeApproval = FinanceSmsService.approveDraft({
        draftId: cbeDraft.id,
        finalType: 'expense',
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        occurrenceDate: resolveDefaultDraftOccurrenceDate(cbeDraft),
        description: 'CBE Payment to Dawit',
        accounts,
        categories,
      });

      const approvedResult = cbeApproval.result;
      assert.strictEqual(approvedResult.updatedDraft.status, 'approved');
      assert.strictEqual(approvedResult.updatedDraft.approvedEntryId, approvedResult.entry.id);
      assert.ok(approvedResult.feeCategoryToAdd);
      assert.strictEqual(approvedResult.feeCategoryToAdd?.id, 'cat-fees');

      // Check double-entry balance and exact separation of principal vs fees
      const totalDebits = approvedResult.postings
        .filter((p) => p.direction === 'debit')
        .reduce((s, p) => s + p.amountCents, 0);
      const totalCredits = approvedResult.postings
        .filter((p) => p.direction === 'credit')
        .reduce((s, p) => s + p.amountCents, 0);
      assert.strictEqual(totalDebits, 200120);
      assert.strictEqual(totalCredits, 200120);
      assert.strictEqual(
        approvedResult.postings.find((p) => p.categoryId === 'cat-food')?.amountCents,
        200000
      );
      assert.strictEqual(
        approvedResult.postings.find((p) => p.categoryId === 'cat-fees')?.amountCents,
        120
      );
      // Individual CBE charge breakdown is preserved both on the approved draft AND the fee posting note
      assert.strictEqual(approvedResult.updatedDraft.serviceFeeCents, 87);
      assert.strictEqual(approvedResult.updatedDraft.vatCents, 13);
      assert.strictEqual(approvedResult.updatedDraft.otherChargesCents, 20);
      const feePosting = approvedResult.postings.find((p) => p.categoryId === 'cat-fees')!;
      assert.ok(feePosting.note?.includes('Service fee: ETB 0.87'));
      assert.ok(feePosting.note?.includes('VAT: ETB 0.13'));
      assert.ok(feePosting.note?.includes('Disaster Recovery / Other: ETB 0.20'));
      const expenseSummary = summarizeDirectExpense({
        entry: approvedResult.entry,
        postings: approvedResult.postings,
        accountById: new Map(accounts.map((a) => [a.id, a])),
      });
      assert.strictEqual(expenseSummary.isDirectExpense, true);
      assert.strictEqual(expenseSummary.principalCents, 200000);
      assert.strictEqual(expenseSummary.feeCents, 120);
      assert.strictEqual(expenseSummary.totalOutflowCents, 200120);

      // Ensure rawSmsText & receipt URL are NEVER leaked into ledger entries or postings
      assert.ok(!approvedResult.entry.description.includes('Service charge of ETB'));
      assert.ok(!approvedResult.entry.description.includes('apps.cbe.com.et'));
      assert.ok(!(approvedResult.simpleTx.description ?? '').includes('Service charge of ETB'));

      // Double approval must fail closed
      assert.throws(() => {
        FinanceSmsService.approveDraft({
          draftId: cbeDraft.id,
          finalType: 'expense',
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Duplicate Post Attempt',
          accounts,
          categories,
        });
      }, DoubleEntryValidationError);

      // Non-ETB account rejection
      const tbDraft = imported.drafts.find((d) => d.provider === 'telebirr')!;
      assert.throws(() => {
        buildApprovedSmsLedgerEntry({
          draft: tbDraft,
          finalType: 'income',
          accountId: 'acc-usd',
          categoryId: 'cat-salary',
          occurrenceDate: '2026-11-22',
          description: 'Non-ETB should fail',
          entryId: 'entry-bad-usd',
          accounts,
          categories,
        });
      }, DoubleEntryValidationError);

      // Approve Telebirr incoming & test transfer approval on a fresh draft
      const tbApproval = FinanceSmsService.approveDraft({
        draftId: tbDraft.id,
        finalType: 'income',
        accountId: 'acc-telebirr',
        categoryId: 'cat-salary',
        occurrenceDate: '2026-11-22',
        description: 'Abebe Transfer In',
        accounts,
        categories: [...categories, approvedResult.feeCategoryToAdd!],
      });
      assert.strictEqual(tbApproval.result.simpleTx.type, 'income');
      assert.strictEqual(tbApproval.result.simpleTx.amountCents, 300000);

      // Outgoing CBE draft approved as Internal Transfer (Liquid -> Vault with fee)
      const xferImport = FinanceSmsService.importSmsMessages({
        rawMessages: [
          'You have successfully transferred ETB 1,000.00 from account 1****5678 to account 1****8888 (My Vault). Service charge of ETB 0.50 and VAT(15%) of ETB 0.08 with total of ETB 1,000.58. Your current balance is ETB 16,998.22.',
        ],
        receivedAtUtc: '2026-11-22T12:00:00.000Z',
        accounts,
        categories,
      });
      const xferDraft = xferImport.summary.importedDrafts[0];
      const xferApproval = FinanceSmsService.approveDraft({
        draftId: xferDraft.id,
        finalType: 'transfer',
        accountId: 'acc-cbe',
        destinationAccountId: 'acc-vault',
        occurrenceDate: '2026-11-22',
        description: 'Top up House Vault',
        accounts,
        categories,
      });
      assert.strictEqual(xferApproval.result.entry.entryType, 'transfer');
      assert.strictEqual(
        xferApproval.result.postings.find((p) => p.accountId === 'acc-vault')?.amountCents,
        100000
      );
      assert.strictEqual(
        xferApproval.result.postings.find((p) => p.accountId === 'acc-cbe')?.amountCents,
        100058
      );
      assert.strictEqual(
        xferApproval.result.postings.find((p) => p.categoryId === 'cat-fees')?.amountCents,
        58
      );

      // Verify portable snapshots & exports EXCLUDE smsDrafts and rawSmsText
      entries.push(approvedResult.entry, tbApproval.result.entry, xferApproval.result.entry);
      postings.push(
        ...approvedResult.postings,
        ...tbApproval.result.postings,
        ...xferApproval.result.postings
      );

      const fullBackup = SharedStateBridge.exportToAndroidJson();
      const financeOnlyBackup = SharedStateBridge.exportFinanceOnlyJson();
      assert.ok(!fullBackup.includes('smsDrafts'));
      assert.ok(!fullBackup.includes('Service charge of ETB 0.87'));
      assert.ok(!financeOnlyBackup.includes('smsDrafts'));
      assert.ok(!financeOnlyBackup.includes('Service charge of ETB 0.87'));

      const { blob } = await DataPortabilityService.createExportZipBundle({
        accounts,
        parties: [],
        entries,
        postings,
        debts: [],
        settlementAllocations: [],
        categories: [...categories, approvedResult.feeCategoryToAdd!],
        reservedSavingsCents: 0,
        transactions: [
          approvedResult.simpleTx,
          tbApproval.result.simpleTx,
          xferApproval.result.simpleTx,
        ],
      });
      const zip = await JSZip.loadAsync(await blob.arrayBuffer());
      for (const path of Object.keys(zip.files)) {
        if (path.endsWith('.csv') || path.endsWith('.sql') || path.endsWith('.json')) {
          const text = await zip.file(path)!.async('string');
          assert.ok(!text.includes('Service charge of ETB 0.87'), `Leaked raw SMS in ${path}`);
          assert.ok(!text.includes('sms_drafts'), `Unexpected sms_drafts table in ${path}`);
        }
      }
    });
  });

  it('7. Uncertain classification guard + Web atomic approval rollback on storage failure', async () => {
    await withMockBrowserStorage((store) => {
      const accounts = makeTestAccounts();
      const categories = makeTestCategories();

      // Uncertain / unknown draft cannot pass canApproveSmsDraft directly
      const uncertainDraft: FinanceSmsDraft = {
        id: 'sms-draft-uncertain-1',
        provider: 'boa',
        fingerprint: 'fp-uncertain-1',
        suggestedType: 'unknown',
        direction: 'uncertain',
        principalCents: 50000,
        serviceFeeCents: 0,
        vatCents: 0,
        otherChargesCents: 0,
        hasAmountMismatch: false,
        currencyCode: 'ETB',
        receivedAtUtc: '2026-11-22T10:00:00.000Z',
        confidence: 'low',
        status: 'needs_review',
        isNonLedgerNotice: false,
        rawSmsText: 'Ambiguous notice',
        createdAt: '2026-11-22T10:00:00.000Z',
        updatedAt: '2026-11-22T10:00:00.000Z',
      };
      assert.strictEqual(canApproveSmsDraft(uncertainDraft).ok, false);

      // Seed one pending draft + pre-existing ledger state
      const imp = FinanceSmsService.importSmsMessages({
        rawMessages: [
          'Your account 1****4321 was debited with ETB 300.00 for Grocery. Available Balance: ETB 14,700.00.',
        ],
        receivedAtUtc: '2026-11-22T10:00:00.000Z',
        accounts,
        categories,
      });
      const pendingDraft = imp.summary.importedDrafts[0];
      store.set('daywell_journal_entries', '[]');
      store.set('daywell_postings', '[]');
      const draftsBefore = store.get(FINANCE_SMS_DRAFTS_STORAGE_KEY);

      // Inject write failure on the final draft-status key AFTER ledger keys were staged
      const failingStorage = {
        getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
        setItem: (k: string, v: string) => {
          if (k === FINANCE_SMS_DRAFTS_STORAGE_KEY) {
            throw new Error('Simulated storage quota failure');
          }
          store.set(k, v);
        },
        removeItem: (k: string) => void store.delete(k),
      };

      assert.throws(() => {
        FinanceSmsService.approveDraftAtomically({
          draftId: pendingDraft.id,
          finalType: 'expense',
          accountId: 'acc-boa',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Should roll back',
          accounts,
          categories,
          entries: [],
          postings: [],
          simpleTransactions: [],
          savingsGoals: [],
          storage: failingStorage,
        });
      }, /Simulated storage quota failure/);

      // Both ledger keys AND sms drafts MUST be restored cleanly to pre-approval snapshot
      assert.strictEqual(store.get('daywell_journal_entries'), '[]');
      assert.strictEqual(store.get('daywell_postings'), '[]');
      assert.strictEqual(store.has('daywell_finance_transactions'), false);
      assert.strictEqual(store.has('daywell_transactions'), false);
      assert.strictEqual(store.get(FINANCE_SMS_DRAFTS_STORAGE_KEY), draftsBefore);
      assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);
      assert.strictEqual(
        FinanceSmsService.loadDrafts().find((d) => d.id === pendingDraft.id)?.status,
        'needs_review'
      );
    });
  });

  it('8. Crash-safe recovery after abrupt termination following the 1st ledger write + clean retry', async () => {
    await withMockBrowserStorage((store) => {
      const accounts = makeTestAccounts();
      const categories = makeTestCategories();
      const cbeAccount = accounts.find((a) => a.id === 'acc-cbe')!;

      // Pre-existing unrelated ledger transaction (must remain intact)
      const baselineEntry: JournalEntry = {
        id: 'je-existing-1',
        entryType: 'standard',
        description: 'Existing rent payment',
        occurrenceDate: '2026-11-10',
        isVoided: false,
        createdAt: '2026-11-10T09:00:00.000Z',
      };
      const baselinePostings: Posting[] = [
        {
          id: 'post-existing-dr',
          entryId: 'je-existing-1',
          accountId: SYSTEM_CONTROL_ACCOUNT_IDS.expense,
          direction: 'debit',
          amountCents: 100000,
          accountMovementDate: '2026-11-10',
          categoryId: 'cat-food',
        },
        {
          id: 'post-existing-cr',
          entryId: 'je-existing-1',
          accountId: 'acc-cbe',
          direction: 'credit',
          amountCents: 100000,
          accountMovementDate: '2026-11-10',
        },
      ];
      const baselineSimpleTxs = [
        {
          id: 'tx-existing-1',
          type: 'expense' as const,
          amountCents: 100000,
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          description: 'Existing rent payment',
          transactionDate: '2026-11-10',
          createdAt: '2026-11-10T09:00:00.000Z',
          updatedAt: '2026-11-10T09:00:00.000Z',
          journalEntryId: 'je-existing-1',
        },
      ];

      store.set('daywell_accounts', JSON.stringify(accounts));
      store.set('daywell_categories', JSON.stringify(categories));
      store.set('daywell_journal_entries', JSON.stringify([baselineEntry]));
      store.set('daywell_postings', JSON.stringify(baselinePostings));
      store.set('daywell_finance_transactions', JSON.stringify(baselineSimpleTxs));
      store.set('daywell_transactions', JSON.stringify(baselineSimpleTxs));
      store.set('daywell_savings_goals', '[]');

      const imp = FinanceSmsService.importSmsMessages({
        rawMessages: [
          'Dear Customer, You have successfully transferred ETB 500.00 from account 1****5678 to account 1****9999 (Abebe) with Service charge of ETB 5.00 and VAT (15%) of ETB 0.75 with total of ETB 505.75. Your Current Balance is ETB 18,494.25. https://apps.cbe.com.et:100/?id=FT26326CRASH1',
        ],
        receivedAtUtc: '2026-11-22T12:00:00.000Z',
        accounts,
        categories,
      });
      const pendingDraft = imp.summary.importedDrafts[0];

      // Baseline balance & P&L report before approval
      const baselineCbeBalance = calculateAccountBalance(cbeAccount, baselinePostings, undefined, [baselineEntry]);
      const baselineSafeHarbor = calculateAvailableToSpendBreakdownV7({
        accounts,
        postings: baselinePostings,
        entries: [baselineEntry],
        debts: [],
        allocations: [],
        commitments: [],
        commitmentSettlements: [],
        recurringRules: [],
        savingsGoals: [],
      });
      const baselineSpend = calculateCanonicalCategorySpendV7({
        accounts,
        categories,
        entries: [baselineEntry],
        postings: baselinePostings,
        debts: [],
        allocations: [],
        startDate: '2026-11-01',
        endDate: '2026-11-30',
      });

      // Simulate abrupt browser/device termination right after writing the 1st ledger key
      // (`daywell_journal_entries`), bypassing JS catch rollback completely.
      const diskWorking = new Map(store);
      let crashedSnapshot: Map<string, string> | undefined;
      const crashAfterJournalEntryWrite = {
        getItem: (k: string) => (diskWorking.has(k) ? diskWorking.get(k)! : null),
        setItem: (k: string, v: string) => {
          if (k === 'daywell_postings') {
            if (!crashedSnapshot) {
              crashedSnapshot = new Map(diskWorking);
            }
            throw new Error('Simulated abrupt process termination after 1st ledger write');
          }
          diskWorking.set(k, v);
        },
        removeItem: (k: string) => void diskWorking.delete(k),
      };

      assert.throws(() => {
        FinanceSmsService.approveDraftAtomically({
          draftId: pendingDraft.id,
          finalType: 'expense',
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Abebe payment',
          accounts,
          categories,
          entries: [baselineEntry],
          postings: baselinePostings,
          simpleTransactions: baselineSimpleTxs,
          savingsGoals: [],
          entryId: 'entry-sms-crash-1',
          storage: crashAfterJournalEntryWrite,
        });
      }, /Simulated abrupt process termination/);

      assert.ok(crashedSnapshot);
      const snap1 = crashedSnapshot!;
      // Verify the crashed snapshot really has the incomplete state (pending intent + new entry + new fee category,
      // but NO postings, NO simpleTx, and draft still needs_review)
      assert.ok(snap1.has(FINANCE_SMS_PENDING_APPROVAL_KEY));
      assert.strictEqual(
        (JSON.parse(snap1.get('daywell_journal_entries')!) as JournalEntry[]).length,
        2
      );
      assert.strictEqual(
        (JSON.parse(snap1.get('daywell_postings')!) as Posting[]).length,
        2
      );

      // Simulate restarting the application with the crashed disk snapshot
      store.clear();
      for (const [k, v] of snap1.entries()) {
        store.set(k, v);
      }

      // Restart recovery runs automatically on SharedStateBridge / loadDrafts
      const recoveredCanonical = SharedStateBridge.loadCanonicalState();
      const recoveredDrafts = FinanceSmsService.loadDrafts();

      assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);
      assert.strictEqual(recoveredDrafts.find((d) => d.id === pendingDraft.id)?.status, 'needs_review');
      assert.strictEqual(
        recoveredDrafts.find((d) => d.id === pendingDraft.id)?.approvedEntryId,
        undefined
      );
      assert.strictEqual(recoveredCanonical.journalEntries?.length, 1);
      assert.strictEqual(recoveredCanonical.journalEntries?.[0].id, 'je-existing-1');
      assert.strictEqual(recoveredCanonical.postings?.length, 2);
      assert.strictEqual(recoveredCanonical.transactions.length, 1);
      assert.strictEqual(
        recoveredCanonical.categories.some((c) => c.id === 'cat-fees'),
        false
      );

      // Verify zero impact on balances, Safe Harbor, or category spend reports after recovery
      const recoveredEntries = recoveredCanonical.journalEntries ?? [];
      const recoveredPostings = recoveredCanonical.postings ?? [];
      const recoveredCategories = recoveredCanonical.categories as TransactionCategory[];
      const recoveredSimpleTxs = JSON.parse(store.get('daywell_finance_transactions')!);
      assert.strictEqual(
        calculateAccountBalance(cbeAccount, recoveredPostings, undefined, recoveredEntries),
        baselineCbeBalance
      );
      assert.strictEqual(
        calculateAvailableToSpendBreakdownV7({
          accounts,
          postings: recoveredPostings,
          entries: recoveredEntries,
          debts: [],
          allocations: [],
          commitments: [],
          commitmentSettlements: [],
          recurringRules: [],
          savingsGoals: [],
        }).availableToSpendCents,
        baselineSafeHarbor.availableToSpendCents
      );
      assert.strictEqual(
        calculateCanonicalCategorySpendV7({
          accounts,
          categories: recoveredCategories,
          entries: recoveredEntries,
          postings: recoveredPostings,
          debts: [],
          allocations: [],
          startDate: '2026-11-01',
          endDate: '2026-11-30',
        }).totalExpenseCents,
        baselineSpend.totalExpenseCents
      );

      // Retry the exact same approval after recovery -> succeeds cleanly with zero duplicates
      const retried = FinanceSmsService.approveDraftAtomically({
        draftId: pendingDraft.id,
        finalType: 'expense',
        accountId: 'acc-cbe',
        categoryId: 'cat-food',
        occurrenceDate: '2026-11-22',
        description: 'Abebe payment',
        accounts,
        categories: recoveredCategories,
        entries: recoveredEntries,
        postings: recoveredPostings,
        simpleTransactions: recoveredSimpleTxs,
        savingsGoals: [],
      });

      assert.strictEqual(retried.entries.length, 2);
      assert.strictEqual(retried.postings.length, 5); // 2 existing + 3 (principal debit, fee debit, combined credit)
      assert.strictEqual(retried.simpleTransactions.length, 2);
      assert.strictEqual(
        retried.drafts.find((d) => d.id === pendingDraft.id)?.status,
        'approved'
      );
      assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);

      // Attempting to approve the same draft again fails closed without duplicating
      assert.throws(() => {
        FinanceSmsService.approveDraftAtomically({
          draftId: pendingDraft.id,
          finalType: 'expense',
          accountId: 'acc-cbe',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Duplicate retry',
          accounts,
          categories: retried.categories,
          entries: retried.entries,
          postings: retried.postings,
          simpleTransactions: retried.simpleTransactions,
          savingsGoals: retried.savingsGoals,
        });
      }, /already been approved/i);
    });
  });

  it('9. Crash-safe recovery after partial multi-key ledger writes (mid-ledger & pre-draft-status)', async () => {
    const cutPoints = [
      { name: 'after postings before simpleTx', failOnKey: 'daywell_finance_transactions' },
      { name: 'after all 6 ledger keys before draft status', failOnKey: FINANCE_SMS_DRAFTS_STORAGE_KEY },
    ];

    for (const cutPoint of cutPoints) {
      await withMockBrowserStorage((store) => {
        const accounts = makeTestAccounts();
        const categories = makeTestCategories();
        const initialGoals: SharedSavingsGoal[] = [
          {
            id: 'goal-house',
            title: 'House Fund',
            targetCents: 500000,
            currentAllocatedCents: 100000,
            linkedAccountId: 'acc-vault',
            status: 'active',
          },
        ];

        store.set('daywell_accounts', JSON.stringify(accounts));
        store.set('daywell_categories', JSON.stringify(categories));
        store.set('daywell_journal_entries', '[]');
        store.set('daywell_postings', '[]');
        store.set('daywell_finance_transactions', '[]');
        store.set('daywell_transactions', '[]');
        store.set('daywell_savings_goals', JSON.stringify(initialGoals));

        const imp = FinanceSmsService.importSmsMessages({
          rawMessages: [
            'Dear Customer, You have successfully transferred ETB 1,000.00 from account 1****5678 to account 1****0001 (House Vault) with Service charge of ETB 0.50 and VAT (15%) of ETB 0.08 with total of ETB 1,000.58. Your Current Balance is ETB 18,999.42.',
          ],
          receivedAtUtc: '2026-11-22T14:00:00.000Z',
          accounts,
          categories,
        });
        const draft = imp.summary.importedDrafts[0];

        const diskWorking = new Map(store);
        let crashedSnapshot: Map<string, string> | undefined;
        const crashInjector = {
          getItem: (k: string) => (diskWorking.has(k) ? diskWorking.get(k)! : null),
          setItem: (k: string, v: string) => {
            if (k === cutPoint.failOnKey) {
              if (!crashedSnapshot) {
                crashedSnapshot = new Map(diskWorking);
              }
              throw new Error(`Simulated abrupt kill (${cutPoint.name})`);
            }
            diskWorking.set(k, v);
          },
          removeItem: (k: string) => void diskWorking.delete(k),
        };

        assert.throws(() => {
          FinanceSmsService.approveDraftAtomically({
            draftId: draft.id,
            finalType: 'transfer',
            accountId: 'acc-cbe',
            destinationAccountId: 'acc-vault',
            occurrenceDate: '2026-11-22',
            description: 'Vault transfer',
            accounts,
            categories,
            entries: [],
            postings: [],
            simpleTransactions: [],
            savingsGoals: initialGoals,
            entryId: 'entry-sms-partial-1',
            storage: crashInjector,
          });
        }, /Simulated abrupt kill/);

        assert.ok(crashedSnapshot);
        const snap2 = crashedSnapshot!;
        // Confirm postings WERE already written into the crashed snapshot!
        assert.ok(
          (JSON.parse(snap2.get('daywell_postings')!) as Posting[]).length > 0
        );

        // Restart app with crashed disk state
        store.clear();
        for (const [k, v] of snap2.entries()) {
          store.set(k, v);
        }

        const recovery = FinanceSmsService.recoverPendingApproval();
        assert.strictEqual(recovery.recovered, true);
        assert.strictEqual(recovery.outcome, 'rolled_back');
        assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);

        // Verify ALL partial ledger writes AND savings goal allocation were cleanly reverted
        assert.deepStrictEqual(JSON.parse(store.get('daywell_journal_entries')!), []);
        assert.deepStrictEqual(JSON.parse(store.get('daywell_postings')!), []);
        assert.deepStrictEqual(JSON.parse(store.get('daywell_finance_transactions')!), []);
        assert.deepStrictEqual(JSON.parse(store.get('daywell_transactions')!), []);
        assert.strictEqual(
          (JSON.parse(store.get('daywell_savings_goals')!) as SharedSavingsGoal[])[0]
            .currentAllocatedCents,
          100000
        );
        assert.strictEqual(
          FinanceSmsService.loadDrafts().find((d) => d.id === draft.id)?.status,
          'needs_review'
        );

        // Retry approval after recovery -> exactly 1 transfer entry + 1 updated vault goal
        const retried = FinanceSmsService.approveDraftAtomically({
          draftId: draft.id,
          finalType: 'transfer',
          accountId: 'acc-cbe',
          destinationAccountId: 'acc-vault',
          occurrenceDate: '2026-11-22',
          description: 'Vault transfer',
          accounts,
          categories: JSON.parse(store.get('daywell_categories')!),
          entries: JSON.parse(store.get('daywell_journal_entries')!),
          postings: JSON.parse(store.get('daywell_postings')!),
          simpleTransactions: JSON.parse(store.get('daywell_finance_transactions')!),
          savingsGoals: JSON.parse(store.get('daywell_savings_goals')!),
        });
        assert.strictEqual(retried.entries.length, 1);
        assert.strictEqual(retried.savingsGoals[0].currentAllocatedCents, 200000);
        assert.strictEqual(
          retried.drafts.find((d) => d.id === draft.id)?.status,
          'approved'
        );
      });
    }
  });

  it('10. Edge crash cases: post-commit intent cleanup, mid-recovery interruption, and no orphaned approved drafts', async () => {
    await withMockBrowserStorage((store) => {
      const accounts = makeTestAccounts();
      const categories = makeTestCategories();
      store.set('daywell_accounts', JSON.stringify(accounts));
      store.set('daywell_categories', JSON.stringify(categories));
      store.set('daywell_journal_entries', '[]');
      store.set('daywell_postings', '[]');
      store.set('daywell_finance_transactions', '[]');
      store.set('daywell_transactions', '[]');
      store.set('daywell_savings_goals', '[]');

      const imp = FinanceSmsService.importSmsMessages({
        rawMessages: [
          'Your account 1****4321 was debited with ETB 250.00 for Coffee. Available Balance: ETB 14,750.00.',
          'Your account 1****4321 was debited with ETB 400.00 for Lunch. Available Balance: ETB 14,350.00.',
        ],
        receivedAtUtc: '2026-11-22T15:00:00.000Z',
        accounts,
        categories,
      });
      const [draft1, draft2] = imp.summary.importedDrafts;

      // Case A: All 7 keys committed, crash happens right before clearing PENDING_KEY
      const diskA = new Map(store);
      let snapshotPostCommit: Map<string, string> | undefined;
      const crashOnRemoveIntent = {
        getItem: (k: string) => (diskA.has(k) ? diskA.get(k)! : null),
        setItem: (k: string, v: string) => void diskA.set(k, v),
        removeItem: (k: string) => {
          if (k === FINANCE_SMS_PENDING_APPROVAL_KEY) {
            if (!snapshotPostCommit) {
              snapshotPostCommit = new Map(diskA);
            }
            throw new Error('Simulated crash after all 7 keys committed before intent cleanup');
          }
          diskA.delete(k);
        },
      };

      assert.throws(() => {
        FinanceSmsService.approveDraftAtomically({
          draftId: draft1.id,
          finalType: 'expense',
          accountId: 'acc-boa',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Coffee',
          accounts,
          categories,
          entries: [],
          postings: [],
          simpleTransactions: [],
          savingsGoals: [],
          entryId: 'entry-sms-complete-1',
          storage: crashOnRemoveIntent,
        });
      }, /Simulated crash after all 7 keys/);

      // Restore store to snapshotPostCommit (simulating real process death before catch ran)
      assert.ok(snapshotPostCommit);
      const snapA = snapshotPostCommit!;
      store.clear();
      for (const [k, v] of snapA.entries()) {
        store.set(k, v);
      }
      const resA = FinanceSmsService.recoverPendingApproval();
      assert.strictEqual(resA.recovered, true);
      assert.strictEqual(resA.outcome, 'finalized_completed');
      assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);
      assert.strictEqual(
        FinanceSmsService.loadDrafts().find((d) => d.id === draft1.id)?.status,
        'approved'
      );
      assert.strictEqual((JSON.parse(store.get('daywell_journal_entries')!) as JournalEntry[]).length, 1);

      // Retrying draft1 after finalized_completed is rejected with zero duplicates
      assert.throws(() => {
        FinanceSmsService.approveDraftAtomically({
          draftId: draft1.id,
          finalType: 'expense',
          accountId: 'acc-boa',
          categoryId: 'cat-food',
          occurrenceDate: '2026-11-22',
          description: 'Coffee duplicate',
          accounts,
          categories,
          entries: JSON.parse(store.get('daywell_journal_entries')!),
          postings: JSON.parse(store.get('daywell_postings')!),
          simpleTransactions: JSON.parse(store.get('daywell_finance_transactions')!),
          savingsGoals: [],
        });
      }, /already been approved/i);

      // Case B: Simulate an approved draft written WITHOUT complete postings + interrupted recovery
      const entriesBeforeB = JSON.parse(store.get('daywell_journal_entries')!) as JournalEntry[];
      const postingsBeforeB = JSON.parse(store.get('daywell_postings')!) as Posting[];
      const txsBeforeB = JSON.parse(store.get('daywell_finance_transactions')!);
      const draftsBeforeB = FinanceSmsService.loadDrafts();

      // Write an inconsistent mid-commit state directly (draft marked approved, entry written, postings missing!)
      const partialDraft2: FinanceSmsDraft = {
        ...draft2,
        status: 'approved',
        approvedEntryId: 'entry-sms-broken-2',
        updatedAt: '2026-11-22T15:05:00.000Z',
      };
      store.set(
        FINANCE_SMS_DRAFTS_STORAGE_KEY,
        JSON.stringify(draftsBeforeB.map((d) => (d.id === draft2.id ? partialDraft2 : d)))
      );
      store.set(
        'daywell_journal_entries',
        JSON.stringify([
          {
            id: 'entry-sms-broken-2',
            entryType: 'standard',
            description: 'Lunch',
            occurrenceDate: '2026-11-22',
            isVoided: false,
            createdAt: '2026-11-22T15:05:00.000Z',
          },
          ...entriesBeforeB,
        ])
      );
      store.set(
        FINANCE_SMS_PENDING_APPROVAL_KEY,
        JSON.stringify({
          version: 1,
          draftId: draft2.id,
          entryId: 'entry-sms-broken-2',
          postingIds: ['p-missing-1', 'p-missing-2'],
          simpleTxId: 'tx-entry-sms-broken-2',
          previousDraft: draft2,
          createdAt: '2026-11-22T15:05:00.000Z',
        })
      );

      // Interrupt recovery mid-way after restoring draft, before cleaning journal_entries
      const diskB = new Map(store);
      const midRecoveryFault = {
        getItem: (k: string) => (diskB.has(k) ? diskB.get(k)! : null),
        setItem: (k: string, v: string) => {
          if (k === 'daywell_journal_entries') {
            throw new Error('Simulated crash during recovery rollback');
          }
          diskB.set(k, v);
        },
        removeItem: (k: string) => void diskB.delete(k),
      };
      assert.throws(() => {
        FinanceSmsService.recoverPendingApproval(midRecoveryFault);
      }, /Simulated crash during recovery rollback/);
      assert.ok(diskB.has(FINANCE_SMS_PENDING_APPROVAL_KEY));

      // Second restart recovery finishes idempotently
      store.clear();
      for (const [k, v] of diskB.entries()) {
        store.set(k, v);
      }
      const resB = FinanceSmsService.recoverPendingApproval();
      assert.strictEqual(resB.recovered, true);
      assert.strictEqual(resB.outcome, 'rolled_back');
      assert.strictEqual(store.has(FINANCE_SMS_PENDING_APPROVAL_KEY), false);
      assert.strictEqual(
        FinanceSmsService.loadDrafts().find((d) => d.id === draft2.id)?.status,
        'needs_review'
      );
      assert.strictEqual((JSON.parse(store.get('daywell_journal_entries')!) as JournalEntry[]).length, 1);
      assert.strictEqual((JSON.parse(store.get('daywell_postings')!) as Posting[]).length, postingsBeforeB.length);
      assert.strictEqual(JSON.parse(store.get('daywell_finance_transactions')!).length, txsBeforeB.length);

      // Verify full & finance-only exports exclude both smsDrafts and pending approval key
      const fullBackup = SharedStateBridge.exportToAndroidJson();
      const financeOnlyBackup = SharedStateBridge.exportFinanceOnlyJson();
      assert.ok(!fullBackup.includes('daywell_finance_sms_pending_approval'));
      assert.ok(!financeOnlyBackup.includes('daywell_finance_sms_pending_approval'));
    });
  });
});
