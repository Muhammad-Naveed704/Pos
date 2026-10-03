# StoreFlow POS — Project Context and Engineering Handoff

This file is the source of truth for AI-assisted work on StoreFlow POS. Read it
before changing code. The current project root is:

`G:\Software Engineer\storeflow_pos`

The project was moved from
`G:\Software Engineer\fontwala\apps\storeflow_pos`. Never hardcode either path
in application code. If the project is moved again, run `flutter clean` before a
Windows build so CMake does not reuse its absolute-path cache.

This directory is a standalone Git repository (initialized at the moved root;
the first commit is the pre-overhaul baseline). It has no remote yet. Do not
assume the old parent repository still tracks this copy.

## Product and current delivery

StoreFlow POS is a Windows-first, offline-first Flutter desktop point-of-sale
application. It has no server, cloud account, remote API, telemetry, or required
network dependency. The local SQLite database is the business system of record.

Phase 1 foundation plus Phase 2 identity/master-data and Phase 3 checkout are
implemented. The current usable scope is:

- First-run business/store/owner setup
- Offline login, lock, logout, active-user checks, and store-scoped sessions
- Roles and editable permission mappings
- Store, category, product, customer, and user management
- Store-aware product pricing, discount, availability, and inventory
- Commercial POS cart, held carts, customers, discounts, tax, and split payment
- Atomic checkout with inventory, cash, loyalty, audit, and invoice sequencing
- Sales history, receipt viewing, printing, and PDF saving
- Persistent theme/accessibility settings (presets, Windows accent, custom
  colour, density, text size, radius, motion)
- Database-backed business settings: currency, number format, tax mode/label,
  tax registration number, discount and stock rules
- Receipt designer (58/80 mm thermal, A4/A5 invoice, logo, contact lines,
  policy, toggles), live preview, per-PC printer and direct print
- Bulk CSV import/export for products (auto-creates categories) and customers
- Custom roles, bulk role creation and a roles × permissions matrix
- Inventory: stock list, adjustments with reasons, stock counts, store
  transfers, movement ledger
- Purchases: suppliers, stock receiving (GRN), supplier returns
- Cashbook: drawer sessions, pay-ins/outs, closing count with over/short
- Reports: sales summary, daily, products (profit), categories, cashiers,
  payment methods, purchases, stock valuation; CSV and PDF export
- Offline password recovery key, change own password
- Sale returns/refunds (partial or full, per-line restock choice, cash/card/
  bank/other) and same-day voids, with refund slips
- USB barcode scanner capture on the POS even when search is not focused
- Backup/restore: checksummed `.storeflowbackup` files, verify, guarded
  restore with safety backup and rollback, scheduled backups with retention
- Credit (udhaar) sales: Pay in full / Partial / Credit at checkout, due dates,
  credit limits with audited override, customer ledger, payments with explicit
  oldest-first or manual allocation, payment reversal, due-date changes
- Customer detail screen (overview, invoices, ledger, payments, statement),
  Receivables page and dashboard card, six credit reports

Not implemented yet (do not describe as done):

- Supplier payables/balances (purchases are still paid in full)
- Customer advances/credit notes (overpayment is blocked)
- UI translations (all text is English)

The database already contains supporting tables/permissions for some future
modules. Their presence does not mean their workflows are complete.

## Toolchain and packages

- Flutter 3.47.5 stable / Dart 3.13.x
- State: `flutter_riverpod` 3.x
- Navigation: `go_router` 18.x
- Database: Drift 2.35 + sqlite3 3.6
- Password hashing: `cryptography`
- PDF/printing: `pdf` + `printing`
- Desktop window: `window_manager`
- Preferences: `shared_preferences`
- Logging: `talker_flutter`
- Theming: `flex_color_scheme` **8.x** (pinned; 9.x is built on the separate
  `material_ui` package and its `ThemeData` is a different type)
