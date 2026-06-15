# AGENTS.md — HalalExpress Reference

## Goal
Rebuild the existing KampungRider delivery app (currently in production) using Flutter. The new app is named **HalalExpress**.

## Key Architecture Decisions
- **State management**: `setState` only, no Provider/Bloc/Riverpod
- **Routing**: `Navigator.push` directly, no named routing
- **Animations`: `AnimationController` + `FadeTransition` / `SlideTransition`
- **Backend**: Firebase Auth + Firebase Firestore
- **Location**: `geolocator` + `geocoding`
- **Notifications**: `firebase_messaging` + `flutter_local_notifications`
- **Payments**: `billplz` (manual redirect URL-based)
- **Audio**: `audioplayers` for notification sounds
- **Date**: `intl`
- **Images**: `image_picker` + `firebase_storage`
- **Map**: `url_launcher` (open Google Maps)
- **Onboarding**: `shared_preferences`
- **Currency formatting**: custom intl-based helper
- **Platform**: Android + iOS (Windows/web/macOS/linux are known but not actively targeted; macos and linux config files were updated for rename)

## Project Structure
```
halalexpress/
├── lib/
│   ├── main.dart                    # App entry + FCM setup + notifications
│   ├── splash_screen.dart           # Animated splash → onboarding or login
│   ├── onboarding_screen.dart       # 3-page swipe onboarding (no status bar)
│   ├── login_screen.dart            # Email/password login
│   ├── register_screen.dart         # Registration with role selection (customer/rider) + rider doc uploads
│   ├── home_screen.dart             # Customer main screen w/ bottom nav
│   ├── order_screen.dart            # Create order form
│   ├── order_detail_screen.dart     # Order detail + live rider tracking
│   ├── my_orders_screen.dart        # Customer's order history
│   ├── profile_screen.dart          # Customer profile
│   ├── rider_main_nav.dart          # Rider main screen w/ limited bottom nav
│   ├── rider_home_screen.dart       # Rider order list page
│   ├── rider_order_detail_screen.dart # Rider view of a single order
│   ├── rider_history_screen.dart    # Rider completed order history
│   ├── rider_profile_screen.dart    # Rider profile
│   ├── admin_screen.dart            # Admin dashboard
│   ├── admin_login_screen.dart      # Admin login screen
│   ├── admin_rider_verify_screen.dart # Admin verify rider documents
│   ├── currency_helper.dart         # Currency formatting (RM)
│   └── bunny_icon.dart              # Custom BunnyIcon painter (replaces bunny.jpg)
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml      # App name "BunnyFresh"
│       └── res/values/strings.xml   # App name "BunnyFresh"
├── ios/Runner/
│   └── Info.plist                   # Display name "BunnyFresh"
├── assets/                          # Sounds, fonts
│   ├── notification.mp3
│   └── accepted_job.mp3
└── pubspec.yaml                     # Dependencies
```

## Features Implemented (in order)

### 1. Splash Screen (splash_screen.dart)
- Animated logo with scale + rotation + fade
- Fades into onboarding (first launch) or login screen
- Removed "system ok" status text

### 2. Onboarding Screen (onboarding_screen.dart)
- Three swipeable pages (Konon, Hantar, Rapi)
- Dots indicator, Skip & Next buttons
- No visible status bar

### 3. Login Screen (login_screen.dart)
- Animated email/password login with teal gradient
- "Daftar Akaun Baru" → Register screen
- "Log Masuk Admin" → admin login

### 4. Registration (register_screen.dart)
- Full form with name, account name, email, WhatsApp, password, address
- Location auto-detect with geocoding
- Role selection: Pelanggan (Customer) or Rider
- Rider-specific document uploads (selfie, license front/back, roadtax, motorcycle, insurance)
- Documents uploaded to Firebase Storage
- Rider data saved to Firestore `riders` collection with `verified: false`
- Customer data saved to Firestore `users` collection
- Back button → login screen

### 5. Customer Features
- **Home (home_screen.dart)**: 4-tab bottom nav (Home, Orders, Profile, Logout)
- **Create Order (order_screen.dart)**: Pickup/delivery locations, item details, fare input → Firestore with status "menunggu"
- **My Orders (my_orders_screen.dart)**: List of user's orders grouped by status
- **Order Detail (order_detail_screen.dart)**: Live tracking with rider info, status updates, delete (admin), edit/cancel (customer, if pending)
- **Profile (profile_screen.dart)**: Edit profile fields, save to Firestore

### 6. Rider Features
- **Rider Main Nav (rider_main_nav.dart)**: 3-tab bottom nav (Orders, History, Profile) — no order creation
- **Rider Home (rider_home_screen.dart)**: Lists available orders; accept order → updates riderId + status "dijemput" + plays accepted_job.mp3
- **Rider Order Detail (rider_order_detail_screen.dart)**: View order details, update status (ambil barang → dalam penghantaran → selesai)
- **Rider History (rider_history_screen.dart)**: Past completed orders
- **Rider Profile (rider_profile_screen.dart)**: Edit rider profile

### 7. Admin Features
- **Admin Login (admin_login_screen.dart)**: Hardcoded admin email/password check
- **Admin Dashboard (admin_screen.dart)**: Overview with order count, total earnings, user/rider counts
- **Admin Rider Verify (admin_rider_verify_screen.dart)**: List unverified riders, view uploaded docs, approve/reject

### 8. Sound Effects
- `notification.mp3` — played on new order notification
- `accepted_job.mp3` — played when rider accepts an order

### 9. Order Lifecycle
- Customer creates → status "menunggu" (waiting)
- Rider accepts → status "dijemput" (picked up), riderId + riderName set
- Rider starts delivery → "ambil barang" → "dalam penghantaran"
- Rider completes → "selesai" (completed)
- Customer can edit/cancel while status is "menunggu"
- Admin can delete any order
- Rider name is fetched from `full_name` field in `riders` Firestore collection
- Rider name displayed in amber/gold color in customer order detail

### 10. UI Components
- BunnyIcon: Custom `CustomPainter` widget drawing a bunny silhouette (replaces bunny.jpg asset, transparent background that blends with any gradient/bg color)
- Teal-green gradient throughout (#0D7377 → #14C38E)
- Poppins font via GoogleFonts
- Curved edges, glassmorphism effects

## Important Notes
- Ride time/price calculation uses static methods in `currency_helper.dart`
- Payment integration ready (Billplz) but not fully wired—only captures payment screenshot
- Customer notification when rider accepts: via FCM + local notification with `accepted_job.mp3`
- There is a `lib/currency_helper.dart` for formatting
- The old splash screen initially showed a bunny.jpg in center; replaced with BunnyIcon custom painter
- The native splash screen icon was removed (just teal color)
- `app_icon.png` used for launcher icon
- iOS/macOS bundle IDs use `com.halalexpress.app`
- Firebase notification sound files must be in `android/app/src/main/res/raw/`

### 11. Income History Management
- **History Screen (`history_order_screen.dart`)**: Real-time income tracking per rider/admin
- **Reset Pendapatan**: Trash icon button deletes all completed orders (confirmation dialog)
- **Export Excel**: Download icon generates `.xlsx` file via `excel` package with columns: Kedai, Tarikh Siap, Jarak (km), Pendapatan (RM), Rider
- Pendapatan Hari Ini resets daily (filters by today's date); Jumlah Pendapatan is cumulative
- Revenue uses `data["fare"]` with fallback to `data["total"]` for backward compatibility
- Dependencies: `excel: ^4.0.6`, `share_plus: ^10.1.4`, `path_provider: ^2.1.5`
- compileSdk/targetSdk upgraded to 36 (patched `flutter_native_splash` cache to compileSdk 34)

### 12. Quick-Login (login_screen.dart) — TEMPORARY, REMOVE BEFORE PRODUCTION
- **3 tickboxes** labeled "LOGIN CEPAT (alfagroup)" above the account name field:
  1. Pelanggan → `abu200` / `Abu!23`
  2. Rider → `mamat300` / `Mamat!23`
  3. Admin → `zainal200` / `Zainal!23` (bypasses 2FA, goes straight to AdminMainNav)
- Ticking a box auto-fills account name + password; untick to go back to manual login
- Admin quick-login bypasses the "Admin only via Log Masuk Admin" block
- Firebase Auth accounts created with emails: `abu200@halalexpress.com`, `mamat300@halalexpress.com`, `wukongfantastic5@gmail.com`
- Rider doc `mamat300` has `rider_verified: true`
- **To remove**: delete the `_quickRole` state, the `_quickCheckbox` method, the checkbox UI block, and the `_quickRole != 2` condition in the admin block check

### 13. Rider Commission (80/20 split)
- **Order list card** (`admin_screen.dart`): Rider sees `fare * 0.8` instead of full fare; label changes to `"Pendapatan Saya"` (single) or `"Jumlah Pendapatan"` (batch)
- **Batch offer popup** (`_BatchOfferDialog`): Shows only total 80% sum at bottom, no individual fare per order
- **History screen** (`history_order_screen.dart`): Already uses `_riderShare(fare * 0.8)` for revenue, order cards, and Excel export
- **Admin view**: Unchanged — still shows full fare
- Batch total computed by summing `fare` of all orders sharing the same `batch_id`, then × 0.8
- Helper: `_riderFareText()` at `admin_screen.dart:1782`

### 14. OSRM Route Optimization
- **`_openBatchRoute()`** (`admin_screen.dart:1655`): Uses OSRM Trip API to find optimal stop order from rider's current location
  - Calls `https://router.project-osrm.org/trip/v1/driving/{coords}?source=first&roundtrip=false`
  - Reorders stops based on `waypoint_index` in response (nearest-next optimization)
  - Falls back to pickups-first group sort if OSRM fails/times out
  - Opens Google Maps with optimized waypoints
