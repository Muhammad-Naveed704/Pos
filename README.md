# StoreFlow POS

Offline-first, Windows-first point of sale built with Flutter, Riverpod, GoRouter,
Drift and SQLite.

The current build includes first-run business setup, local authentication and
role permissions, multi-store master data, store-aware products and stock,
customers, a keyboard-friendly POS, persistent held carts, split payments,
atomic checkout, sales history, and printable/PDF receipts.

## Run

```powershell
flutter pub get
dart run build_runner build
flutter run -d windows
```

On a new database, the setup wizard creates the first store and owner account.
Subsequent launches require that local username and password. The selected store
is remembered, but credentials are never persisted and the app never auto-signs
in.

## Verify

```powershell
flutter analyze
flutter test
flutter build windows --release
```

The app creates its local database in the Windows application-support directory.
No business data is sent over the network.

See [architecture](docs/architecture.md) and the
[implementation plan](docs/implementation_plan.md).
