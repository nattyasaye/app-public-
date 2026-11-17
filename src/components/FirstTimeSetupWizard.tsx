import React, { useState } from 'react';
import {
  User,
  Wallet,
  CheckCircle2,
  ArrowRight,
  ArrowLeft,
  Plus,
  Trash2,
  ShieldCheck,
  Building2,
  Calendar,
} from 'lucide-react';
import {
  Account,
  CategoryBudget,
} from '../domain/doubleEntryFinance';
import { formatBirr, parseDecimalToCentsStrict } from '../domain/financialEngine';
import { CalendarDate, EthiopiaClock } from '../domain/date';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellStatusBanner,
  DaywellTextField,
} from './ui';

export interface UserProfile {
  name: string;
  completed: boolean;
  setupDate?: string;
}

interface FirstTimeSetupWizardProps {
  onComplete: (profile: UserProfile, accounts: Account[], budgets: CategoryBudget[]) => void;
  initialName?: string;
}

export function FirstTimeSetupWizard({ onComplete, initialName = '' }: FirstTimeSetupWizardProps) {
  const [step, setStep] = useState<1 | 2 | 3>(1);

  // Step 1: User Profile
  const [userName, setUserName] = useState(initialName);
  const [nameError, setNameError] = useState('');

  const todayStr = CalendarDate.today().toIsoString();

  // Step 2: Accounts & Opening Balances
  const [setupAccounts, setSetupAccounts] = useState<Array<{
    id: string;
    name: string;
    balanceText: string;
    openingDate: string;
    isActive: boolean;
  }>>([
    { id: 'acc-cbe', name: 'CBE', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-boa', name: 'BOA', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-dashen', name: 'Dashen Bank', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-telebirr', name: 'Telebirr', balanceText: '', openingDate: todayStr, isActive: true },
    { id: 'acc-cash', name: 'Cash', balanceText: '', openingDate: todayStr, isActive: true },
  ]);

  const [newAccountName, setNewAccountName] = useState('');
  const [newAccountBalance, setNewAccountBalance] = useState('');
  const [accountError, setAccountError] = useState('');

  // Step 1 Validation
  const handleProceedFromStep1 = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = userName.trim();
    if (!trimmed) {
      setNameError('Please enter your name to personalize your workspace.');
      return;
    }
    setNameError('');
    setStep(2);
  };

  // Add Custom Account
  const handleAddCustomAccount = () => {
    const trimmedName = newAccountName.trim();
    if (!trimmedName) {
      setAccountError('Account name cannot be empty.');
      return;
    }
    if (setupAccounts.some((a) => a.name.toLowerCase() === trimmedName.toLowerCase())) {
      setAccountError('An account with this name already exists.');
      return;
    }
    setAccountError('');
    const newId = `acc-custom-${Date.now()}`;
    setSetupAccounts((prev) => [
      ...prev,
      {
        id: newId,
        name: trimmedName,
        balanceText: newAccountBalance.trim() || '0',
        openingDate: todayStr,
        isActive: true,
      },
    ]);
    setNewAccountName('');
    setNewAccountBalance('');
  };

  const handleToggleAccount = (id: string) => {
    setSetupAccounts((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, isActive: !acc.isActive } : acc))
    );
  };

  const handleUpdateAccountBalance = (id: string, balanceText: string) => {
    setSetupAccounts((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, balanceText } : acc))
    );
  };

  const handleUpdateAccountDate = (id: string, openingDate: string) => {
    setSetupAccounts((prev) =>
      prev.map((acc) => (acc.id === id ? { ...acc, openingDate } : acc))
    );
  };

  const handleRemoveAccount = (id: string) => {
    setSetupAccounts((prev) => prev.filter((acc) => acc.id !== id));
  };

  const handleProceedFromStep2 = () => {
    const active = setupAccounts.filter((a) => a.isActive);
    if (active.length === 0) {
      setAccountError('Please select or add at least one account to continue.');
      return;
    }
    for (const acc of active) {
      if (acc.balanceText.trim() !== '') {
        const parsed = parseDecimalToCentsStrict(acc.balanceText);
        if (!parsed.valid || parsed.cents < 0) {
          setAccountError(`Invalid balance for ${acc.name}. Please enter a valid non-negative ETB amount.`);
          return;
        }
      }
    }
    setAccountError('');
    setStep(3);
  };

  const handleFinalConfirm = () => {
    const finalAccounts: Account[] = setupAccounts
      .filter((acc) => acc.isActive)
      .map((acc) => {
        const parsed = acc.balanceText.trim() ? parseDecimalToCentsStrict(acc.balanceText) : null;
        const openingBalanceCents = parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0;
        return {
          id: acc.id,
          name: acc.name.trim() || 'Account',
          type: 'asset',
          currencyCode: 'ETB',
          openingBalanceCents,
          openingBalanceDate: acc.openingDate || todayStr,
          isArchived: false,
          createdAt: EthiopiaClock.nowUtc().toISOString(),
        };
      });

    const profile: UserProfile = {
      name: userName.trim(),
      completed: true,
      setupDate: EthiopiaClock.nowUtc().toISOString(),
    };

    onComplete(profile, finalAccounts, []);
  };

  const totalOpeningBalanceCents = setupAccounts
    .filter((a) => a.isActive)
    .reduce((sum, a) => {
      const parsed = a.balanceText.trim() ? parseDecimalToCentsStrict(a.balanceText) : null;
      return sum + (parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0);
    }, 0);

  return (
    <div className="min-h-screen bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] flex flex-col items-center justify-center p-4 sm:p-6">
      <DaywellCard
        radius="lg"
        padding="none"
        className="w-full max-w-2xl shadow-xl overflow-hidden"
      >
        {/* Header with step indicator */}
        <div className="bg-[var(--dw-primary-brand)] text-white p-6 sm:p-8">
          <div className="flex items-center justify-between gap-2 mb-4">
            <div className="flex items-center gap-2">
              <span className="w-8 h-8 rounded-[var(--dw-radius-full)] bg-white/20 flex items-center justify-center font-bold text-sm">
                {step}
              </span>
              <span className="dw-type-label uppercase tracking-wider text-white/85">
                Step {step} of 3 · Finance Setup
              </span>
            </div>
            <span className="dw-type-caption bg-white/15 px-3 py-1 rounded-[var(--dw-radius-sm)]">
              Daywell Personal Management
            </span>
          </div>

          <h1 className="dw-type-display text-white">
            {step === 1 && 'Welcome! Let’s personalize your app'}
            {step === 2 && 'Set up your financial accounts'}
            {step === 3 && 'Review & confirm your starting balances'}
          </h1>
          <p className="dw-type-body-compact text-white/85 mt-1">
            {step === 1 && 'Enter your real name so Daywell addresses you correctly.'}
            {step === 2 && 'Select the accounts you use and enter their starting balances. Opening balances are never counted as income.'}
            {step === 3 && 'Verify your starting financial position before launching your simplified ledger.'}
          </p>

          {/* Stepper progress bar */}
          <div className="flex gap-2 mt-6">
            {[1, 2, 3].map((s) => (
              <div
                key={s}
                className={`h-1.5 flex-1 rounded-[var(--dw-radius-full)] transition-all ${
                  s <= step ? 'bg-white' : 'bg-white/25'
                }`}
              />
            ))}
          </div>
        </div>

        {/* STEP 1: User Profile */}
        {step === 1 && (
          <form onSubmit={handleProceedFromStep1} className="p-6 sm:p-8 space-y-6">
            <DaywellTextField
              id="user-name-input"
              label="What should we call you? *"
              type="text"
              value={userName}
              onChange={(e) => setUserName(e.target.value)}
              placeholder="e.g. Natnael, Abebe, Kidist"
              leadingIcon={<User className="w-4 h-4" />}
              errorText={nameError || undefined}
              autoFocus
            />

            <DaywellStatusBanner
              tone="success"
              icon={<ShieldCheck className="w-5 h-5 shrink-0" />}
              title="Offline-First & Private"
              message="Daywell runs entirely on your device. Your financial accounts and balances remain completely private and stored locally."
            />

            <div className="flex justify-end pt-4">
              <DaywellButton
                type="submit"
                disabled={!userName.trim()}
                label="Continue to Accounts"
                trailingIcon={<ArrowRight className="w-4 h-4" />}
              />
            </div>
          </form>
        )}

        {/* STEP 2: Accounts & Opening Balances */}
        {step === 2 && (
          <div className="p-6 sm:p-8 space-y-6">
            <div>
              <h2 className="dw-type-label text-[var(--dw-text-secondary)] uppercase tracking-wider mb-1">
                Your Financial Accounts
              </h2>
              <p className="dw-type-body-compact text-[var(--dw-text-muted)]">
                Choose the accounts you use. Enter their actual starting balance (0 is completely valid).
              </p>
            </div>

            {accountError && (
              <DaywellStatusBanner tone="error" message={accountError} />
            )}

            <div className="space-y-3 max-h-[360px] overflow-y-auto pr-1">
              {setupAccounts.map((acc) => (
                <div
                  key={acc.id}
                  className={`p-4 rounded-[var(--dw-radius-md)] border transition-all ${
                    acc.isActive
                      ? 'border-[var(--dw-primary)]/40 bg-[var(--dw-surface-subtle)]'
                      : 'border-[var(--dw-border)] opacity-60 bg-[var(--dw-canvas)]'
                  }`}
                >
                  <div className="flex items-center justify-between gap-3 mb-3">
                    <label className="flex items-center gap-3 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={acc.isActive}
                        onChange={() => handleToggleAccount(acc.id)}
                        className="w-4 h-4 accent-[var(--dw-primary)] rounded border-[var(--dw-border)]"
                      />
                      <Building2 className="w-4 h-4 text-[var(--dw-primary)]" />
                      <span className="font-semibold text-sm text-[var(--dw-text-primary)]">
                        {acc.name}
                      </span>
                    </label>

                    {acc.id.startsWith('acc-custom') && (
                      <DaywellIconButton
                        label="Remove custom account"
                        size="compact"
                        tone="danger"
                        onClick={() => handleRemoveAccount(acc.id)}
                        icon={<Trash2 className="w-4 h-4" />}
                      />
                    )}
                  </div>

                  {acc.isActive && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                      <div>
                        <label className="block dw-type-caption text-[var(--dw-text-muted)] mb-1">
                          Opening Balance (ETB)
                        </label>
                        <div className="relative">
                          <input
                            type="text"
                            inputMode="decimal"
                            value={acc.balanceText}
                            onChange={(e) => handleUpdateAccountBalance(acc.id, e.target.value)}
                            placeholder="0.00"
                            className="w-full min-h-[42px] px-3 py-2 pl-12 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-sm text-[var(--dw-text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--dw-primary)]/25 focus:border-[var(--dw-primary)]"
                          />
                          <span className="dw-type-label text-[var(--dw-text-muted)] absolute left-3 top-3">
                            ETB
                          </span>
                        </div>
                      </div>

                      <div>
                        <label className="block dw-type-caption text-[var(--dw-text-muted)] mb-1">
                          Opening Date
                        </label>
                        <div className="relative">
                          <input
                            type="date"
                            value={acc.openingDate}
                            onChange={(e) => handleUpdateAccountDate(acc.id, e.target.value)}
                            className="w-full min-h-[42px] px-3 py-2 pl-9 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-sm text-[var(--dw-text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--dw-primary)]/25 focus:border-[var(--dw-primary)]"
                          />
                          <Calendar className="w-4 h-4 text-[var(--dw-text-muted)] absolute left-3 top-3 pointer-events-none" />
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>

            {/* Add Custom Account */}
            <div className="border border-dashed border-[var(--dw-border)] rounded-[var(--dw-radius-md)] p-4 bg-[var(--dw-surface-subtle)]/50">
              <p className="dw-type-label text-[var(--dw-text-secondary)] mb-2">
                Need another account? (e.g. Awash Bank, Zemen, Coop)
              </p>
              <div className="flex flex-col sm:flex-row gap-2">
                <input
                  type="text"
                  value={newAccountName}
                  onChange={(e) => setNewAccountName(e.target.value)}
                  placeholder="Account name"
                  className="flex-1 min-h-[42px] px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-xs text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)]"
                />
                <input
                  type="text"
                  inputMode="decimal"
                  value={newAccountBalance}
                  onChange={(e) => setNewAccountBalance(e.target.value)}
                  placeholder="Balance (e.g. 500)"
                  className="w-full sm:w-32 min-h-[42px] px-3 py-2 rounded-[var(--dw-radius-sm)] border border-[var(--dw-border)] bg-[var(--dw-card)] text-xs text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)]"
                />
                <DaywellButton
                  label="Add"
                  variant="tonal"
                  size="compact"
                  disabled={!newAccountName.trim()}
                  onClick={handleAddCustomAccount}
                  leadingIcon={<Plus className="w-3.5 h-3.5" />}
                />
              </div>
            </div>

            <div className="flex items-center justify-between pt-4 border-t border-[var(--dw-divider)]">
              <DaywellButton
                label="Back"
                variant="outlined"
                onClick={() => setStep(1)}
                leadingIcon={<ArrowLeft className="w-4 h-4" />}
              />

              <DaywellButton
                label="Review Setup"
                variant="primary"
                disabled={!setupAccounts.some((a) => a.isActive)}
                onClick={handleProceedFromStep2}
                trailingIcon={<ArrowRight className="w-4 h-4" />}
              />
            </div>
          </div>
        )}

        {/* STEP 3: Review & Confirm */}
        {step === 3 && (
          <div className="p-6 sm:p-8 space-y-6">
            <div>
              <h2 className="dw-type-label text-[var(--dw-text-secondary)] uppercase tracking-wider mb-1">
                Starting Financial Position Summary
              </h2>
              <p className="dw-type-body-compact text-[var(--dw-text-muted)]">
                Please review your starting accounts before opening your simplified dashboard.
              </p>
            </div>

            {/* Total Combined Starting Balance */}
            <div className="bg-[var(--dw-primary-brand)] text-white p-5 rounded-[var(--dw-radius-md)] flex items-center justify-between shadow-xs">
              <div>
                <span className="dw-type-label uppercase tracking-wider text-white/85 block mb-1">
                  Total Combined Starting Balance
                </span>
                <span className="dw-type-numeric-hero">
                  {formatBirr(totalOpeningBalanceCents)}
                </span>
              </div>
              <Wallet className="w-10 h-10 text-white/40" aria-hidden="true" />
            </div>

            {/* Account Breakdown */}
            <div className="border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] divide-y divide-[var(--dw-divider)] overflow-hidden">
              <div className="bg-[var(--dw-surface-subtle)] px-4 py-2 dw-type-caption uppercase text-[var(--dw-text-muted)] tracking-wider flex justify-between font-bold">
                <span>Account</span>
                <span>Opening Balance</span>
              </div>
              {setupAccounts
                .filter((a) => a.isActive)
                .map((acc) => {
                  const parsed = acc.balanceText.trim()
                    ? parseDecimalToCentsStrict(acc.balanceText)
                    : null;
                  const balCents = parsed && parsed.valid && parsed.cents > 0 ? parsed.cents : 0;
                  return (
                    <div key={acc.id} className="px-4 py-3 flex items-center justify-between text-sm">
                      <div>
                        <span className="font-semibold text-[var(--dw-text-primary)] block">
                          {acc.name}
                        </span>
                        <span className="text-xs text-[var(--dw-text-muted)]">
                          Date: {acc.openingDate}
                        </span>
                      </div>
                      <span className="dw-type-numeric-body text-[var(--dw-text-primary)]">
                        {formatBirr(balCents)}
                      </span>
                    </div>
                  );
                })}
            </div>

            <DaywellStatusBanner
              tone="success"
              icon={<CheckCircle2 className="w-5 h-5 shrink-0" />}
              title="Ready for Accurate Tracking"
              message="These opening balances establish your starting point. They will not be counted as income or salary transactions."
            />

            <div className="flex items-center justify-between pt-4 border-t border-[var(--dw-divider)]">
              <DaywellButton
                label="Back"
                variant="text"
                onClick={() => setStep(2)}
                leadingIcon={<ArrowLeft className="w-4 h-4" />}
              />

              <DaywellButton
                label="Complete Setup & Open Finance"
                variant="primary"
                onClick={handleFinalConfirm}
                leadingIcon={<CheckCircle2 className="w-4 h-4" />}
              />
            </div>
          </div>
        )}
      </DaywellCard>
    </div>
  );
}
