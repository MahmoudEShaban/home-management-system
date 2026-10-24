# Home Management System (نظام إدارة العقارات)

Flutter app for landlords and building managers, for Android and iOS.

- **Properties and units**: buildings, apartments, shops, offices, with live occupancy.
- **Tenants and leases**: rent amount, due day, lease dates and deposit. Ending a lease frees the unit.
- **Rent collection**: a monthly rent roll showing paid, partial, unpaid and overdue tenants. Partial payments are supported.
- **Utility and building expenses**: electricity, water, gas, maintenance and more, logged per building or per unit. An expense can be recharged to the unit's tenant.
- **Invoices**: numbered invoices that auto-fill rent and rechargeable utilities. They export as an A4 PDF in English or Arabic, ready to share or print.
- **Dashboard**: collected vs expected, outstanding, expenses, net, occupancy, and an overdue list.
- **Cloud sync**: Firebase Auth (Google or email) and Firestore. Works offline and syncs when online.
- **Automated backups**: JSON snapshots to a "Home Management Backups" folder in Google Drive, daily or weekly, with one-tap restore. The 30 newest are kept.
- **Arabic + English** with full right-to-left layout and a language switch.

---

## 1. Prerequisites

- Flutter **3.35 or newer** (`flutter --version`; run `flutter upgrade` if older).
- Android Studio with the Android SDK, for Android builds.
- A Mac with Xcode 16+ and CocoaPods, for iOS builds.
- A Google account for Firebase.

## 2. Generate the platform folders

This project contains only the Dart code, assets and config. Create the Android/iOS folders once:

```bash
cd homemanagement
flutter create . --platforms=android,ios --org com.mahmoudessam --project-name homemanagement
flutter pub get
```

`flutter create .` will not overwrite the existing `lib/`, `test/` or `pubspec.yaml`.

## 3. Firebase setup

1. Go to <https://console.firebase.google.com> → **Add project**.
2. **Build → Authentication → Sign-in method**: enable **Email/Password** and **Google**.
3. **Build → Firestore Database → Create database** (production mode). Then open the **Rules** tab, paste the contents of `firestore.rules`, and click **Publish**.
4. Connect the app (this replaces `lib/firebase_options.dart` and adds the platform config files):

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure        # choose your project, tick android + ios
   ```

## 4. Android settings

1. In `android/app/build.gradle(.kts)`, set `minSdk = 23` inside `defaultConfig`.
2. Register your signing keys so Google Sign-In works:

   ```bash
   cd android && ./gradlew signingReport     # Windows: gradlew signingReport
   ```

   Copy the **SHA-1** and **SHA-256** of the `debug` variant (and later your release key). Add them in Firebase → Project settings → Your Android app → **Add fingerprint**. Then run `flutterfire configure` again.

## 5. iOS settings (on a Mac)

1. In `ios/Podfile`, uncomment and set: `platform :ios, '15.0'`.
2. Open `ios/Runner/GoogleService-Info.plist` and copy the value of `REVERSED_CLIENT_ID`.
3. Add it as a URL scheme in `ios/Runner/Info.plist`:

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>com.googleusercontent.apps.YOUR-REVERSED-CLIENT-ID</string>
       </array>
     </dict>
   </array>
   ```

4. Run `cd ios && pod install`.

## 6. Google Drive backups

Backups use the narrow `drive.file` scope, so the app can only see files it created.

1. Open <https://console.cloud.google.com>, select the **same project** Firebase created.
2. **APIs & Services → Library** → enable **Google Drive API**.
3. **APIs & Services → OAuth consent screen**: fill in the app name and support email, and add your Google account as a **test user** while the app is in testing.
   `drive.file` is a non-sensitive scope, so Google verification is light when you publish.

## 7. Run and test

```bash
flutter test          # rent and summary logic
flutter run           # with a phone or emulator connected
```

Release builds:

```bash
flutter build appbundle      # Android → upload to Google Play
flutter build ipa            # iOS → upload with Xcode / Transporter
```

---

## How it works

| Area | Where |
| --- | --- |
| Data models | `lib/data/models.dart` |
| Rent roll, overdue logic, monthly summary | `lib/data/rent_logic.dart` (unit-tested) |
| Firestore access, backup export/import | `lib/data/repository.dart` |
| Drive backup and restore, auto-backup scheduling | `lib/data/backup_service.dart` |
| Riverpod providers | `lib/data/providers.dart` |
| English/Arabic strings | `lib/l10n/strings.dart` |
| Screens | `lib/ui/` |
| Invoice PDF | `lib/ui/invoice_pdf.dart` (bundled Cairo font, so Arabic works offline) |

**Data layout.** Everything lives under `users/{uid}/` in Firestore: `properties`, `units`, `tenants`, `payments`, `expenses`, `invoices`. The business profile (invoice header, currency, invoice prefix) is on the `users/{uid}` document. Dates are stored as epoch milliseconds, so every document is plain JSON.

**Rent status.** A tenant is billed for a month when their lease overlaps it and the lease is active.
- **Paid**: payments for that month cover the rent.
- **Partial**: some was paid and the due day has not passed.
- **Unpaid**: nothing was paid and the due day has not passed.
- **Overdue**: the due day has passed without full payment.

**Automatic backups** run when the app opens or returns to the foreground and the last backup is older than the chosen interval. iOS does not allow reliable timed background jobs, so this approach works the same on both platforms.

**Invoices.** Picking a tenant and month adds the rent line and any expenses marked "recharge to tenant" for that unit and month. Marking an invoice paid can also record the rent line as a payment.

## Possible next steps

- Several managers sharing one portfolio (organisation documents + roles).
- Rent reminders by push notification or WhatsApp.
- Excel export of the rent roll and expenses.
- Meter readings with per-unit utility splitting.
