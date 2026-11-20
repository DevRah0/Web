# GameTranslator v1.7.0 — TCL Native HDMI compatibility build

This is a compatibility-only derivative of [Sefflex/GameTranslator v1.7.0](https://gitlab.com/sefflex/GameTranslator/-/releases/v1.7.0), licensed under GNU AGPL-3.0-only (upstream `LICENSE` included).

## Scope: only TV's HDMI video presentation is changed

- Original `tv/webos` user interface and text rendering: **unchanged**.
- Original Android JS platform integration: **unchanged**.
- Original network EventSource, 27-language text handling, subtitle positions, speaker styles, text coverage, demo, background voice audio and discovery: **unchanged**.
- TV Android `MainActivity`: original `TvView` mode retained as fallback.
- New `HdmiOverlayService` draws the existing transparent WebView above the **native TV input**. There is **no HDMI decode, encoding, capture, scaling or HDMI pass-through rerendering**.
- `SYSTEM_ALERT_WINDOW` permission is requested via Android Settings for the transparent overlay. Android TV manufacturer support **is required and has not been verified on this TCL device**.
- Original `applicationId` `com.gametranslator.tv` preserved, so existing Windows companion app ADB launch hooks remain compatible. APK signed with development key if upstream signing secret is unavailable. If a different signature is already installed, uninstall that copy before installing this one; this resets that app's local settings.

## Install / التثبيت

Connect to TCL using ADB:

```powershell
adb connect <TV-IP>:5555
adb uninstall com.gametranslator.tv
adb install GameTranslator-TCL-v1.7.0-HDMI-Fix.apk
adb shell monkey -p com.gametranslator.tv 1
```

Enable **Display over other apps** for GameTranslator when asked. Source/HDMI switching may require pressing the TV remote's **Input/Source** key if the TCL firmware does not recognize the Android passthrough-channel ACTION_VIEW intent. If the OS blocks overlay over its HDMI hardware layer, no ordinary third-party APK can guarantee compatibility.

## Quality / الجودة

The native HDMI route does not modify the incoming PS5 video or audio. **4K/HDR/120 Hz/VRR cannot be guaranteed from a build alone**; actual TCL model/firmware verification is required. The TV's original image-processing and gaming-mode settings remain in effect; game quality is not intentionally lowered.

### Build

```sh
cd GameTranslator-TCL/tv/android
gradle :app:assembleRelease
```

Copyright (C) original GameTranslator contributors; compatibility changes from this project.
See `LICENSE` for GNU AGPL-3.0-only terms. Redistribution of a modified version must preserve notices and provide source.
