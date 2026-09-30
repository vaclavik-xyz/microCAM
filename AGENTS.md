# microCAM – notes for coding agents

- Swift, SwiftPM. The only third-party dependency is Sparkle (updates);
  don't add others. `swift test` must pass;
  `scripts/make-app.sh` builds the app bundle.
- Pure logic goes into `Sources/MicroCAMCore` with unit tests.
  `Sources/MicroCAMApp` is the thin AVFoundation/SwiftUI layer.
- **Every new UI text must exist in English and Czech** (and in any other
  language in `Resources/*.lproj`). Write it in English in the code, add the
  key to every `Localizable.strings` (and to every language of `STRINGS` in
  `StreamPage.swift` for the stream page). `LocalizationTests` fails when a
  key is missing. No hard-coded Czech in Swift sources.
- Texts are short and plain: say what a setting does, what a button does,
  what went wrong and what to do. Czech uses "ty". English uses sentence
  case. A job (repair order) is "Job" / "zakázka" everywhere.
- Adding a language: see "Localization" in README.md.
- Never commit names of the maintainer's machines, Tailscale addresses or
  tailnet host names; `NoDeviceNamesTests` checks every tracked file.
- Webhook field names and values (`kind=photo`, …) are an API: don't
  translate or rename them.
