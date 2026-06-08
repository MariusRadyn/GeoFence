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
3. Choose **GeoFence (Android)** and press **F5**.

If both an emulator and a phone are connected, pick the phone in the status bar device selector, or run:

```powershell
flutter run -d <device-id>
```

### 4. Local config

Copy `android/local.properties.example` to `android/local.properties` and set `MAP_API_KEY` (required for Google Maps). `google-services.json` must exist at `android/app/google-services.json` for Firebase.

## Getting Started

- [Flutter documentation](https://docs.flutter.dev/)
