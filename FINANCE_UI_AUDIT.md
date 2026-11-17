# FINANCE_UI_AUDIT.md — Preview vs. Installed Android Application

> **Phase**: 1 (Complete UI Inspection and Comparison Only — No UI Changes Implemented)  
> **Date**: 2026-11-10  
> **Preview Reference**: `src/components/DaywellFinanceModule.tsx` (React + Vite + Tailwind CSS, 3,060 lines)  
> **Android Implementation**: `flutter_app/lib/ui/screens/finance_view.dart` (Flutter/Dart, 686 lines)

---

## 1. Executive Summary & Root Cause

The AI Studio Preview tab renders the **React/TypeScript web application** (`src/components/DaywellFinanceModule.tsx`), whereas the installed Android APK is compiled from the **Flutter/Dart application** (`flutter_app/lib/ui/screens/finance_view.dart`). They are two completely separate UI implementations.

While `DaywellFinanceModule.tsx` was rebuilt with a comprehensive 4-tab layout (`Overview`, `Transactions`, `Accounts`, `Categories`), a 2-step First-Time Finance Setup wizard, full transaction detail/edit/delete-confirmation modals, account rename/archive/delete guards, category management, and dual Ethiopian-Gregorian date formatting, `finance_view.dart` in Flutter is still an earlier 686-line implementation with only 2 modals (`_showAddTransactionModal` and `_showAddAccountModal`) and none of the newer management screens or dialogs.

---

## 2. Complete List of Finance Screens & Interactions Inspected

### Preview (`src/components/DaywellFinanceModule.tsx`)
1. First-Time Finance Setup Wizard (2-step onboarding: Welcome/Accounts + Opening Balances)
2. Finance Main Header & 4-Tab Bar (`Overview`, `Transactions`, `Accounts`, `Categories`)
3. **Overview Tab**: Combined Balance Hero Card, Quick Action Buttons (`+ Expense`, `+ Income`, `Transfer`), Active Accounts Horizontal/Grid Cards, Recent Transactions List
4. **Transactions Tab**: Search Input, Type Filter Chips (`All`, `Expense`, `Income`, `Transfer`), Account Filter Dropdown, Transaction List with Dual Dates & Color Coding
5. **Accounts Tab**: Active Accounts List, Archived Accounts Section, Add Account Modal, Rename Account Modal, Archive/Unarchive Toggle, Safe Deletion Guard
6. **Categories Tab**: Expense vs. Income Sub-tabs, Add Category Modal, Edit/Rename Category Modal, Safe Deletion Guard
7. **Transaction Modals**: Add/Edit Transaction Modal (Expense/Income), Transfer Modal, Transaction Details Modal, Delete Transaction Confirmation Dialog, 5-Second Ephemeral Undo Toast

### Installed Android (`flutter_app/lib/ui/screens/finance_view.dart`)
1. Finance Main Screen (`FinanceView`) with Combined Balance Card and Quick Action Buttons
2. Add Transaction Modal (`_showAddTransactionModal`)
3. Add Account Modal (`_showAddAccountModal`)

---

## 3. Detailed Preview vs. Android Comparison

