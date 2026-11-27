import React, { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import {
  Account,
  findCategoryByIdOrAlias,
  formatCurrencyCents,
  isActiveVerifiedEtbAccount,
  Party,
  TransactionCategory,
} from '../../domain/financeV7Engine';
import { DEFAULT_EXPENSE_CATEGORIES } from '../../domain/doubleEntryFinance';
import { SHARED_DESIGN_TOKENS } from '../../domain/sharedFoundation';
import { CalendarDate } from '../../domain/date';
import {
  ComposerKind,
  FinanceComposerPrefill,
  tryParseStrictDecimalToCents,
} from './financeV7Types';
import { DaywellButton, DaywellIconButton, DaywellStatusBanner } from '../ui';

interface FinanceComposerModalProps {
  isOpen: boolean;
  prefill: FinanceComposerPrefill | null;
  accounts: Account[];
  categories: TransactionCategory[];
  parties: Party[];
  onClose: () => void;
  onCreateParty: (name: string) => Party;
  onSubmit: (payload: {
    kind: ComposerKind;
    amountCents: number;
    theirShareCents?: number;
    feeCents?: number;
    feeCategoryId?: string;
    accountId: string;
    destinationAccountId?: string;
    categoryId?: string;
    partyId?: string;
    occurrenceDate: string;
    movementDate: string;
    dueDate?: string;
    description: string;
    payee?: string;
    correctedFromEntryId?: string;
  }) => { ok: boolean; error?: string };
}

export function FinanceComposerModal({
  isOpen,
  prefill,
  accounts,
  categories,
  parties,
  onClose,
  onCreateParty,
  onSubmit,
}: FinanceComposerModalProps) {
  const todayIso = CalendarDate.today().toIsoString();
  const activeAccounts = accounts.filter((a) => isActiveVerifiedEtbAccount(a));
  const hasNonEtbActiveAccounts = accounts.some(
    (a) => !a.isSystem && !a.isArchived && !isActiveVerifiedEtbAccount(a)
  );
  const liquidAccounts = activeAccounts.filter(
    (a) => a.type === 'asset' && a.subType !== 'savings_vault' && a.subType !== 'receivable'
  );
  const expenseCategories = categories.filter((c) => c.type === 'expense' && !c.isArchived);
  const incomeCategories = categories.filter((c) => c.type === 'income' && !c.isArchived);

  const [kind, setKind] = useState<ComposerKind>(() => prefill?.kind || 'expense');
  const [amountStr, setAmountStr] = useState(() => prefill?.amountText || '');
  const [theirShareStr, setTheirShareStr] = useState('');
  const [feeStr, setFeeStr] = useState(() => prefill?.feeText || '0');
  const [feeCategoryId, setFeeCategoryId] = useState(() => prefill?.feeCategoryId || 'cat-fees');
  const [accountId, setAccountId] = useState('');
  const [destAccountId, setDestAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [partyId, setPartyId] = useState('');
  const [newPartyName, setNewPartyName] = useState('');
  const [occurrenceDate, setOccurrenceDate] = useState(todayIso);
  const [movementDate, setMovementDate] = useState(todayIso);
  const [dueDate, setDueDate] = useState('');
  const [description, setDescription] = useState('');
  const [payee, setPayee] = useState('');
  const [correctedFromEntryId, setCorrectedFromEntryId] = useState<string | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  const feeCategoryOptions: TransactionCategory[] = expenseCategories.some(
    (c) => c.id === 'cat-fees'
  )
    ? expenseCategories
    : [
        {
          id: 'cat-fees',
          name: 'Financial Fees',
          type: 'expense',
          colorHex:
            DEFAULT_EXPENSE_CATEGORIES.find((c) => c.id === 'cat-fees')?.colorHex ??
            SHARED_DESIGN_TOKENS.colors.text.mutedLight,
          isArchived: false,
        },
        ...expenseCategories,
      ];

  useEffect(() => {
    if (!isOpen) return;
    const targetKind = prefill?.kind || 'expense';
    setKind(targetKind);
    setAmountStr(prefill?.amountText || '');
    setTheirShareStr('');
    setFeeStr(prefill?.feeText || '0');
    const matchedFeeCat = findCategoryByIdOrAlias(
      feeCategoryOptions,
      prefill?.feeCategoryId
    );
    setFeeCategoryId(matchedFeeCat?.id || 'cat-fees');
    const prefillValidId =
      prefill?.accountId && activeAccounts.some((a) => a.id === prefill.accountId)
        ? prefill.accountId
        : undefined;
    const defaultFromId =
      prefillValidId ||
      liquidAccounts[0]?.id ||
      activeAccounts[0]?.id ||
      '';
    setAccountId(defaultFromId);
    const prefillDestId =
      prefill?.destinationAccountId &&
      activeAccounts.some((a) => a.id === prefill.destinationAccountId)
        ? prefill.destinationAccountId
        : undefined;
    setDestAccountId(
      prefillDestId ||
        activeAccounts.find((a) => a.id !== defaultFromId)?.id ||
        activeAccounts[0]?.id ||
        ''
    );
    const targetCategories = targetKind === 'income' ? incomeCategories : expenseCategories;
    const matchedPrefillCat = findCategoryByIdOrAlias(targetCategories, prefill?.categoryId);
    setCategoryId(
      matchedPrefillCat?.id ||
        targetCategories[0]?.id ||
        (targetKind === 'income' ? 'cat-other-inc' : 'cat-other-exp')
    );
    setPartyId(parties[0]?.id || '');
    setNewPartyName('');
    setOccurrenceDate(prefill?.occurrenceDate || todayIso);
    setMovementDate(prefill?.movementDate || prefill?.occurrenceDate || todayIso);
    setDueDate('');
    setDescription(prefill?.description || '');
    setPayee(prefill?.payee || '');
    setCorrectedFromEntryId(prefill?.correctedFromEntryId);
    setError(null);
  }, [isOpen, prefill?.nonce]);

  if (!isOpen) return null;

  const needsParty =
    kind === 'split' || kind === 'lend' || kind === 'borrow';

  const handleFormSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (kind === 'third_party') {
      setError(
        'Third-party entries must link to an active ETB account. Use Split Expense or Borrow instead.'
      );
      return;
    }
    if (activeAccounts.length === 0 || !activeAccounts.some((a) => a.id === accountId)) {
      setError('Select an active ETB account.');
      return;
    }
    if (kind === 'transfer' && !activeAccounts.some((a) => a.id === destAccountId)) {
      setError('Select a valid active ETB destination account.');
      return;
    }

    const amountCents = tryParseStrictDecimalToCents(amountStr);
    if (amountCents === null || amountCents <= 0) {
      setError('Enter a valid ETB amount greater than 0 (up to 2 decimal places).');
      return;
    }

    let resolvedPartyId = partyId;
    if (needsParty && !resolvedPartyId) {
      const trimmedParty = newPartyName.trim();
      if (!trimmedParty) {
        setError('Select or enter a counterparty name.');
        return;
      }
      const created = onCreateParty(trimmedParty);
      resolvedPartyId = created.id;
    }

    const theirShareCents =
      kind === 'split' ? tryParseStrictDecimalToCents(theirShareStr) : undefined;
    if (kind === 'split' && (theirShareCents === null || theirShareCents === undefined || theirShareCents <= 0)) {
      setError('Enter a valid counterparty share amount (> 0) for Split Expense.');
      return;
    }

    const supportsFee = kind === 'expense' || kind === 'transfer';
    let feeCents = 0;
    if (supportsFee && feeStr.trim() !== '') {
      const parsedFee = tryParseStrictDecimalToCents(feeStr);
      if (parsedFee === null || parsedFee < 0) {
        setError(
          kind === 'transfer'
            ? 'Enter a valid non-negative transfer fee (up to 2 decimal places).'
            : 'Enter a valid non-negative bank/service fee (up to 2 decimal places).'
        );
        return;
      }
      feeCents = parsedFee;
    }

    const res = onSubmit({
      kind,
      amountCents,
      theirShareCents: theirShareCents ?? undefined,
      feeCents,
      feeCategoryId:
        supportsFee && feeCents > 0 ? feeCategoryId || 'cat-fees' : undefined,
      accountId,
      destinationAccountId: kind === 'transfer' ? destAccountId : undefined,
      categoryId,
      partyId: resolvedPartyId || undefined,
      occurrenceDate: occurrenceDate || todayIso,
      movementDate: movementDate || occurrenceDate || todayIso,
      dueDate: dueDate || undefined,
      description: description.trim() || `${kind} entry`,
      payee: payee.trim() || undefined,
      correctedFromEntryId,
    });

    if (!res.ok) {
      setError(res.error || 'Could not post journal entry.');
      return;
    }
    onClose();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={correctedFromEntryId ? 'Correct & Replace Entry' : 'Finance Ledger Composer'}
      className="fixed inset-0 z-50 bg-black/55 flex items-center justify-center p-4"
    >
      <form
        onSubmit={handleFormSubmit}
        className="w-full max-w-lg rounded-[var(--dw-radius-lg)] bg-[var(--dw-card)] border border-[var(--dw-border)] p-5 space-y-4 max-h-[90vh] overflow-y-auto text-xs text-[var(--dw-text-primary)] shadow-xl"
      >
        <div className="flex items-center justify-between gap-3">
          <div>
            <h3 className="dw-type-title text-[var(--dw-text-primary)]">
              {correctedFromEntryId ? 'Correct & Replace Entry' : 'Finance Ledger Composer'}
            </h3>
            {correctedFromEntryId && (
              <p className="text-[11px] text-[var(--dw-on-warning-container)] mt-0.5">
                Submitting will void the prior entry and post this replacement.
              </p>
            )}
          </div>
          <DaywellIconButton
            label="Close composer"
            size="compact"
            tone="muted"
            onClick={onClose}
            icon={<X className="w-4 h-4" />}
          />
        </div>

        {/* Mode selector (locked when replacing an existing entry to prevent unsafe type/debt conversion) */}
        <div className="flex flex-wrap gap-1.5">
          {(
            [
              ['expense', 'Expense'],
              ['income', 'Income'],
              ['transfer', 'Transfer'],
              ['split', 'Split Expense'],
              ['lend', 'Lend'],
              ['borrow', 'Borrow'],
            ] as const
          ).map(([k, label]) => {
            const isLocked = Boolean(correctedFromEntryId) && k !== kind;
            return (
              <button
                key={k}
                type="button"
                disabled={isLocked}
                onClick={() => {
                  if (correctedFromEntryId) return;
                  setKind(k);
                  setError(null);
                }}
                className={`px-2.5 py-1.5 rounded-[var(--dw-radius-sm)] font-semibold whitespace-nowrap shrink-0 transition-colors ${
                  kind === k
                    ? 'bg-[var(--dw-primary)] text-[var(--dw-on-primary)] cursor-pointer'
                    : isLocked
                    ? 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-disabled)] opacity-50 cursor-not-allowed'
                    : 'bg-[var(--dw-surface-subtle)] text-[var(--dw-text-secondary)] hover:text-[var(--dw-text-primary)] cursor-pointer'
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>

        {error && <DaywellStatusBanner tone="error" message={error} />}
        {activeAccounts.length === 0 && (
          <DaywellStatusBanner
            tone="error"
            message="No active ETB accounts available. Add or restore an ETB account first."
          />
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
              {kind === 'split' ? 'My Share (ETB)' : 'Amount (ETB)'}
            </label>
            <input
              type="number"
              step="0.01"
              value={amountStr}
              onChange={(e) => setAmountStr(e.target.value)}
              className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums text-sm font-semibold focus:outline-none focus:border-[var(--dw-primary)]"
              placeholder="0.00"
              autoFocus
            />
          </div>

          {kind === 'split' && (
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                Their Share / Receivable (ETB)
              </label>
              <input
                type="number"
                step="0.01"
                value={theirShareStr}
                onChange={(e) => setTheirShareStr(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums text-sm font-semibold focus:outline-none focus:border-[var(--dw-primary)]"
                placeholder="0.00"
              />
            </div>
          )}

          {(kind === 'expense' || kind === 'transfer') && (
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                {kind === 'transfer'
                  ? 'Bank / Transfer Fee (ETB)'
                  : 'Bank / Service Fee (ETB, optional)'}
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={feeStr}
                onChange={(e) => setFeeStr(e.target.value)}
                placeholder="0.00"
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono tabular-nums focus:outline-none focus:border-[var(--dw-primary)]"
              />
            </div>
          )}

          {(kind === 'expense' || kind === 'transfer') &&
            (tryParseStrictDecimalToCents(feeStr) ?? 0) > 0 && (
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Fee Category
                </label>
                <select
                  value={feeCategoryId}
                  onChange={(e) => setFeeCategoryId(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] focus:outline-none focus:border-[var(--dw-primary)]"
                >
                  {feeCategoryOptions.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </div>
            )}

          <div>
            <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
              {kind === 'transfer' ? 'From Account' : kind === 'income' || kind === 'borrow' ? 'To Account' : 'Paid From Account'}
            </label>
            <select
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
              className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] focus:outline-none focus:border-[var(--dw-primary)]"
            >
              {activeAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>

          {kind === 'transfer' && (
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">To Account</label>
              <select
                value={destAccountId}
                onChange={(e) => setDestAccountId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] focus:outline-none focus:border-[var(--dw-primary)]"
              >
                {activeAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {(kind === 'expense' || kind === 'income' || kind === 'split') && (
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Category</label>
              <select
                value={categoryId}
                onChange={(e) => setCategoryId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] focus:outline-none focus:border-[var(--dw-primary)]"
              >
                {(kind === 'income' ? incomeCategories : expenseCategories).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
          )}
        </div>

        {kind === 'expense' &&
          (() => {
            const principalCents = tryParseStrictDecimalToCents(amountStr) ?? 0;
            const parsedFeeCents = tryParseStrictDecimalToCents(feeStr) ?? 0;
            if (principalCents <= 0 || parsedFeeCents <= 0) return null;
            return (
              <div className="px-3 py-2 rounded-[var(--dw-radius-sm)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] text-xs text-[var(--dw-text-secondary)] flex flex-wrap items-center justify-between gap-2">
                <span>
                  Principal {formatCurrencyCents(principalCents, 'ETB')} + Fee{' '}
                  {formatCurrencyCents(parsedFeeCents, 'ETB')}
                </span>
                <span className="font-semibold font-mono tabular-nums text-[var(--dw-text-primary)]">
                  Total deduction:{' '}
                  {formatCurrencyCents(principalCents + parsedFeeCents, 'ETB')}
                </span>
              </div>
            );
          })()}

        {needsParty && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-3 rounded-[var(--dw-radius-md)] bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)]">
            <div>
              <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Counterparty</label>
              <select
                value={partyId}
                onChange={(e) => setPartyId(e.target.value)}
                className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
              >
                <option value="">+ Create new counterparty</option>
                {parties.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            {!partyId ? (
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  New Person / Organization Name
                </label>
                <input
                  type="text"
                  value={newPartyName}
                  onChange={(e) => setNewPartyName(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)]"
                  placeholder="e.g. Abebe"
                />
              </div>
            ) : (
              <div>
                <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
                  Due Date (Optional)
                </label>
                <input
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] font-mono"
                />
              </div>
            )}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
              Occurrence Date (Economic P&amp;L)
            </label>
            <input
              type="date"
              value={occurrenceDate}
              onChange={(e) => {
                setOccurrenceDate(e.target.value);
                if (movementDate === occurrenceDate) setMovementDate(e.target.value);
              }}
              className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
            />
          </div>
          <div>
            <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
              Cash Movement Date
            </label>
            <input
              type="date"
              value={movementDate}
              onChange={(e) => setMovementDate(e.target.value)}
              className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] font-mono"
            />
          </div>
        </div>

        <div>
          <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">Description</label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
            placeholder="What was this for?"
          />
        </div>

        {(kind === 'expense' || kind === 'income') && (
          <div>
            <label className="block font-medium text-[var(--dw-text-secondary)] mb-1">
              Payee / Source (Optional)
            </label>
            <input
              type="text"
              value={payee}
              onChange={(e) => setPayee(e.target.value)}
              className="w-full px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-canvas)] text-[var(--dw-text-primary)]"
              placeholder="Merchant, employer, or person"
            />
          </div>
        )}

        <div className="flex justify-end gap-2 pt-3 border-t border-[var(--dw-divider)]">
          <DaywellButton label="Cancel" variant="text" size="compact" onClick={onClose} />
          <DaywellButton
            type="submit"
            label={correctedFromEntryId ? 'Replace Entry' : 'Post Journal Entry'}
            variant="primary"
            size="compact"
          />
        </div>
      </form>
    </div>
  );
}
