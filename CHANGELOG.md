## v1.2

- Release a ZIP whose module metadata matches `versionCode=12`
- Point update metadata and changelog URLs at the active `main` branch

## v1.1

- Add an external CA inbox at `/data/adb/root-ca-injector/certs`
- Copy external CAs to Android user trust stores and the system/Conscrypt store
- Detect new external CA files while Android is running; no device reboot required
- Preserve hash-colliding certificates instead of overwriting them

## v1

- Initial release of RootCAInjector
- Renamed from Always Trust User Certificates
- Updated author to manhgdev
- Enhanced Android 17 support with modern mount namespace handling
- Improved zygote injection reliability with better PID detection
- Added APatch support
- Updated for latest Magisk/KernelSU module standards
