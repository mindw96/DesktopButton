# Mac App Store screenshots

- `01-grid-ko.jpg`: actual icon-grid view with a temporary example folder.
- `02-list-ko.jpg`: actual list view of the same folder.
- Both images are 1440 × 900 pixels, JPEG, RGB, with no alpha channel.
- Locale: Korean. Captured from the App Store Debug target, version 1.0.0 (7).

The foreground is the real native app, including its actual folder title, file icons, list/grid controls, and resize handle. A separate native backdrop window provides the explanatory text and existing shipping app icon. The screen region was captured directly; app UI was not generated or composited afterward. Only generated example files were shown.

The capture used the existing `--ui-testing` mode and `OneButton.UITests` preferences. Login-item registration was not changed. Test apps, temporary example folders, and the backdrop window were closed or removed afterward.

The settings menu was checked separately for the privacy-policy and support links and the absence of Sparkle controls. Its verification image is not part of the store screenshot set, because UI testing deliberately disables the login setting.
