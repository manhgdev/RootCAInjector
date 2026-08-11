# RootCAInjector

RootCAInjector makes installed user certificates part of the system certificate store, so that they will automatically be used when building the trust chain. This module makes it unnecessary to add the network_security_config property to an application's manifest.

## Features

- Support for multiple users
- Support for Magisk/KernelSU/KernelSU Next/APatch
- Support for devices with and without mainline/conscrypt updates
- Enhanced Android 17 compatibility with modern namespace handling
- Automatic certificate synchronization
- Install external CAs into both the user and system stores

## Compatibility

Works on any device from Android 7 until Android 17.

Depending on your Android version and Google Play Security Update version, your certificates will be either stored in `/system/etc/security/cacerts` or in `/apex/com.android.conscrypt/cacerts/`. This module handles all scenarios automatically.

## Usage

### Installing Certificates

1. Install the certificate as a user certificate through Android Settings
2. Restart the device
3. The certificate will be automatically injected into the system trust store

### Installing an External CA into Both Stores

After booting once with this version of the module, put a correctly named CA file in `/data/adb/root-ca-injector/certs`. The module detects it within a few seconds and installs a copy into every available Android user trust store (including the legacy keychain store when present) and into the system/Conscrypt trust store.

Android requires the filename to use the old OpenSSL subject hash, such as `9a5ba575.0`. For a PEM CA certificate on a computer with OpenSSL:

```sh
hash=$(openssl x509 -in my-ca.pem -subject_hash_old -noout | head -1)
cp my-ca.pem "$hash.0"
adb push "$hash.0" /sdcard/Download/
adb shell su -c "mkdir -p /data/adb/root-ca-injector/certs && cp /sdcard/Download/$hash.0 /data/adb/root-ca-injector/certs/$hash.0"
```

Only the initial module install/update needs a device reboot. Adding a CA file afterward does not. An app which has already cached a TLS trust manager may still need to be fully restarted.

### Removing Certificates

1. Remove the certificate from the user store through Android Settings
2. Restart the device
3. The certificate will be automatically removed from the system trust store

## License

Modified from NVISOsecurity/AlwaysTrustUserCerts

## Author

manhgdev
