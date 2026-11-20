# GameTranslator iOS — OpenRouter translation enhancement

Source basis: the existing, unofficial GameTranslator iOS app at
https://github.com/SimonPetrus/GameTranslator-iOS/tree/ios-app
pinned to commit `2ebef08cbbbee531f752aaa443b39d368954823f`.
This directory includes **modified source files only**, not a new iOS application.

License: GNU AGPL-3.0-only. The original author's copyright and license
headers remain intact. Build fetches the complete upstream source.

## What changed
- Added **OpenRouter · Hy-MT2** as an additional optional translation engine
  in the existing iPhone Settings screen.
- A native HTTPS Chat Completions request uses `tencent/hy-mt2-30b-a3b`
  (or 7B) for English-to-Arabic subtitling.
- Preserves the original Google, DeepL, and Gemini choices.
- Short-term translation context and existing disk cache remain active.
- OpenRouter key is kept in iOS Keychain, not written to UserDefaults JSON.
- Short timeout followed by existing Google fallback if OpenRouter fails,
  so an AI outage does not freeze subtitles.
- **No modification** to PS5 streaming, game video frames, the TV Android APK,
  the TV subtitle protocol or display-resolution processing.

## Configure
1. Install a build signed with your own iOS signing credentials.
2. Settings > Target language: **Arabic**.
3. Settings > Translation engine > **OpenRouter · Hy-MT2**.
4. Paste your own API key into the masked field, then **Save and test**.
5. Pick 30B for first quality test or 7B for a speed comparison.
6. The existing paired TCL app receives Arabic subtitles unchanged.

## Build
A GitHub Actions workflow checks out the **original app** at a fixed commit,
copies these seven modified source files into it, runs its original tests and
builds an **unsigned IPA**. The IPA needs your own signing certificate before
installation. The app bundle identifier is not intentionally changed.

### Security and limitations
- Never add your personal API key to the repository.
- The remote model receives the text of subtitles and some previous lines.
  It does not receive game video or image data from this translator.
- This build has not been tested on the user's physical iPhone or TCL.
- The system's original video/HDMI path is unchanged.
- Prices and availability depend on the selected OpenRouter provider.
- A 5.5-second provider timeout is intentionally capped for responsive fallback.
