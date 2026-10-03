# Releasing StoreFlow POS on the Microsoft Store

StoreFlow POS is a Windows desktop app, so it is published on the
**Microsoft Store** (Google Play Store does not distribute Windows desktop
apps). The project is already configured to build an MSIX package for the
Store.

## What is already set up

| Item | Where | Value |
| --- | --- | --- |
| App icon (window, taskbar, .exe) | `windows/runner/resources/app_icon.ico` | Orange bag logo (regenerate with `dart run tool/generate_icons.dart`) |
| Store/tile logo | `assets/branding/storeflow_icon.png` | 1024 × 1024 PNG |
| Package settings | `pubspec.yaml` → `msix_config` | name, logo, x64, en-us, Store mode |
| App version | `pubspec.yaml` `version: 1.0.0+1`, `msix_version: 1.0.0.0`, `lib/app/app_info.dart` | 1.0.0 |
| Capabilities | `msix_config.capabilities` | `webcam` (+ `runFullTrust`, added automatically) |
| Minimum Windows | generated manifest | Windows 10 1809 (10.0.17763) |
| Privacy policy | `docs/store/PRIVACY_POLICY.md` | publish at a public URL |
| Listing texts | `docs/store/STORE_LISTING.md` | copy into Partner Center |
| Support page / in-app help | `docs/store/SUPPORT.md`, Settings → Help & support | email + phone |
| Terms | `docs/store/TERMS_OF_USE.md` | optional additional terms |
| User guide | `docs/USER_GUIDE.md` | |

### Capabilities (permissions) and why

| Capability | Needed | Reason |
| --- | --- | --- |
| `runFullTrust` | Yes (automatic) | Desktop Flutter app: local SQLite database, Windows print spooler, file save/open dialogs, backups. |
| `webcam` | Yes | Optional camera barcode scanning (POS and product editor). Windows asks the user the first time. |
| `internetClient` | **No** | The app never uses the network. |
| `broadFileSystemAccess` | **No** | Files are only accessed through file pickers the user opens. |
| `documentsLibrary`, `picturesLibrary` | **No** | Full-trust apps can write the backup folder the user chooses. |
| `microphone`, `location`, `bluetooth` | **No** | Not used. |

USB barcode scanners act as keyboards and need no capability. Printing to
any installed printer needs no capability.

## Step-by-step

### 1. Partner Center account (one time)

1. Go to https://partner.microsoft.com/dashboard and sign up as a developer
   with your Microsoft account (individual or company).
2. Fill in the publisher display name (e.g. *XWS*) — this name appears on
   the Store.

### 2. Reserve the app name

Partner Center → **Apps and games** → **New product** → **MSIX or PWA app** →
reserve **StoreFlow POS** (or the closest available name).

### 3. Put the product identity into pubspec.yaml

Partner Center → your app → **Product management → Product identity**.
Copy the three values into `msix_config` in `pubspec.yaml`:

```yaml
msix_config:
  identity_name: <Package/Identity/Name>          # e.g. 12345XWS.StoreFlowPOS
  publisher: <Package/Identity/Publisher>         # e.g. CN=A1B2C3D4-....
  publisher_display_name: <Package/Properties/PublisherDisplayName>
```

The placeholders currently in the file (`XWS.StoreFlowPOS`, `CN=XWS`)
build locally but **will be rejected** by the Store until replaced.

### 4. Build the package

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
dart run msix:create
```

The package is written to
`build\windows\x64\runner\Release\storeflow_pos.msix`. With `store: true` it is
not signed locally; Microsoft signs it during certification.

For every update raise both versions, e.g. `version: 1.0.1+2` and
`msix_version: 1.0.1.0` (the fourth number must stay 0 for the Store), and
`AppInfo.appVersion`.

### 5. Test the package before submitting

To install locally you need a signed test package:

```powershell
dart run msix:create --store false
```

This signs with a test certificate (Windows asks you to trust it) so you can
install the `.msix` by double-clicking. Check: first-run setup, a sale with a
receipt print, camera scanning permission prompt, CSV import, backup and
restore. Optionally run the **Windows App Certification Kit**
(`appcert.exe`, part of the Windows SDK) on the package.

Uninstall the test package before installing the Store version.

### 6. Create the submission

Partner Center → your app → **Start your submission**:

1. **Pricing and availability** — markets, free or paid, release date.
2. **Properties** — category *Business*; privacy policy URL; website and
   support contact (mnaveed2862@gmail.com); system requirements (x64,
   4 GB RAM recommended; camera optional).
3. **Age ratings** — complete the questionnaire (see STORE_LISTING.md);
   expected rating 3+.
4. **Packages** — upload `storeflow_pos.msix`.
5. **Store listings** — English: description, short description,
   features, screenshots (at least 1, ideally 8 at 1920×1080), logo,
   search terms, copyright. Texts are in `STORE_LISTING.md`.
6. **Submission options → Notes for certification** — paste the notes from
   STORE_LISTING.md and the justification for `runFullTrust`
   (restricted capability): *"Desktop Win32 (Flutter) app; uses a local SQLite
   database, the Windows print spooler for receipt printers and user-selected
   files for CSV, PDF and backups. No network access."*
7. **Submit to the Store**. Certification usually takes 1–3 working days.

### 7. Publish the privacy policy

The Store requires a public privacy-policy URL. Easiest options:
GitHub Pages (commit `docs/store/PRIVACY_POLICY.md` to a public repo and
enable Pages) or Google Sites. Use that URL in Properties.

## Data location

The Store (MSIX) version keeps its database inside the package's private
folder (Windows redirects `%APPDATA%`). An existing non-Store installation
does not move automatically: create a backup in the old version and restore
it in the Store version (Settings → Data & backup).

`windows/runner/Runner.rc` keeps `CompanyName` = `com.storeflow` and
`ProductName` = `StoreFlow POS`. They decide the data folder of the
non-Store (exe) build, so never change them.

## Checklist before each submission

- [ ] Version numbers raised (pubspec `version`, `msix_version`,
      `AppInfo.appVersion`)
- [ ] Partner Center identity values in `msix_config`
- [ ] `flutter analyze` clean, `flutter test` passing
- [ ] Test package installed and checked (sale, print, scan, backup)
- [ ] Screenshots current
- [ ] "What's new" text written
