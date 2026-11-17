import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  CANONICAL_SEED_DATABASE,
  KNOWN_SEED_IDS,
  isKnownSeedId,
  SharedAccount,
  SharedCategory,
  SharedTransaction,
  SharedTask,
  SharedNote,
  calculateSharedAccountBalance,
  calculateSharedCombinedBalance,
} from './sharedFoundation';
import { SharedStateBridge } from '../services/sharedStateBridge';

describe('STAGE 2: DUMMY DATA REMOVAL & CLEAN INITIALIZATION VERIFICATION', () => {
  it('1. Fresh Application Initialization: Canonical seed database starts with zero dummy records', () => {
    assert.strictEqual(CANONICAL_SEED_DATABASE.accounts.length, 0, 'Must have 0 pre-populated accounts');
    assert.strictEqual(CANONICAL_SEED_DATABASE.transactions.length, 0, 'Must have 0 pre-populated transactions');
    assert.strictEqual(CANONICAL_SEED_DATABASE.tasks.length, 0, 'Must have 0 pre-populated tasks');
    assert.strictEqual(CANONICAL_SEED_DATABASE.notes.length, 0, 'Must have 0 pre-populated notes');
    assert.strictEqual(CANONICAL_SEED_DATABASE.projects.length, 0, 'Must have 0 pre-populated projects');
    assert.strictEqual(CANONICAL_SEED_DATABASE.goals.length, 0, 'Must have 0 pre-populated goals');
    assert.strictEqual(CANONICAL_SEED_DATABASE.isFinanceSetupCompleted, false, 'Finance setup wizard must be active');
    assert.strictEqual(CANONICAL_SEED_DATABASE.openingBalanceCents, 0, 'Opening balance must start at 0 cents');
  });

  it('2. Legitimate Defaults Preserved: Standard Ethiopian income and expense categories remain available', () => {
    assert.strictEqual(CANONICAL_SEED_DATABASE.categories.length, 11, 'Must preserve 11 default categories');

    const expenseCategories = CANONICAL_SEED_DATABASE.categories.filter((c) => c.type === 'expense');
    const incomeCategories = CANONICAL_SEED_DATABASE.categories.filter((c) => c.type === 'income');

    assert.strictEqual(expenseCategories.length, 6, 'Should have 6 default expense categories');
    assert.strictEqual(incomeCategories.length, 5, 'Should have 5 default income categories');

    const categoryNames = CANONICAL_SEED_DATABASE.categories.map((c) => c.name);
    assert.ok(categoryNames.includes('Food'));
    assert.ok(categoryNames.includes('Transport'));
    assert.ok(categoryNames.includes('Housing'));
    assert.ok(categoryNames.includes('Utilities'));
    assert.ok(categoryNames.includes('Salary'));
    assert.ok(categoryNames.includes('Freelance & Business'));
  });

  it('3. Finance Setup: Allows user to initialize real accounts with real opening balances', () => {
    // Simulate user completing setup wizard with real accounts
    const userRealAccounts: SharedAccount[] = [
      {
        id: 'acc-user-cbe-real',
        name: 'My Personal CBE Account',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 2450000, // 24,500.00 ETB
        openingBalanceDate: '2026-11-11',
        isArchived: false,
      },
      {
        id: 'acc-user-telebirr-real',
        name: 'My Telebirr Wallet',
        type: 'asset',
        currencyCode: 'ETB',
        openingBalanceCents: 120000, // 1,200.00 ETB
        openingBalanceDate: '2026-11-11',
        isArchived: false,
      },
    ];

    const initialCombined = calculateSharedCombinedBalance(userRealAccounts, []);
    assert.strictEqual(initialCombined, 2570000, 'Combined balance must strictly equal sum of user accounts (25,700 ETB)');
  });

  it('4. Creating Actual Records: Transaction creation updates account and combined balances accurately', () => {
    const account: SharedAccount = {
      id: 'acc-real-1',
      name: 'Commercial Bank of Ethiopia',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 1000000, // 10,000.00 ETB
      isArchived: false,
    };

    const newTx: SharedTransaction = {
      id: 'tx-real-user-1',
      amountCents: 35000, // 350.00 ETB
      type: 'expense',
      accountId: 'acc-real-1',
      categoryId: 'cat-food',
      categoryName: 'Food',
      transactionDate: '2026-11-11T12:00:00Z',
    };

    const bal = calculateSharedAccountBalance(account, [newTx]);
    assert.strictEqual(bal, 965000, 'Account balance must be 9,650.00 ETB after deducting 350.00 ETB');

    const combined = calculateSharedCombinedBalance([account], [newTx]);
    assert.strictEqual(combined, 965000, 'Combined balance must equal 9,650.00 ETB');
  });

  it('5. Editing and Deleting Actual Records: Balance restores cleanly without synthetic entries', () => {
    const account: SharedAccount = {
      id: 'acc-real-1',
      name: 'Commercial Bank of Ethiopia',
      type: 'asset',
      currencyCode: 'ETB',
      openingBalanceCents: 1000000, // 10,000.00 ETB
      isArchived: false,
    };

    const tx: SharedTransaction = {
      id: 'tx-real-user-1',
      amountCents: 50000, // 500.00 ETB
      type: 'expense',
      accountId: 'acc-real-1',
      transactionDate: '2026-11-11',
    };

    // Before deletion
    assert.strictEqual(calculateSharedAccountBalance(account, [tx]), 950000);

    // After deletion (voiding/removal)
    assert.strictEqual(calculateSharedAccountBalance(account, []), 1000000, 'Deleting expense restores exact balance');
  });

  it('6. Known Seed ID Detection: Accurately identifies demonstration IDs across all modules', () => {
    assert.ok(isKnownSeedId('acc-cbe'));
    assert.ok(isKnownSeedId('acc-boa'));
    assert.ok(isKnownSeedId('tx-seed-1'));
    assert.ok(isKnownSeedId('task-seed-1'));
    assert.ok(isKnownSeedId('t-1'));
    assert.ok(isKnownSeedId('note-seed-1'));
    assert.ok(isKnownSeedId('note-1'));
    assert.ok(isKnownSeedId('evt-1'));
    assert.ok(isKnownSeedId('com-1'));
    assert.ok(isKnownSeedId('sav-1'));
    assert.ok(isKnownSeedId('inbox-1'));
    assert.ok(isKnownSeedId('party-abebe'));

    // Genuine user-generated IDs must NOT be flagged as seed IDs
    assert.strictEqual(isKnownSeedId('acc-custom-user-99'), false);
    assert.strictEqual(isKnownSeedId('tx-user-lunch-101'), false);
    assert.strictEqual(isKnownSeedId('task-user-rent-check'), false);
    assert.strictEqual(isKnownSeedId('note-personal-diary-1'), false);
    assert.strictEqual(isKnownSeedId('evt-meeting-with-manager'), false);
  });

  it('7. Safe Purge Logic: Purges seed records while strictly preserving user records and accounts with history', () => {
    // Simulated legacy database with mixed demo and user data
    const mixedAccounts: SharedAccount[] = [
      { id: 'acc-cbe', name: 'CBE', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 1500000, isArchived: false },
      { id: 'acc-boa', name: 'BOA', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 500000, isArchived: false },
      { id: 'acc-user-dashen', name: 'User Real Dashen', type: 'asset', currencyCode: 'ETB', openingBalanceCents: 800000, isArchived: false },
    ];

    const mixedTransactions: SharedTransaction[] = [
      { id: 'tx-seed-1', amountCents: 125000, type: 'expense', accountId: 'acc-cbe', transactionDate: '2026-11-08' },
      // User recorded a real salary on CBE!
      { id: 'tx-user-real-salary', amountCents: 4500000, type: 'income', accountId: 'acc-cbe', transactionDate: '2026-11-10' },
      // User recorded a real grocery on BOA!
      { id: 'tx-user-real-grocery', amountCents: 120000, type: 'expense', accountId: 'acc-boa', transactionDate: '2026-11-10' },
    ];

    const mixedTasks: SharedTask[] = [
      { id: 'task-seed-1', title: 'Review weekly financial ledger', status: 'not_started', priority: 'high', createdAt: '2026-11-01' },
      { id: 't-1', title: 'Review portfolio case study & submit deck', status: 'not_started', priority: 'urgent', createdAt: '2026-11-01' },
      { id: 'task-user-custom', title: 'Call contractor about balcony repair', status: 'not_started', priority: 'medium', createdAt: '2026-11-11' },
    ];

    const mixedNotes: SharedNote[] = [
      { id: 'note-seed-1', title: 'Personal Strategy & Capital Allocation', body: 'Strategy', tags: [], isPinned: true, isArchived: false, createdAt: '2026-11-01', updatedAt: '2026-11-01' },
      { id: 'note-user-real', title: 'Doctor prescription notes', body: 'Take medication twice daily', tags: ['health'], isPinned: false, isArchived: false, createdAt: '2026-11-11', updatedAt: '2026-11-11' },
    ];

    // Filter transactions: purge seed transactions
    const cleanedTxs = mixedTransactions.filter((t) => !(KNOWN_SEED_IDS.transactions as readonly string[]).includes(t.id));
    assert.strictEqual(cleanedTxs.length, 2, 'Only user transactions remain');
    assert.strictEqual(cleanedTxs[0].id, 'tx-user-real-salary');
    assert.strictEqual(cleanedTxs[1].id, 'tx-user-real-grocery');

    // Filter accounts: CBE and BOA have real user transactions, so they MUST BE PRESERVED!
    const cleanedAccounts = mixedAccounts.filter((a) => {
      if ((KNOWN_SEED_IDS.accounts as readonly string[]).includes(a.id)) {
        const hasUserTx = cleanedTxs.some((t) => t.accountId === a.id || t.destinationAccountId === a.id);
        return hasUserTx; // Keep because user has transactions!
      }
      return true;
    });
    assert.strictEqual(cleanedAccounts.length, 3, 'All 3 accounts preserved because user recorded transactions on them');

    // Filter tasks: seed tasks removed, user task preserved
    const cleanedTasks = mixedTasks.filter((t) => !(KNOWN_SEED_IDS.tasks as readonly string[]).includes(t.id));
    assert.strictEqual(cleanedTasks.length, 1);
    assert.strictEqual(cleanedTasks[0].id, 'task-user-custom');

    // Filter notes: seed note removed, user note preserved
    const cleanedNotes = mixedNotes.filter((n) => !(KNOWN_SEED_IDS.notes as readonly string[]).includes(n.id));
    assert.strictEqual(cleanedNotes.length, 1);
    assert.strictEqual(cleanedNotes[0].id, 'note-user-real');
  });

  it('8. Cross-Platform Parity: Canonical export from Web produces clean payload for Android', () => {
    const cleanState = SharedStateBridge.assembleLiveDatabaseState();
    const json = SharedStateBridge.exportToAndroidJson(cleanState);
    const parsed = JSON.parse(json);

    assert.strictEqual(parsed.schemaVersion, 5);
    assert.strictEqual(parsed.appVersion, CANONICAL_SEED_DATABASE.appVersion);
    assert.strictEqual(parsed.accounts.length, 0);
    assert.strictEqual(parsed.transactions.length, 0);
    assert.strictEqual(parsed.tasks.length, 0);
    assert.strictEqual(parsed.notes.length, 0);
    assert.strictEqual(parsed.categories.length, 11);
    assert.strictEqual(parsed.isFinanceSetupCompleted, false);
  });
});
