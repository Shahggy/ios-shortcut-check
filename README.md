# Isolated Apple Shortcuts check

A manual test on a fresh Xcode iPhone 16e simulator. It reports the **actual** iOS runtime; a nearby iOS 27 runtime is not called 27.0.1. If this device or Apple Shortcuts is unavailable the run reports that limitation. It never signs in with an Apple ID, a production app account, or a provider key.

The test opens the public ShagAttack download in Safari. A second copy, verified against its SHA-256, is available through Apple's Files app in On My iPhone → Shortcut Lab. The checks exercise file import, direct launch, Apple's simulated Siri request **after speech recognition**, a disposable placeholder pairing, and a named test alarm when Clock is installed. The public app is opened without signing in. No production tasks or alarms are created. Actual speech recognition, vibration, sound, physical snooze buttons and permissions on a personal iPhone are not verified.

Cloud configuration: one manually dispatched **standard** GitHub-hosted macOS runner, public repository only, owner only, 20-minute timeout. No schedules, paid runner fallback, caches, uploaded artifacts or paid APIs. Test code, run logs, the shortcut's name and its already-public download address will be visible if this test project is published. No app source, personal tasks, real pairing values, account credentials, or phone screenshots are included.

On a Mac with Xcode and Homebrew the same probe can also run locally. It creates and removes only its own simulator. It cannot deliver an update or grant permissions on a separate physical iPhone.
