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
  tax registration number, receipt header/footer, discount and stock rules

Do not describe these placeholder modules as implemented:

- `/inventory`: dedicated movement/adjustment/transfer UI
- `/purchases`: suppliers, purchase receiving, returns
- `/cashbook`: cash sessions and full cashbook UI
- `/reports`: advanced reporting/charts/export
- Backup/restore workflow
- CSV import/export
- Sale void/refund workflow

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
- `/settings` — implemented appearance, business & regional, checkout & receipt
- `/inventory`, `/purchases`, `/cashbook`, `/reports` — placeholders

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

Current schema version: **2**.

The 21 tables are:

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

Version 1 created all tables and the base lookup/history indexes. Version 2 adds
non-destructive indexes for scoped settings, users/store status, category trees,
exact barcode/SKU lookup, held carts, and payment methods.

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
`lib/features/auth/domain/permissions.dart`. Reuse constants rather than typing
permission strings elsewhere. Existing families cover POS, products, customers,
inventory, reports, users, and settings.

When adding a protected action:

1. Add/reuse a permission constant.
2. Add it to appropriate default role sets.
3. Hide or disable UI when unavailable.
4. Enforce it again in the repository/service.
5. Add allowed and denied tests.

## First-run setup

The setup wizard collects business/store identity, address/phone, owner username
and password, currency, timezone, tax behavior, and receipt footer. The service
creates the store, five default roles, all-store Owner user, default settings,
invoice sequence, and setup audit record in one transaction. Normal application
navigation is blocked until setup succeeds.

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
- Underpayment is blocked. Change cannot exceed cash tendered. Credit sale is not
  implemented.

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
- P on the sale-complete dialog — print receipt
- Ctrl+N — confirmed new/clear sale
- Ctrl+B — collapse/expand sidebar; Ctrl+L — lock
- Escape — standard dialog/back behavior

The POS customer label is derived from `cart.customerId`, never kept as
separate widget state. Tracked products cannot be added beyond stock unless
`inventory.allowNegative` is on. An unmatched scan shows a toast; if exactly
one search result is visible, Enter adds it.

The focused search field supports ordinary USB barcode scanners. There is no
global scanner buffer when focus is elsewhere.

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

Receipt PDF generation uses an 80mm thermal roll layout and runs in a background
isolate. It includes store details, invoice/date, cashier/customer, item snapshots,
discount/tax totals, tenders, received amount, and change.

Receipts take `BusinessSettings`: business name, store, optional header, tax
registration number, configured tax label, footer and currency format. The
built-in PDF font is Latin-1 only, so symbols such as ₹ or ৳ print as the ISO
code; bundle a Unicode font before printing native symbols.

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
- Business settings load, permission denial, persistence, audit and fallbacks
- Gate text-input regression (edit/delete/retype on login and setup) and
  legacy theme-preference migration
- 1280×720 Dashboard → POS → Settings → Sales History smoke navigation

Last verified before this handoff:

- `dart format .` — clean
- `flutter analyze` — zero issues
- `flutter test` — 32 tests passed
- Windows release build — passed at the current root

Always repeat format, analyze, tests, and release build after material changes.

## Safe continuation plan

The intended next phases are:

1. Dedicated inventory movement/adjustment/transfer workflows
2. Suppliers and purchase receiving/returns
3. Cash sessions and cashbook
4. Void/refund flows with compensating stock/cash/audit transactions
5. Reports and background export/import
6. Checksum-verified backup/restore with safety snapshots
7. Release packaging, accessibility/profile hardening, then MSIX/signing

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
- Do not split checkout/void/refund/purchase multi-table writes across transactions.
- Do not use raw `double` arithmetic for new financial domain logic.
- Do not block the UI isolate with large PDF/CSV/report/image work.
- Preserve desktop density and verify 1280×720 overflow behavior.
- Dialog text fields: create controllers inside a `StatefulWidget` that disposes
  them; never create or re-sync a controller from `build()`. Key
  `DropdownButtonFormField`s (they read `initialValue` once) when their data
  can be reloaded.
- Do not call a repository future inside `build()` (`FutureBuilder(future:
  _load())`); cache the future and refresh it on real filter changes.
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
