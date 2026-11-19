# Herasat

Android VPN client project (Persian/English, dark UI).

## Current scope
- Android application shell with manual connect/disconnect controls.
- Public VLESS/VMess/Trojan/Shadowsocks subscription/config discovery is planned.
- A real VPN tunnel requires an integrated and tested Xray/sing-box core; the initial scaffold does not claim to establish proxy traffic yet.

## Build
Open this project in Android Studio with JDK 17 and Android SDK 35, or run `./gradlew assembleDebug` after Gradle wrapper files are added.

## Security
Public free proxy configurations are untrusted. Do not use them for sensitive traffic. Herasat must never connect without an explicit user action.
