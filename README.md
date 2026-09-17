# GeoFence

Flutter app for geofencing and IoT monitoring.

## Debug on a physical Android phone

### 1. Phone setup

1. On the phone: **Settings → About phone** → tap **Build number** 7 times to enable Developer options.
2. **Settings → Developer options** → turn on **USB debugging**.
3. Connect the phone with a USB data cable (not charge-only).
4. When prompted on the phone, tap **Allow USB debugging** for this computer.

### 2. Verify the device

In a terminal at the project root:

```powershell
flutter devices
```

Your phone should appear (for example `SM G991B` with an id like `R58N...`). If it does not:

- Try another USB port or cable.
- Install your phone manufacturer’s USB driver (Samsung, Google, etc.).
- Run: `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices`

### 3. Run from Cursor

1. Install the **Flutter** and **Dart** extensions (Cursor will suggest them from `.vscode/extensions.json`).
2. Open **Run and Debug** (Ctrl+Shift+D).
3. Choose **Full (Android)** or **Reporting (Chrome)** and press **F5**.

If both an emulator and a phone are connected, pick the phone in the status bar device selector, or run:

```powershell
flutter run -d <device-id>
```

### 4. Local config

Copy `android/local.properties.example` to `android/local.properties` and set `MAP_API_KEY` (required for Google Maps). `google-services.json` must exist at `android/app/google-services.json` for Firebase.

## Flavors (same codebase)

One project, two product modes via `--dart-define=APP_FLAVOR=...`:

| Flavor | Define | Typical target | Features |
|--------|--------|----------------|----------|
| **Full** | `APP_FLAVOR=full` | Android / iOS | Track, GeoFence, Base Stations, IoT Devices + reports |
| **Reporting** | `APP_FLAVOR=reporting` | **Web**, Windows | IoT Data, Wages, Tracking History, Operators, Settings |

If `APP_FLAVOR` is omitted: **web defaults to reporting**, mobile/desktop default to **full**.

### Web app (reporting)

```powershell
# Run in Chrome (reporting flavor is automatic on web)
flutter run -d chrome --web-port=50000 --web-browser-flag="--user-data-dir=$PWD/.chrome-debug-profile"

# Or explicitly:
flutter run -d chrome --dart-define=APP_FLAVOR=reporting --web-port=50000 --web-browser-flag="--user-data-dir=$PWD/.chrome-debug-profile"

# Production build → output in build/web
flutter build web --release --dart-define=APP_FLAVOR=reporting --no-wasm-dry-run

# Deploy to Firebase Hosting (project limitless-iot-17e8f)
firebase use limitless-iot-17e8f
firebase deploy --only hosting
```

Live site: https://limitless-iot-17e8f.web.app

### Custom domain (e.g. trinityglobal.co.za)

Firebase Hosting custom domains are set in the Console (DNS must be edited at your registrar):

1. Open [Firebase Hosting](https://console.firebase.google.com/project/limitless-iot-17e8f/hosting/sites) → **Add custom domain**.
2. Enter `trinityglobal.co.za` (optionally also add `www.trinityglobal.co.za`).
3. Add the **TXT** record Firebase shows (domain ownership).
4. After Verify succeeds, add the **A** (and any **AAAA**) records Firebase shows — use exactly those IPs from the console.
5. Wait for status **Connected** (SSL is automatic; can take minutes to 24h).
6. Firebase Console → **Authentication → Settings → Authorized domains** → add:
   - `trinityglobal.co.za`
   - `www.trinityglobal.co.za` (if used)

If DNS is on Cloudflare, set records to **DNS only** (grey cloud) until Firebase shows Connected, then you can re-enable proxy if desired.

In Cursor: **Run and Debug** → **Reporting (Chrome)** → F5.

**Stay logged in while debugging:** Flutter’s default Chrome session is temporary, so auth was wiped on every run. The launch config uses a fixed port (`50000`) and a persistent browser profile (`.chrome-debug-profile`). A hosted production build keeps login across refreshes via Firebase `Persistence.LOCAL`.

**Images on web:** Flutter’s CanvasKit renderer can’t read Firebase Storage / Google photo bytes without CORS. The app uses HTML `<img>` avatars on web so user/operator photos display. Optionally harden the bucket with `cors.json`:

```powershell
# Requires Google Cloud SDK (gsutil). Bucket from firebase_options.dart:
gsutil cors set cors.json gs://limitless-iot-17e8f.firebasestorage.app
```

**MQTT on web:** Browsers cannot use TCP port 1883. The base Mosquitto config exposes WebSockets on **9001**; the Flutter app uses `MqttBrowserClient` on web and `MqttServerClient` on Android. On each Pi, re-apply broker config:

```bash
cd ~/GeoFenceBase   # or your clone path
python3 MqttCredentials.py --setup
sudo ufw allow from 192.168.0.0/16 to any port 9001
```

For Google Sign-In in production, add your hosting domain under Firebase Console → Authentication → Settings → Authorized domains.
### Mobile / Windows

```powershell
flutter run --dart-define=APP_FLAVOR=full
flutter run -d windows --dart-define=APP_FLAVOR=reporting
flutter build apk --dart-define=APP_FLAVOR=full
flutter build windows --dart-define=APP_FLAVOR=reporting
```

Feature flags live in `lib/app_flavor.dart` (`AppConfig`).

## Getting Started

- [Flutter documentation](https://docs.flutter.dev/)