| Finance screen/component | Preview appearance/behavior | Installed Android appearance/behavior | Difference | Priority |
|---|---|---|---|---|
| **First-Time Finance Setup** | 2-step onboarding wizard when `!isSetupCompleted` (default accounts CBE, BOA, Dashen, Telebirr, Cash + opening balances) | Not implemented; lands directly on main Finance screen | Missing onboarding flow | **Medium** |
| **Main Dashboard / Tab Structure** | 4-tab navigation (`Overview`, `Transactions`, `Accounts`, `Categories`) | Single scrollable view without the 4-tab structure | Missing `Transactions`, `Accounts`, and `Categories` tabs | **High** |
| **Combined Balance Hero Card** | Emerald gradient/card with Combined Balance, active account count, and quick actions (`+ Expense`, `+ Income`, `Transfer`) | Basic balance card with different spacing/typography | Visual & layout mismatch | **High** |
| **Account List & Cards** | Dedicated `Accounts` tab + `Overview` summary cards; shows balance, type, archive status | Basic inline list; no dedicated `Accounts` tab | Missing dedicated tab & archived section | **High** |
| **Add / Edit / Archive Account** | Add Account modal, Rename Account modal, Archive/Unarchive toggle, safe deletion guard | Only `_showAddAccountModal` exists; no Rename, Archive, or Delete guard | Missing Edit, Archive, and Delete guard | **High** |
| **Add / Edit Transaction** | Unified modal for Expense/Income with validation, dual date picker, category filter by type, double-submit guard | Basic `_showAddTransactionModal` | Missing edit mode, dual date display, and validation parity | **High** |
| **Transaction History & Filters** | Dedicated `Transactions` tab with live search, Type chips (`All`/`Expense`/`Income`/`Transfer`), Account filter | Basic recent list; no search bar, type chips, or account filter | Missing search & filter UI | **High** |
| **Transaction Details & Delete** | Tapping a row opens Transaction Details modal with Edit & Delete (with confirmation dialog + undo toast) | Not implemented | Missing Details modal, Delete confirmation, and Undo toast | **High** |
| **Transfer Creation & Details** | Dedicated Transfer modal (Source, Destination, Amount, Date, Note) with same-account guard | Basic or missing transfer UI | Missing full Transfer modal parity | **High** |
| **Category Management** | Dedicated `Categories` tab with Expense/Income sub-tabs, Add, Rename, duplicate check, safe delete guard | Not implemented | Missing entire Category Management UI | **High** |
| **Empty / Error / Loading States** | Dedicated empty states per tab (no accounts, no transactions, no search results) + inline validation errors | Minimal or generic empty states | Missing tailored empty & validation states | **Medium** |

---

## 4. Categorized Differences Summary

1. **Missing Screens & Components**:
   - `Transactions` tab (search, type chips, account filter)
   - `Accounts` tab (active/archived sections, rename, archive, delete guard)
   - `Categories` tab (Expense/Income sub-tabs, add/edit/delete)
   - Transaction Details modal & Delete Confirmation dialog
   - First-Time Finance Setup wizard
2. **Incorrect Screen Structure**:
   - `finance_view.dart` uses a single-page layout instead of the 4-tab structure (`Overview`, `Transactions`, `Accounts`, `Categories`).
3. **Visual Design Differences**:
   - Card corner radii, Emerald (`#1B4D3E`) / Mint (`#E0EFE8`) surface tokens, typography hierarchy, and dual Ethiopian-Gregorian date badges differ between `DaywellFinanceModule.tsx` and `finance_view.dart`.
4. **Interaction Differences**:
   - Tapping a transaction in Preview opens Details → Edit/Delete; Android lacks this flow.
   - Preview has 5-second ephemeral undo toasts and double-submission debouncing.

---

## 5. Prioritized Implementation Plan (For Phase 2 — Awaiting Approval)

1. **P0 — Core Navigation & Overview**: Refactor `finance_view.dart` to use the 4-tab structure (`Overview`, `Transactions`, `Accounts`, `Categories`) and match the Combined Balance Hero Card + Quick Actions.
2. **P0 — Transaction History, Details, Edit & Delete**: Implement the `Transactions` tab (search, type chips, account filter), Transaction Details bottom sheet, Edit flow, and Delete confirmation with Undo snackbar.
3. **P1 — Account & Category Management**: Implement the `Accounts` tab (Add, Rename, Archive/Unarchive, safe delete guard) and `Categories` tab (Expense/Income sub-tabs, Add, Rename, safe delete guard).
4. **P1 — Transfer & Transaction Modal Parity**: Align Add/Edit Transaction and Transfer modals with Preview validation, dual-date display, and double-submit protection.
5. **P2 — First-Time Finance Setup & Empty States**: Add the 2-step Finance onboarding wizard and tailored empty states per tab.
6. **P2 — On-Device Verification**: Build APK via GitHub Actions and verify all 4 tabs and modals on an Android device/emulator.
