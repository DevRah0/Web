# GameTranslator iOS 1.8.6 — OpenRouter patch

This is a compatibility-only modification of the **same existing iPhone app**, based on the exact source tag:
https://github.com/SimonPetrus/GameTranslator-iOS/tree/ios-v1.8.6

The uploaded IPA matches SHA-256 of the upstream release:
`7428f256fa16e5763a19f1d8b902f71ccaf0d7edd4cf3671358d148c9cede5f9`.

## Changes
- Opt-in OpenRouter translation engine, model `tencent/hy-mt2-30b-a3b`, English → Modern Standard Arabic.
- Cinematic localization system prompt, limited previous dialogue context, no arbitrary new story content.
- API key stored securely in **iOS Keychain**, not in settings JSON or source control.
- Test API button makes one small billable translation request.
- Fallback to Google if the service is unavailable or the response is not Arabic.
- Other engines, OCR, PS5 link, TV subtitle transport, design and HDMI image quality unchanged.
- Original bundle ID: `com.gametranslator.gametranslatorMobile`.

The workflow clones the upstream version and overlays only seven code files at build time.
New build number: 14 (original uploaded 1.8.6 build 13). Like the upstream IPA, output is **unsigned**.
Sign with your existing Feather / Sideloadly / AltStore identity. If the signing identity or team changes, PS5 and API
Keychain access may not carry over and re-pairing may be required.

Build relies on upstream public native libchiaki artifact; if permissions or expiration block download,
the workflow cannot make an IPA until the native dependency is restored. There is no API key in this repo.

Licensed under upstream **AGPL-3.0-only**. Full original source and notices: pinned tag above.