- **Dependency**: `http: ^1.6.0` already present; `geolocator` for current location

### 15. Rating System
- **Trigger**: When rider completes delivery (`completeDelivery` in `admin_screen.dart`), sets `pending_rating: true` on the order
- **Customer prompt**: In `customer_history_screen.dart`, a "BARU" badge appears and tapping a star opens a dialog with 1-5 stars + optional comment
- **Storage**: Rating saved to `ratings` collection (order_id, rider_uid, customer_uid, rating, comment, created_at) + `rider_rating` field on order document; `pending_rating` cleared after submit
- **Rider profile**: `rider_profile_screen.dart` shows average rating (stars + count) from `ratings` collection
- **Admin view**: New "Rating Rider" tab in `admin_rider_verify_screen.dart` — lists all riders with average rating, count, ranking (#1/2/3 gold/silver/bronze), search by name, sort by rating/count/name; tap rider card shows detailed breakdown of each rating + comment

### 16. Language Toggle (BM / English)
- **System**: `lib/translations.dart` — `AppTranslations` class with `ValueNotifier<string>` for reactive language switching
- **Storage**: Language preference saved to `SharedPreferences` key `app_lang`
- **Toggle**: BM/EN text buttons in app bar of both `user_main_nav.dart` and `rider_main_nav.dart`
- **Scope**: All ~27 screens now use `AppTranslations.get()` for display strings (status labels, buttons, nav tabs, dialog text, form labels, etc.)
- **Initialization**: `AppTranslations.init()` called in `main.dart` before `runApp`

### 17. Debug Quick-Order (order_screen.dart)
- **3 preset checkboxes** always visible under "Cari lokasi penghantaran" field:
  1. Petronas Taman Amaniah — Nasi → Jalan 1/4 Taman Amaniah
  2. Masjid Taman Amaniah — Roti → Jalan 1/2 Taman Amaniah
  3. 7-Eleven Taman Amaniah — Air minum → Jalan 1/6 Taman Amaniah
- Check any box → Submit button routes to `_submitDebugOrders()` — geocodes each via Nominatim + OSRM, creates Firestore orders directly
- Success dialog with count; auto-unchecks after submit
- No toggle — always visible when logged in as customer

### 18. APK Install (force_update_screen.dart)
- **Method**: Custom MethodChannel `com.halalexpress/install_apk` → native Kotlin `Intent.ACTION_INSTALL_PACKAGE`
- **FileProvider**: `content://` URI via `FileProvider.getUriForFile()` (solves Android 7+ FileUriExposedException)
- **Permission**: `com.halalexpress/install_permission` channel checks/requests `MANAGE_UNKNOWN_APP_SOURCES`
- **File path**: Downloads to `getTemporaryDirectory()` → `${appName}_${version}.apk`
- **file_paths.xml**: `<cache-path name="cache" path="." />` covers temporary directory
- **Dependency**: `open_file` removed; replaced entirely by native channel
- **Note**: MIUI/HyperOS security scanner runs at system level; `ACTION_INSTALL_PACKAGE` is the most direct path
