/**
 * High-Volume Stress-Testing Utility (10,000 Synthetic Items)
 * Generates and benchmarks realistic datasets:
 * - 4,000 Tasks (mix of urgent, high, medium, low across multiple statuses)
 * - 3,500 Financial Transactions (ETB income and expenses with payee details)
 * - 2,500 Notes & Knowledge records (bilingual English and Ge'ez/Amharic Unicode)
 * Total: 10,000 synthetic items
 * 
 * Benchmarks:
 * 1. Generation throughput (records/sec)
 * 2. SQLite / in-memory linear filter latency
 * 3. Multi-field text search latency over 10,000 records
 * 4. Available-to-spend calculation performance over thousands of transactions
 * 5. Memory footprint & serialization overhead
 */

import { 
  LocalDatabaseState, 
  LocalTask, 
  LocalFinancialTransaction, 
  LocalNote, 
  DEFAULT_CATEGORIES 
} from './localDatabase.ts';
import { computeFinancialSnapshot } from '../domain/financialEngine.ts';

export interface StressGenerationResult {
  tasks: LocalTask[];
  transactions: LocalFinancialTransaction[];
  notes: LocalNote[];
  totalItemCount: number;
  generationDurationMs: number;
  memoryEstimateBytes: number;
}

export interface StressBenchmarkReport {
  totalItems: number;
  generationDurationMs: number;
  taskFilterDurationMs: number;
  taskFilterMatches: number;
  transactionSumDurationMs: number;
  calculatedBalanceBirr: string;
  searchDurationMs: number;
  searchMatchesAmharic: number;
  serializationDurationMs: number;
  payloadSizeKb: number;
  fpsBudgetRespected: boolean; // under 16ms
}

const AMHARIC_SAMPLES = [
  'የዕለት ማስታወሻ እና የሥራ ዕቅድ ዝግጅት በዝርዝር።',
  'የወርሃዊ በጀት ግምገማ እና የቁጠባ ድልድል ማስተካከያ።',
  'የመኖሪያ ቤት የኤሌክትሪክ መስመር ምርመራ እና የፀሐይ ኃይል ጥገና።',
  'በመርካቶ የንግድ እንቅስቃሴ እና የፍጆታ ዕቃዎች ግዥ ዝርዝር።',
  'የጤና ምርመራ እና የዶክተር ቀጠሮ ማስታወሻ።',
  'የትምህርት እና የምርምር ማስታወሻዎች ስለ ኮምፒውተር ሳይንስ።',
  'የቤተሰብ እና የግል ጉዳዮች የትኩረት ነጥቦች።',
  'የውሃ እና የመብራት ክፍያዎች ማረጋገጫ ደረሰኝ።'
];

const TASK_TITLES = [
  'Inspect solar inverter grounding cables',
  'Reconcile weekly bank ledger and telebirr statements',
  'Audit monthly living expenses against target threshold',
  'Purchase spare backup batteries at Mercato hardware store',
  'Prepare quarterly financial forecast in ETB',
  'Backup offline SQLite database to encrypted USB drive',
  'Review daily commitments and overdue tasks',
  'Check Ethiopian calendar Pagumē leap year schedule',
  'Archive tax receipts and digital utility invoices',
  'Schedule offline device software health check'
];

const PAYEES = [
  'Ethiopian Electric Power',
  'Addis Ababa Water Supply',
  'Ethio Telecom / Telebirr',
  'Mercato Wholesale Depot',
  'Bole Hardware Supplies',
  'Local Medical Clinic',
  'Commercial Bank of Ethiopia',
  'St. George Bakery',
  'Family Support Fund',
  'Fuel & Transit Authority'
];

