# Implementation plan

## Audit outcome

- New application: no prior StoreFlow code or data needed migration.
- Toolchain: Flutter 3.47.2 stable, Dart 3.13.2, Windows x64 toolchain ready.
- Existing `fontsora_flutter` changes are unrelated and remain untouched.
- Current package releases were checked against pub.dev on 2026-09-29.
- `sqlite3_flutter_libs` is intentionally omitted: sqlite3 3.x supersedes it.

## Phase plan

1. **Foundation (implemented):** Windows scaffold, dependency injection, router,
   responsive shell, database v1, indexes, theme engine, dashboard foundation,
   POS workspace foundation, password hashing, calculation tests and docs.
2. **Master data and identity (implemented):** first-run owner/store setup,
   authentication, lock/logout, safe store switching, default roles and permission
   mappings,
   repository-level permissions, stores, users, categories, products and customers.
3. **POS checkout (implemented):** exact barcode/SKU scan, debounced store-aware
   lookup, integer-money cart rules, line/sale discounts, price override, notes,
   persistent cart holds, customer selection, split tender, cash change, atomic
   checkout, stock/audit/cash/loyalty side effects, receipt/PDF and reprint.
4. **Inventory and purchasing (implemented):** adjustments, receipts, returns and
   transfers with mandatory movements, suppliers and low-stock workflow.
5. **Customers, cashbook and history (implemented):** loyalty, cash sessions,
   voids, refunds.
6. **Reports and interchange (implemented):** reports, charts, CSV/PDF/print
   export, background CSV mapping/import/export.
7. **Data safety, credit sales and customer ledger (implemented, schema v5):**
   checksummed `.storeflowbackup` archives, verify, guarded restore with safety
   backup and rollback, scheduled backups with retention; partial/credit
   checkout, customer ledger, payments with explicit allocations, due dates,
   credit limits with audited override, receivables dashboard and credit
   reports, credit-aware refunds.
8. **Supplier payables (next):** purchases on credit, supplier ledger and
   payments, reusing the allocation pattern of customer accounts.
9. **Translations:** Urdu/Arabic with RTL.
10. **Release hardening:** complete widget/integration suite, profiling, accessibility,
   icon/privacy disclosures, MSIX metadata and signed Store validation.

## Primary risks

- Invoice sequencing and checkout contention: allocate inside the write transaction.
- Currency precision: application calculations now use integer minor units; a
  future schema migration can replace the legacy REAL persistence columns.
- Large imports/reports: never parse or render large payloads on the UI isolate.
- Backup consistency under WAL: use SQLite backup/checkpoint semantics, not a blind
  copy of only the main database file.
- Store scope leakage: require an explicit active-store context in repositories.
- Permissions enforced only in UI: services must perform the same authorization.
- Thermal printer variability: isolate printer adapters and preserve PDF fallback.
