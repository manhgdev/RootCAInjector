# RootCAInjector

RootCAInjector makes all installed user certificates part of the system certificate store, so that they will automatically be used when building the trust chain. This module makes it unnecessary to add the network_security_config property to an application's manifest.

## Features

- Support for multiple users
- Support for Magisk/KernelSU/KernelSU Next/APatch
- Support for devices with and without mainline/conscrypt updates
- Enhanced Android 17 compatibility with modern namespace handling
- Automatic certificate synchronization

## Compatibility

Works on any device from Android 7 until Android 17.

Depending on your Android version and Google Play Security Update version, your certificates will be either stored in `/system/etc/security/cacerts` or in `/apex/com.android.conscrypt/cacerts/`. This module handles all scenarios automatically.

## Usage

### Installing Certificates

1. Install the certificate as a user certificate through Android Settings
2. Restart the device
3. The certificate will be automatically injected into the system trust store

### Removing Certificates

1. Remove the certificate from the user store through Android Settings
2. Restart the device
3. The certificate will be automatically removed from the system trust store

## License

Modified from NVISOsecurity/AlwaysTrustUserCerts

## Author

manhgdev