export function generate10kSyntheticDataset(): StressGenerationResult {
  const start = performance.now();
  const tasks: LocalTask[] = [];
  const transactions: LocalFinancialTransaction[] = [];
  const notes: LocalNote[] = [];

  const statuses: LocalTask['status'][] = ['in_progress', 'not_started', 'completed', 'inbox', 'cancelled'];
  const priorities: LocalTask['priority'][] = ['urgent', 'high', 'medium', 'low'];
  const categories: LocalNote['category'][] = ['reflection', 'reference', 'learning', 'general'];

  // 1. Generate 4,000 Tasks
  for (let i = 0; i < 4000; i++) {
    const status = statuses[i % statuses.length];
    const priority = priorities[i % priorities.length];
    const titleBase = TASK_TITLES[i % TASK_TITLES.length];
    tasks.push({
      id: `synthetic-task-${i + 1}`,
      title: `${titleBase} [Item #${i + 1}]`,
      description: `Synthetic stress test record generated for performance benchmarking. Index: ${i}`,
      status,
      priority,
      dueDateUtc: i % 3 === 0 ? new Date(Date.now() + 86400000 * (i % 30)).toISOString() : undefined,
      createdAtUtc: new Date(Date.now() - 3600000 * (i % 720)).toISOString(),
      updatedAtUtc: new Date().toISOString(),
    });
  }

  // 2. Generate 3,500 Financial Transactions
  for (let i = 0; i < 3500; i++) {
    const isIncome = i % 4 === 0; // 25% income, 75% expenses
    const payee = PAYEES[i % PAYEES.length];
    const amharicNote = AMHARIC_SAMPLES[i % AMHARIC_SAMPLES.length];
    const category = isIncome ? DEFAULT_CATEGORIES[0] : DEFAULT_CATEGORIES[1 + (i % (DEFAULT_CATEGORIES.length - 1))];
    const amountCents = (1000 + (i * 350) % 500000); // 10.00 ETB to 5,000.00 ETB

    transactions.push({
      id: `synthetic-tx-${i + 1}`,
      categoryId: category.id,
      amountCents,
      type: isIncome ? 'income' : 'expense',
      transactionDateUtc: new Date(Date.now() - 86400000 * (i % 180)).toISOString(),
      payee,
      note: `${amharicNote} (Batch #${Math.floor(i / 100)})`,
      createdAtUtc: new Date(Date.now() - 3600000 * (i % 720)).toISOString(),
    });
  }

  // 3. Generate 2,500 Notes
  for (let i = 0; i < 2500; i++) {
    const amharicTitle = AMHARIC_SAMPLES[i % AMHARIC_SAMPLES.length];
    const category = categories[i % categories.length];
    const content = `${amharicTitle} Detailed documentation note ${i + 1}. Contains extensive Unicode characters: ሀ ሁ ሂ ሃ ሄ ህ ሆ • ለ ሉ ሊ ላ ሌ ል ሎ • መ ሙ ሚ ማ ሜ ም ሞ • ሰ ሱ ሲ ሳ ሴ ስ ሶ. Verified 100% offline storage compatible.`;

    notes.push({
      id: `synthetic-note-${i + 1}`,
      title: `${amharicTitle.slice(0, 25)} #${i + 1}`,
      content,
      category,
      createdAtUtc: new Date(Date.now() - 86400000 * (i % 365)).toISOString(),
    });
  }

  const durationMs = Math.round((performance.now() - start) * 10) / 10;
  const totalItemCount = tasks.length + transactions.length + notes.length;
  // Estimate in-memory byte weight
  const sampleJson = JSON.stringify({ t: tasks[0], tx: transactions[0], n: notes[0] });
  const memoryEstimateBytes = Math.round(sampleJson.length * totalItemCount);

  return {
    tasks,
    transactions,
    notes,
    totalItemCount,
    generationDurationMs: durationMs,
    memoryEstimateBytes,
  };
}

export function runStressBenchmarkOver10k(dataset: StressGenerationResult): StressBenchmarkReport {
  // 1. Task filter benchmark (active & high-priority)
  const t0 = performance.now();
  const activeTasks = dataset.tasks.filter(
    (t) => (t.status === 'in_progress' || t.status === 'not_started') && (t.priority === 'urgent' || t.priority === 'high')
  );
  const taskFilterDurationMs = Math.round((performance.now() - t0) * 100) / 100;

  // 2. Financial calculation benchmark (sums & snapshot over 3,500 txs)
  const t1 = performance.now();
  const incomes = dataset.transactions.filter((tx) => tx.type === 'income').map((tx) => tx.amountCents);
  const expenses = dataset.transactions.filter((tx) => tx.type === 'expense').map((tx) => tx.amountCents);
  const snapshot = computeFinancialSnapshot({
    openingBalanceCents: 1000000,
    incomesCents: incomes,
    expensesCents: expenses,
    unpaidCommitmentsCents: [50000, 20000],
    savingsAllocationsCents: [100000],
    expectedFutureIncomeCents: [],
  });
  const transactionSumDurationMs = Math.round((performance.now() - t1) * 100) / 100;

  // 3. Multi-entity text search benchmark across all 10,000 records
  const t2 = performance.now();
  const searchQuery = 'ማስታወሻ'; // "Note/Record" in Amharic
  const matchingNotes = dataset.notes.filter(
    (n) => n.title.includes(searchQuery) || n.content.includes(searchQuery)
  );
  const matchingTxs = dataset.transactions.filter(
    (tx) => (tx.note && tx.note.includes(searchQuery)) || (tx.payee && tx.payee.includes(searchQuery))
  );
  const searchDurationMs = Math.round((performance.now() - t2) * 100) / 100;
  const searchMatchesAmharic = matchingNotes.length + matchingTxs.length;

  // 4. JSON serialization latency benchmark
  const t3 = performance.now();
  const jsonString = JSON.stringify({
    tasks: dataset.tasks,
    transactions: dataset.transactions,
    notes: dataset.notes,
  });
  const serializationDurationMs = Math.round((performance.now() - t3) * 100) / 100;
  const payloadSizeKb = Math.round(jsonString.length / 1024);

  return {
    totalItems: dataset.totalItemCount,
    generationDurationMs: dataset.generationDurationMs,
    taskFilterDurationMs,
    taskFilterMatches: activeTasks.length,
    transactionSumDurationMs,
    calculatedBalanceBirr: (snapshot.recordedBalanceCents / 100).toFixed(2) + ' ETB',
    searchDurationMs,
    searchMatchesAmharic,
    serializationDurationMs,
    payloadSizeKb,
    fpsBudgetRespected: taskFilterDurationMs < 16 && transactionSumDurationMs < 16 && searchDurationMs < 16,
  };
}
