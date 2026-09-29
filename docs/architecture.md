# StoreFlow POS architecture

## Product boundary

StoreFlow POS is an offline-first Windows desktop application. Version 1 has no
cloud account, remote API, telemetry, advertising, or mandatory network path.
Business data lives in the user's application-support directory in
`StoreFlow POS/storeflow.sqlite`; SQLite write-ahead logging, foreign keys and a
five-second busy timeout are enabled on every connection.

## Layers

- `app/`: process bootstrap, dependency overrides, routing and app root.
- `core/database/`: Drift schema, migrations, connection policy and providers.
- `core/theme/`: persisted user presentation preferences and centralized tokens.
- `features/<feature>/domain`: pure rules and value objects.
- `features/<feature>/data`: repositories and transactional services.
- `features/<feature>/presentation`: pages, controllers and focused widgets.

UI code never writes raw tables directly. Feature repositories own queries and
permission checks; services own multi-table transactions such as checkout, stock
transfer and restore. The dashboard uses active-store-scoped read-only aggregates.

## Database migration policy

Schema version 1 created the complete table set and base indexes. Version 2 adds
scoped settings, account/store, hierarchy, exact barcode/SKU, held-cart and payment
lookup indexes without rebuilding business tables. Upgrade tests open a version 1
database, retain seeded data and verify the new indexes. Downgrade is unsupported.
Stock quantities may change only in the same transaction that inserts a
`stock_movements` record.

## Transaction boundaries

Checkout is one database transaction: allocate invoice number, insert sale and
items, insert payments, decrement per-store stock, append stock movements, append
cash entry when applicable, and append audit log. Any error rolls back everything.
Purchases and transfers use the same invariant.

## Performance policy

- SQLite WAL and prepared-statement caching through Drift/sqlite3.
- Indexed SKU/barcode uniqueness, product name/category/status, per-store stock,
  sales filter dimensions, customer search, cash history and audit lookups.
- Product search is limited and will be paginated for management lists.
- CSV parsing/validation and report rendering move to isolates before large-data
  workflows ship.
- Riverpod providers expose narrow projections to avoid broad widget rebuilds.
- Currency calculations use integer minor units in application logic and convert
  at the legacy REAL database boundary; pricing and tax rules have pure unit tests.

## Security and data safety

Passwords use PBKDF2-HMAC-SHA256 with a random 128-bit salt, 210,000 iterations,
and constant-time comparison. Login rejects inactive accounts; every protected
repository/service repeats authorization checks and store scope is resolved from
the active session. Only the last selected store is persisted. Master data uses
inactive flags rather than physical deletion and audit records are append-only at
the application layer. Restore will verify a checksum and create a safety backup
before replacing the live database.
