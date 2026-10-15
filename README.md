# WAKA VPN

WAKA VPN is an Android Flutter client that loads public OpenVPN profiles from the VPN Gate community server directory. The app lets you choose a country and then choose an available server in that country.

## Country and server availability

The country picker includes every distinct country present in the live VPN Gate API response when the list is loaded. The app cannot guarantee servers in every country worldwide: availability depends on the third-party directory, volunteer operators, and current server uptime. Refresh the list if a country or server is temporarily unavailable.

## Privacy and trust

VPN Gate entries are community-operated third-party servers. Their operators may observe your IP address and connection metadata, and may see traffic that is not protected by HTTPS. A VPN does not by itself guarantee anonymity, prevent tracking, or protect you after a tunnel disconnects. Do not use an unfamiliar community server for sensitive activity.

The app retrieves the server directory over HTTPS only. It does not fall back to unencrypted HTTP if the secure endpoint is unavailable.

## Build

The GitHub Actions workflow generates the Android project files, applies the OpenVPN permission callback and native-library packaging settings, runs the Android configuration tests plus `flutter analyze` and Flutter tests, and builds both an APK and an Android App Bundle. The generated APK and AAB are uploaded as workflow artifacts. The artifacts are not configured with a store-release signing key.

To build locally with Flutter installed:

```sh
flutter create --project-name waka_vpn --org com.wakavpn.app --platforms android .
python3 tool/configure_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

The Android project targets API level 24 or later for the OpenVPN plugin. On the first connection, Android displays its system VPN consent dialog; approve it to let the plugin start the tunnel. If permission is cancelled, tap Connect again and approve the prompt.