- Windows accent colour: `dynamic_color` **1.7.x** (pinned for the same reason)
- Motion: `flutter_animate` (always through `.entrance()`/`AppTokens.motion`,
  which honour the user's animation setting)
- Charts: `fl_chart`
- Camera barcode scanning: `camera` + `camera_windows` (preview and stills)
  with `flutter_zxing` (zxing-cpp via FFI; EAN/UPC/Code 128/QR). zxing-cpp is
  compiled with MSVC/CMake on the first Windows build (slow once).
- Date-range calendar: `calendar_date_picker2` (MIT)
- Backups: `archive` (zip container) + `crypto` (SHA-256), both already in the
  lock file as transitive dependencies before they were made direct

UI building blocks live in `lib/core/ui/` (exported by `ui_kit.dart`). Use
`AppSelect` (Material 3 `DropdownMenu`, searchable, follows value changes),
`AppSegmented` (sliding segmented control), `DateRangeButton` (presets +
calendar popover) and `SearchField`. Do not add new `DropdownButtonFormField`
or `SegmentedButton` call sites: the former only reads its initial value,
which caused stale selections after reloads.

Theme rule: any `ButtonStyle.textStyle`, chip `labelStyle` or similar must be
derived from `textTheme` (e.g. `textTheme.labelLarge?.copyWith(...)`). A bare
`TextStyle(fontWeight: ...)` replaces the whole style, drops the font family,
and made buttons ignore the font chosen in Settings.

See `pubspec.yaml` for exact constraints. Do not upgrade packages incidentally
while implementing an unrelated feature.

## Essential commands

Run all commands from the project root:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format .
flutter analyze
flutter test
flutter build windows --release
flutter run -d windows
```

When CMake reports an old directory in `CMakeCache.txt`, run:

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

Do not delete the user's application-support database to solve build problems.
`flutter clean` removes generated project build artifacts, not business data.

## Startup and application composition

Entry flow:

1. `lib/main.dart` calls `bootstrap()`.
2. `lib/app/bootstrap.dart` initializes Flutter, SharedPreferences, AppDatabase,
   Talker, and the Windows window.
3. The app injects these instances through root Riverpod overrides.
4. `StoreFlowApp` owns MaterialApp, GoRouter, themes, and font scaling.
5. `ApplicationGate` checks first-run setup before allowing normal navigation.
6. After setup it requires an active unlocked session; otherwise it shows login.

`ApplicationGate` lives in `MaterialApp.builder`, i.e. above the router's
Navigator. Every screen it renders (setup, login, lock, startup error) must be
wrapped in its own `Navigator` (`_GateNavigator`) so it has an `Overlay`.
Without one, text fields on Windows lost edits ("deleted text comes back") and
dropdowns/dialogs could not open. Locking keeps the workspace mounted
(`Offstage` + `ExcludeFocus`) so an in-progress sale survives lock/unlock.

`databaseProvider`, `sharedPreferencesProvider`, and `talkerProvider` must be
overridden at bootstrap/test boundaries. Do not instantiate unrelated database
connections inside widgets.

The production window starts at 1440×900 and has a minimum of 1100×700. Widget
smoke tests use 1280×720 as the required compact desktop layout.

## Source layout and ownership

```text
lib/app/                         bootstrap, router, root app, setup/auth gate
lib/core/database/               Drift schema, connection, migrations, providers
lib/core/money/                  Money, currency catalogue, MoneyFormatter/parseAmount
lib/core/theme/                  AppTokens extension, flex ThemeData, theme controller
lib/core/ui/                     shared UI kit (PageHeader, StatCard, EmptyState,
                                 StatusPill, KeyHint, Toast, confirm/prompt dialogs)
lib/features/*/domain/           pure rules and value objects
lib/features/*/application/      Riverpod state/controllers
lib/features/*/data/             repositories and transactional services
lib/features/*/presentation/     desktop pages/dialogs/widgets
test/support/                    isolated in-memory database fixture
docs/                            architecture and phased implementation plan
```

Keep business writes out of presentation widgets. Single-entity work belongs in
repositories; multi-table atomic work belongs in services. Every sensitive data
method must repeat its permission check even when its button/route is hidden.

## Routes

- `/dashboard` — implemented, current-store aggregates
- `/pos` — implemented checkout workspace
- `/products` — implemented product/store-stock management
- `/categories` — implemented hierarchical category management
- `/customers` — implemented customer management and purchase summary
- `/history` — implemented sales search/detail/receipt actions
- `/users` — implemented users and role-permission editor
- `/stores` — implemented branch management
- `/settings` — appearance, business & regional, checkout & tax, receipt
  designer, security
- `/inventory` — stock, adjustments, counts, transfers, movement ledger
- `/purchases` — receiving, supplier returns, suppliers
- `/cashbook` — cash sessions, pay-ins/outs, closing count
- `/reports` — sales/profit/payment/purchase/stock reports and customer-account
  reports (balances, credit sales, payments received, outstanding with aging,
  overdue, statement) with export
- `/customers/:id` — customer account: overview, invoices, ledger, payments
- `/receivables` — business-wide balances (`?filter=overdue`)

`ModuleDefinition.planned` still exists for future placeholder modules; a
module with a non-empty `planned` list is routed to `ModulePage`.

Navigation visibility is permission-filtered in `AppShell`, using module metadata
from `features/shell/presentation/module_page.dart`. Route visibility is not a
security boundary; repositories/services remain the enforcement boundary.

## Database

Primary file: `lib/core/database/app_database.dart`

Drift generates `app_database.g.dart`. Never hand-edit the generated file. After
changing tables/DAOs, run build_runner and commit both source and generated output.

Production database location is resolved with `getApplicationSupportDirectory()`:

```text
<Windows application support>/StoreFlow POS/storeflow.sqlite
```

The connection enables:

- Foreign keys
- WAL journal mode
- `synchronous=NORMAL`
- 5-second busy timeout
- Drift/sqlite3 prepared-statement reuse

Current schema version: **5**.

The 26 tables are:

1. `stores`
2. `roles`
3. `users`
4. `categories`
5. `products`
6. `product_stores`
7. `customers`
8. `suppliers`
9. `sales`
10. `sale_items`
11. `payments`
12. `cash_sessions`
13. `cash_transactions`
14. `purchases`
15. `purchase_items`
16. `stock_movements`
17. `audit_logs`
18. `app_settings`
19. `held_carts`
20. `invoice_sequences`
21. `backup_records`
22. `sale_refunds`
23. `sale_refund_items`
24. `customer_payments`
25. `customer_ledger_entries`
26. `payment_allocations`

Version 1 created all tables and the base lookup/history indexes. Version 2 adds
non-destructive indexes for scoped settings, users/store status, category trees,
exact barcode/SKU lookup, held carts, and payment methods. Version 3 adds
`sale_items.unit_cost` (cost snapshot at sale time, backfilled from the current
product cost for older sales) and indexes for stock ledgers, purchases, cash
sessions and sale-item product lookups. Version 4 adds `sale_refunds` and
`sale_refund_items` with their indexes. Version 5 adds `sales.credit_amount`,
`sales.due_date`, `sale_refunds.credit_applied`, `backup_records.kind/note`,
the three customer-account tables, an `opening` ledger row for every customer
with a non-zero opening balance, and indexes on customer/sale/payment/store/
created_at/due_date/status. (The v5 branch only adds `credit_applied` when
upgrading from v4; older databases create `sale_refunds` with it.)

**Dates are stored as unix seconds.** Drift's default DateTime storage is an
INTEGER, so SQL date functions must use the `'unixepoch'` modifier, e.g.
`date(created_at, 'unixepoch', 'localtime')`. Without it SQLite reads the value
as a Julian day and returns NULL (this made the dashboard show zero sales until
it was fixed). Range filters should bind `Variable.withDateTime` instead.

### Migration rules

- Never reset or silently delete an existing database.
- Increment `schemaVersion` for every persistent schema change.
- Add an ordered `onUpgrade` branch for the old version.
- Prefer additive/non-destructive changes.
- Add a migration test that opens old state, seeds data, upgrades, and verifies
  both retained data and the new schema.
- Do not use `deleteTable`, drop business columns, or recreate tables without an
  explicit backup/data-copy strategy.

### Data-model boundaries

- `products` contains global product identity/defaults.
- `product_stores` contains store-specific stock, reorder level, custom price,
  custom discount, and availability.
- Stores/products/categories/customers/users are deactivated rather than deleted.
- The active store cannot be deactivated until the user switches away.
- Every stock quantity edit must create a matching `stock_movements` row in the
  same transaction.
- Transactional rows must retain snapshots such as product name/SKU and cashier.

## Money, quantity, discount, and tax rules

Never hardcode a currency symbol. Display every amount through
`moneyFormatterProvider` (`format(Money)`, `major(double)`), and parse typed
amounts with `MoneyFormatter.parse`, which honours the configured decimal
separator (`1.250` kg must not become 1250). `Money` has two minor digits, so
only two-decimal currencies are offered in `Currencies.all`; adding JPY/KWD-style
currencies requires a Money precision change first.

Application arithmetic uses `Money`, which stores signed integer minor units.
The existing database schema persists monetary values in REAL columns for Phase 1
migration compatibility; convert only at the database boundary. Do not perform
business arithmetic directly on database doubles.

Quantities are represented in cart memory as thousandths (`quantityMilli`), so a
quantity of 1.5 is stored as 1500. Database stock and sale quantities remain REAL.

Supported tax modes:

- `disabled`
- `exclusive`
- `inclusive`

Each product has its own tax rate. Cart calculation order is product/store price,
product default discount, manual line percentage/fixed discount, line tax, then
sale percentage/fixed discount. Totals clamp discounts so a line or sale cannot
be negative. The current sale-level discount is subtracted from the post-line-tax
total; it does not reallocate line tax or line totals. Treat a change to this rule
as an accounting behavior change and update tests, receipts, and stored snapshots.

Business settings are read through `businessSettingsProvider` /
`currentBusinessSettingsProvider` (live stream of global `app_settings` rows) and
written only through `BusinessSettingsRepository.save`, which requires
`settings.manage`, updates changed keys in one transaction and writes a
`settings.updated` audit row. The POS UI enforces the discount cap and override
toggle up front; `CheckoutService` still re-validates.

Settings involved in checkout:

- `tax.mode`
- `inventory.allowNegative` (default false)
- `sales.maxDiscountPercent`
- `sales.allowPriceOverride`

Permission and setting checks are both required for discount/price overrides.

## Customer accounts (credit) and ledger

- `customer_ledger_entries` is append-only. Balance = SUM(debit - credit);
  positive means the customer owes money. There is no stored balance column.
- Every sale with a named customer writes `sale` (debit total) and
  `sale_payment` (credit of what was paid now), so paid sales net to zero.
  Other types: `opening`/`adjustment` (opening-balance edits through
  `CreditLedger.syncOpeningBalance`), `payment`, `payment_reversal`, `refund`,
  `refund_paid`, `void`, `void_paid`.
- `sales.credit_amount` is the immutable amount left on account at checkout.
  Invoice outstanding = credit_amount − posted allocations − refunds'
  `credit_applied` (`saleOutstandingSql`). `sales.payment_status` is
  `paid`/`partial`/`credit` and is re-derived after payments, reversals and
  returns. Invariant: grand_total = (paid − change) + credit_amount.
- Partial/credit checkout needs `credit.create` and a named, active customer
  (walk-in sales must be paid in full). The limit check is
  ledger balance + new credit ≤ credit_limit; a limit of 0 means no credit
  without an override. `credit.override_limit` lets the POS retry after a
  confirmation and writes `credit.limit_override`.
- `CreditService.receivePayment` (`credit.receive_payment`) rejects amounts
  above what is owed (no advances). Allocations are stored explicitly in
  `payment_allocations` (null `sale_id` = opening balance), oldest first by
  default or manual. Cash payments add a `customer_payment` cash transaction
  (counted with pay-ins); reversals add `customer_refund` (an outflow).
- Due status (`DueStatus`): overdue when the due date is before today, due soon
  within 3 days, else current; always shown with text and an icon.
- Customer accounts are business-wide (a customer can buy in one branch and
  pay in another), so balances/receivables are not store-filtered; credit
  reports default to the active store with an "All stores" option.
- Refund rule: a return first reduces the invoice's unpaid balance
  (`credit_applied`); only the rest is paid back (method `credit` when nothing
  is paid out). Cash drawer checks use the paid-out part. Voids are blocked
  once a customer payment was allocated to the sale.

## Backup and restore

- `BackupService` (`lib/features/backup/data/backup_service.dart`): the
  snapshot is `VACUUM INTO` (consistent under WAL while the app writes), the
  copy is integrity-checked, then zipped with `manifest.json` (app/schema
  version, stores, per-entry SHA-256 and size), per-PC preferences (`theme.*`,
  `receipt.*`, `shell.*`) and any existing product image / receipt logo files.
  The written file is re-read and verified before a `verified`
  `backup_records` row is written; failures write a `failed` row only.
  Packing and verification run in isolates via top-level helpers (closures
  must not capture the database).
- Restore (`backup.restore`): inspect → confirm (type RESTORE) → safety backup
  (must succeed) → close DB → move live files to `.rollback-*` → copy → reopen
  through `DatabaseHost.openDatabase` (migrations run) → integrity check. On
  failure the previous files are put back and `RestoreFailedException`
  carries the reopened database. Success replaces the database in
  `DatabaseHost`, which rebuilds the provider scope (everyone signs in again).
- Backups newer than the app's schema/format are rejected. Scheduled backups
  (`backup.*` app settings, `backup.settings`) run from `AppShell` while
  signed in; retention deletes only recorded, StoreFlow-named scheduled
  backups in the configured folder. Safety backups go to
  `<app support>/StoreFlow POS/safety-backups` and also run before CSV imports
  when enabled.

## Authentication and sessions

Passwords use PBKDF2-HMAC-SHA256 with random 128-bit salts, 210,000 iterations,
and constant-time verification. Never persist or log plaintext passwords.

Login normalizes usernames to lowercase, rejects inactive users, verifies the
password, loads role permissions, resolves an allowed active store, and updates
`lastLoginAt`.

The only session-related value persisted in SharedPreferences is the last store
ID. Credentials and authenticated sessions are not persisted; the user logs in on
application restart. This is intentional safe behavior, not a missing auto-login.

Switching stores or logging out invalidates the current cart. Permissions are a
session snapshot; after editing a role, affected users must log in again to load
the updated set.

## Roles and permissions

First-run setup creates Owner, Admin, Manager, Cashier, and Inventory Staff.
Owner receives every permission. Owner permissions cannot be reduced.

Permission constants live only in
`lib/features/auth/domain/permissions.dart`, with human-readable labels in
`PermissionCatalog`. Reuse constants rather than typing permission strings
elsewhere. Families cover POS, products, customers, inventory, purchases,
cashbook, reports, users, settings, credit and backup.

Version 3 added `credit.view`, `credit.create`, `credit.receive_payment`,
`credit.override_limit`, `credit.edit_due_date`, `customer.statement`,
`backup.create`, `backup.restore` and `backup.settings`
(`settings.backup_restore` now only opens the Data & backup tab).

The Owner (built-in role named `Owner`) resolves to `Permissions.all` at
sign-in, so new permissions reach it automatically. When adding permissions,
bump `Permissions.version` and list them in `Permissions.introduced`;
`PermissionUpgrade` (run at sign-in) grants them once to built-in roles whose
default set includes them, without undoing admin edits. `RoleRepository`
blocks granting permissions the editor does not hold, deleting built-in or
in-use roles, and reducing the Owner.

When adding a protected action:

1. Add/reuse a permission constant.
2. Add it to appropriate default role sets.
3. Hide or disable UI when unavailable.
4. Enforce it again in the repository/service.
5. Add allowed and denied tests.

## First-run setup

The setup wizard collects business/store identity, address/phone, owner username
and password, currency, number format, timezone, tax behavior/label, and receipt
footer. The service creates the store, five default roles, all-store Owner user,
default settings, invoice sequence, a one-time account recovery key (only its
PBKDF2 hash is stored) and the setup audit record in one transaction, then
shows the key once. Normal application navigation is blocked until setup
succeeds.

Do not ship seed/demo records in this path. Test fixtures may create isolated data.

## Implemented repositories and services

- `AuthRepository`: authentication and allowed-store resolution
- `FirstRunService`: initial atomic application setup
- `StoreRepository`: store listing/create/edit/deactivation guard
- `CategoryRepository`: hierarchy/search/soft activation
- `ProductRepository`: paginated catalog, exact lookup, CRUD/duplicate, store data
- `CustomerRepository`: CRUD/search and aggregate purchase summary
- `UserRepository`: user CRUD/password changes and role permissions
- `HeldCartRepository`: persistent JSON cart save/restore/remove with revalidation
- `CheckoutService`: complete atomic sale transaction
- `SalesRepository`: store-scoped filtered history and sale details
- `ReceiptService`: background PDF generation, printer output, and save dialog
- `BusinessSettingsRepository`: audited business/receipt settings
- `AccountRecoveryService`: recovery key, password reset, change own password
- `ProductImportService` / `CustomerImportService`: two-phase CSV import
  (prepare → preview → apply in one transaction) and export
- `RoleRepository` (+ `PermissionUpgrade`): custom roles and bulk permissions
- `InventoryService`: stock list, adjustments, counts, transfers, ledger
- `PurchaseService`: suppliers, receiving, supplier returns
- `CashbookService`: drawer sessions, pay-ins/outs, closing count
- `ReportsService`: date-ranged reports returning a uniform `ReportResult`
- `RefundService`: sale returns/refunds, voids, refund history
- `CreditLedger`: low-level ledger/outstanding helpers used inside other
  services' transactions
- `CreditService`: balances, invoices, ledger, payments, allocation, reversal,
  due dates, receivables
- `BackupService`: backup create/verify/inspect/restore, schedule, retention

## POS behavior

The POS page is the highest-priority interaction surface:

- Exact SKU/barcode lookup on Enter uses indexed equality queries.
- Partial name/SKU/barcode search is debounced and capped; category chips filter.
- Only active, store-available products appear.
- Adding the same product increases quantity.
- Quantity supports whole/fractional values, increment/decrement, manual editing.
- Supports fixed/percentage line discount, fixed/percentage sale discount, price
  override, sale notes, selected/walk-in/quick-created customer.
- Held carts are database-persistent, do not change stock, revalidate on restore,
  and require confirmation before deletion.
- Payment methods: cash, card, bank, other; split tenders are supported.
- Underpayment is blocked in Pay in full mode. Change cannot exceed cash
  tendered. Partial/Credit modes (with `credit.create`) need a customer, show
  paid now / remaining / due date (today, 7, 15, 30 days, custom or none).
- Ctrl+Shift+P — receive a customer payment (anywhere in the shell).

Keyboard bindings:

- F2 / Ctrl+F — product search
- F3 — customer selector
- F4 — hold sale
- F6 — sale discount
- F7 — payment
- F8 — exact quick-cash checkout
- F9 — held sales (resuming parks the current cart instead of discarding it)
- F10 / Ctrl+Enter — open/complete payment depending focus
- Enter on an empty search field — open payment
- P on the sale-complete dialog — print receipt; V — preview
- Ctrl+R — return items (scan the receipt barcode or type the invoice)
- Ctrl+N — confirmed new/clear sale
- Ctrl+B — collapse/expand sidebar; Ctrl+L — lock
- Escape — standard dialog/back behavior

The POS customer label is derived from `cart.customerId`, never kept as
separate widget state. Tracked products cannot be added beyond stock unless
`inventory.allowNegative` is on. An unmatched scan shows a toast; if exactly
one search result is visible, Enter adds it.

Camera scanning: the scan icon in the POS search box (and the camera button
on product pickers and the product editor's barcode field) opens
`scanWithCamera`. Windows cameras do not stream frames to Flutter, so the
dialog takes a still every ~120 ms and decodes it with zxing-cpp (~25 ms per
frame), then returns the first code. The product editor can also generate an
in-store EAN-13 (prefix 2x, valid check digit, unique).

USB (keyboard-wedge) barcode scanners work anywhere on the POS page:
`ScannerKeyBuffer` captures keystrokes while the POS page has focus but the
search field does not, delivers Enter-terminated bursts as scans, and moves
slower typing into the search field after 350 ms. It never captures input in
dialogs or on the lock screen. Camera scanning is not supported on Windows.

Cash sales are attached to the cashier's open cash session (if any) inside the
checkout transaction.

## Returns, refunds and voids

`RefundService` is the only write path for returns. Sale statuses are
`completed`, `partially_refunded`, `refunded` and `voided`.

- Refund: `pos.refund`; any number of partial refunds until every unit is
  returned. A line's refund value is its line total share times
  `grand_total / sum(line_total)`, so sale-level discounts are spread; the
  refund that returns everything settles the exact remaining balance. Each
  line chooses whether it goes back to stock (movement type `refund`).
- Void: `pos.void_sale`; only same-day sales with no refunds. Restocks every
  tracked line (movement type `void`) and marks the sale `voided`.
- Cash refunds/voids insert a `cash_refund` cash transaction on the user's open
  drawer session and are blocked when the drawer holds less. Loyalty points are
  reversed as `floor(amount)` (checkout awards `floor(grand_total)`).
- Everything for one refund/void happens in one transaction with an audit row.

Reporting rule: sales count when `sale_status <> 'voided'` (by sale date);
refunds of kind `refund` are subtracted on their own date (value, tax share,
and cost only for restocked units). Voids are not subtracted separately because
the voided sale is already excluded. Use the same rule for any new aggregate.

## Atomic checkout invariant

`CheckoutService.checkout()` is the only supported completed-sale write path.
Before/during its single Drift transaction it:

1. Enforces sale, discount, and override permissions/settings.
2. Validates tender methods, underpayment, and cash-funded change.
3. Revalidates each product's activity, store availability, and current price.
4. Allocates the next store/year invoice number.
5. Inserts sale and immutable sale-item snapshots.
6. Inserts all payment records.
7. Validates and deducts tracked stock.
8. Inserts matching stock movements.
9. Inserts the net cash transaction for cash tender.
10. Updates selected-customer loyalty.
11. Inserts the audit log.
12. Advances the invoice sequence.

For partial/credit sales the same transaction also checks the customer and
credit limit, stores `credit_amount`/`due_date`, writes the customer ledger
rows (every named-customer sale does) and the `credit.sale` /
`credit.limit_override` audit rows.

Any exception must roll back every write. Never move one of these writes outside
the transaction. The `_transactionProbe` constructor seam exists only for rollback
testing.

## Search and performance

- Exact barcode and SKU queries are indexed and should be preferred for scanners.
- Product management pages in batches of 50; POS results are bounded.
- Do not load a 50k–100k catalog into application memory.
- Keep active store/category/status conditions in SQL, not post-filtered in Dart.
- Riverpod providers should expose narrow state; avoid rebuilding the whole shell.
- PDF rendering uses `compute()` and must remain off the UI isolate.
- Product image paths are optional; future image display should be lazy and bounded.

Known scaling caveat: contains-name search uses `LIKE '%term%'`, which can scan at
large scale despite the name index. If profiling proves this slow at 100k records,
introduce an FTS table through a real migration and keep exact barcode/SKU paths
unchanged. Do not silently change contains search to prefix-only behavior.

## Sales and receipts

Sales history is store-scoped and supports date, invoice, customer, cashier,
payment method, and status filters. Actions are view detail, print, and save PDF.

Receipt PDF generation runs in a background isolate and follows the receipt
designer (`ReceiptLayout` inside `BusinessSettings`, keys `receipt.*`). Roll
paper (58/80 mm) has infinite height and must be a single `pw.Page`;
`pw.MultiPage` asserts on infinite height (this broke print and Save PDF).
A4/A5 use `MultiPage` with a tabular invoice. Windows Segoe UI (with Nirmala UI
fallback) is loaded from the Windows fonts folder so Unicode currency symbols
print; without it the ISO code is used. Printer choice and direct printing are
per-PC SharedPreferences, not business settings.

Printing never goes through the `printing` plugin on Windows: the plugin
lists printers, spools the job and rasterises on the window (platform)
thread, so a slow or offline printer showed "Not Responding".
`WindowsPrinting` (`lib/core/printing/windows_printing.dart`) does the same
with dart:ffi (winspool level-4 enumeration, GDI, bundled `pdfium.dll`) on
background isolates, with PDFium calls queued. Without a printer saved for
direct printing the in-app picker (`printer_picker.dart`) asks once, with an
"always print here" option. The plugin remains only as a fallback when
pdfium.dll is missing. `tool/printing_probe.dart` checks the bindings.

Previews use `ReceiptPdfView`, not `PdfPreview`. On Windows, PDF rasterising
runs on the UI thread (~0.3–0.6 s for A4), and `PdfPreview` re-rasterises
whenever its `build` callback changes identity, i.e. on every parent rebuild
when given an inline closure. That froze the receipt designer ("Not
Responding"). `ReceiptPdfView` renders only when its `bytes` future changes
and keeps the previous image visible meanwhile.

## Tests and last verified state

Tests use an in-memory Drift database and `StoreFlowFixture`; no production data is
used. Current coverage includes:

- Schema creation and real v1→v2 data-preserving migration
- Password hashing
- First-run transaction
- Valid/invalid/inactive login
- Allowed and denied repository actions
- Store price, active/available filtering
- Quantity, product/sale discounts, and tax calculations
- Cash/change and split payments
- Successful checkout side effects
- Forced checkout rollback
- Held-cart save/restore/remove without stock mutation
- Money formatting/parsing across number styles and decimal separators
- Receipt PDFs for all paper sizes, scanner buffering, recovery keys
- CSV import (categories, stock movements, validation, permissions)
- Roles, permission escalation guard and permission upgrade
- Inventory adjustments/counts/transfers, purchases, cashbook sessions
- Reports and dashboard figures (unix-epoch date regression), v2→v3 migration
- Refunds (partial/full, discount spreading, restock choice, drawer limit,
  loyalty), voids, refund-aware reports/dashboard, v4 migration
- Business settings load, permission denial, persistence, audit and fallbacks
- Gate text-input regression (edit/delete/retype on login and setup) and
  legacy theme-preference migration
- AppSelect value-follow regression, AppSegmented, date presets, EAN-13
- Cash figures net of change (payment mix and payment-method report)
- Credit: zero-payment and partial sales, unchanged full payment, customer and
  permission required, limit and audited override, oldest-first and manual
  allocation, overpayment blocked, reversal, overdue/receivables, opening
  balance edits, credit reports, rollback of credit checkout and of payments,
  returns reducing the balance first, credit voids
- Backup: create + checksums + metadata, damaged and newer-version files
  rejected, restore with safety backup, failed restore rollback, WAL
  consistency, schedule and retention (user files untouched), v4→v5 migration
- Payment dialog modes (widget)
- 1280×720 Dashboard → POS → Settings → Sales History smoke navigation

Visual QA: `flutter test tool/screens_test.dart --dart-define=SHOTS=<dir>
--dart-define=MODE=light|dark --dart-define=SIZE=1280x720` renders the main
pages (including customer detail/ledger, receive payment, receivables, credit
checkout, receivables report, backup and restore confirmation) as the Windows
platform with real Windows fonts
and saves PNGs. It is not part of the suite (it needs Windows fonts); it may
hang on teardown after writing the images, which is harmless.

Last verified before this handoff:

- `dart format .` — clean
- `flutter analyze` — zero issues
- `flutter test` — 99 tests passed
- Windows release build — passed at the current root

Always repeat format, analyze, tests, and release build after material changes.

## Safe continuation plan

The intended next phases are:

1. Supplier payables (purchases on credit, supplier ledger and payments)
2. UI translations (Urdu/Arabic with RTL)
3. Release packaging, accessibility/profile hardening, then MSIX/signing

Do not begin several phases in one unreviewable change. Build vertical slices with
domain rules, service transaction, repository queries, desktop UI, and tests.

## Non-negotiable engineering rules

- Work only in the current StoreFlow project unless explicitly instructed.
- Preserve user data and existing migrations.
- Do not edit `app_database.g.dart` manually.
- Do not add fake records to production startup.
- Do not bypass repository/service permission checks.
- Do not issue cross-store queries without an explicit reason and test.
- Do not update stock without a stock movement in the same transaction.
- Do not split checkout/void/refund/purchase/customer-payment multi-table writes
  across transactions.
- Never store a customer balance; derive it from `customer_ledger_entries`, and
  write a ledger row in the same transaction as anything that changes what a
  customer owes. Record payment allocations explicitly.
- Never filter "real" sales with `sale_status = 'completed'`; use
  `sale_status <> 'voided'` and subtract refunds (see Returns section).
- Do not use raw `double` arithmetic for new financial domain logic.
- Do not block the UI isolate with large PDF/CSV/report/image work.
- Preserve desktop density and verify 1280×720 overflow behavior.
- Dialog text fields: create controllers inside a `StatefulWidget` that disposes
  them; never create or re-sync a controller from `build()`. Key
  `DropdownButtonFormField`s (they read `initialValue` once) when their data
  can be reloaded.
- Do not call a repository future or create a Drift `watch()` stream inside
  `build()`; use `CachedStreamBuilder(create:, keys:)` or cache it in state
  (a new stream re-runs the query on every rebuild, e.g. each POS cart tap).
- Never block the window thread: no synchronous plugin calls for printing;
  CPU-heavy work (PBKDF2 hashing, PDF, CSV, backups) runs in isolates.
- Order ledgers and lists by `created_at` and then `rowid`; timestamps have
  one-second precision.
- Payments store the amount tendered. Any cash total must subtract
  `sales.change_amount` (change is always paid from cash).
- Preserve unrelated user changes; inspect the working tree before editing.
- Run build_runner after Drift schema changes and all quality gates before handoff.

## Change checklist for future agents

Before coding:

- Read this file, `docs/architecture.md`, and `docs/implementation_plan.md`.
- Inspect the exact repository/service/page and its tests.
- Identify active-store, permission, money, audit, and transaction boundaries.

Before declaring completion:

- Verify empty/loading/error/success UI states and permission visibility.
- Add service-level permission and rollback tests where relevant.
- Add/verify migrations without deleting data.
- Run `dart format .`, `flutter analyze`, `flutter test`, and Windows release build.
- Update this file and implementation plan when architecture or phase status changes.
