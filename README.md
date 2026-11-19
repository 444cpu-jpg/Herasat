# Herasat

Herasat is an Android VPN client with a Persian/English dark interface. It uses the sing-box 1.14 core through the `sing_box` Flutter package.

## Features in this build

- Manual connection only: a tunnel starts only after the user taps a server's connect control.
- Fetch public community server lists from three configurable source endpoints.
- Import a direct proxy link or a subscription URL.
- Parse VLESS, VMess, Trojan, Shadowsocks, Hysteria(2), TUIC, AnyTLS, WireGuard and SOCKS/HTTP share links supported by sing-box.
- Select a server from the discovered list and connect/disconnect using Android VpnService.
- Show tunnel status and live upload/download rates.
- Persian and English interface.

## Build an Android APK

Requirements: Flutter 3.44+ (Dart 3.12+), JDK 17 and Android SDK.

```bash
flutter create --platforms=android --org com.herasat --project-name herasat --no-pub .
# Set android/app minSdk to 24 or higher.
flutter pub get
flutter analyze
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

GitHub Actions runs the same process on pushes to `main` and manual workflow dispatch. Download the `Herasat-Android-APK` artifact from the workflow run. The workflow also runs `flutter analyze` before producing the release APK.

## Important limitations and security

- Community proxy servers are untrusted, may be offline, and can observe traffic metadata. Do not use them for banking, private accounts or sensitive information.
- The app does not promise that any public node will work; availability varies by network and region.
- SSR, XHTTP and mKCP links are not supported by the selected sing-box core.
- The app does not connect automatically at startup and does not silently switch servers.
- The sing_box package and sing-box core are GPL-3.0-or-later; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Review licensing obligations before redistributing binaries.
