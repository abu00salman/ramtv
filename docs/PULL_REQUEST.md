# Improve IPTV recovery, Android TV remote navigation and optional Xtream EPG

Rapid channel changes could leave old reconnect timers active and overlap
native opens. Source refreshes could publish stale results or remove a usable
catalogue when a provider temporarily failed. This change serializes playback
mutations, invalidates superseded work, closes superseded refresh clients and
keeps the last usable provider catalogue.

Android TV now uses native device-mode detection, including lower-resolution
TVs, and supports explicit Select activation, first-Back control dismissal and
modal focus ownership. Xtream short EPG displays the current programme and
guide with a bounded provider-scoped cache. M3U/Xtream parsing work runs off the
UI isolate. The local source portal has bounded requests, stronger PINs and
lifecycle cleanup.

Existing identity, assets, package ID, signing script, native iPhone source,
desktop build jobs, audio/subtitle selection and resume features are retained.
media_kit remains the engine; no device measurements justify replacing it.

Validation: Flutter 3.47.7 analyze passed; 21 Flutter tests and the Python
Android patch regression test passed; platform shell syntax and diff checks
passed; Android ARM64/ARM32/x86_64 release APK builds passed. APK metadata and
signature verification passed. APKs use a local test signing certificate.

Keep this PR in draft: no physical TV, licensed-provider playback, Windows,
macOS or iPhone runtime/build tests ran locally. Full encrypted storage migration
remains a priority, along with XMLTV and device-based engine/buffer profiling.
See docs/ANDROID_TV_ENGINEERING.md for reference analysis, file details and
limits. Do not merge until cross-platform CI and device review complete.
