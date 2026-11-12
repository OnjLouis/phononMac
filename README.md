# Phonon for Mac

Offline, multilingual Phonon voices for VoiceOver and other macOS speech
applications. Includes 102 voices in English, French, German, Spanish and
Portuguese, with English character voices available in VoiceOver as well.

Requires macOS 15 or later on Apple Silicon. Speech runs locally using Core ML;
no server, account or first-use model download is needed.

## Downloads

- [Latest Mac release](https://github.com/OnjLouis/phononMac/releases/latest)
- [Phonon for iPhone and iPad on the App Store](https://apps.apple.com/app/phonon/id6828988617)
- [Report an issue](https://github.com/OnjLouis/phononMac/issues)
- [Phonon for NVDA](https://github.com/OnjLouis/phononNVDA)
- [Phonon SAPI for Windows](https://github.com/OnjLouis/phononSAPI)
- [Software catalogue](https://onj.me/software), [contact](https://onj.me/contact)
  and [donate](https://onj.me/donate)

The free iOS and iPadOS edition provides the same 102-voice catalogue for
VoiceOver, with offline on-device speech. It requires iOS or iPadOS 18 or later.
Open it once to prepare the voices, then choose them in VoiceOver's speech
settings; the companion app does not need to stay open.

Copy the app from the DMG into Applications, open it and wait for Ready.
Choose a voice and use Test Voice. Add a Phonon voice in VoiceOver Utility and
select it. Keep a familiar Apple voice available as an alternative. Closing the
settings app does not disable the voices. The first utterance may take several
seconds while Core ML prepares the model; subsequent speech streams immediately.

VoiceOver controls rate, pitch and volume. Navigating cancels obsolete speech.
The app's Help button opens the complete manual.

## Updates

Version 1.0.6 adds **Manage Imported Voices** for compatible `.safetensors`
files and preview examples in the selected language. The 102 built-in voices,
their identifiers, and saved settings are unchanged. Earlier release notes are
in the included manual.

Choose Never, Hourly or Daily checking in the settings app, or check immediately.
Checks run only while that app is open. Updates verify the Phonon signature,
size, hash, Apple developer identity and notarization before replacement, and
preserve preferences and prepared models. VoiceOver can continue using its
loaded voice; restart VoiceOver afterward when convenient.

Speech text and audio stay on the Mac. Only update checks and approved downloads
contact GitHub. No login item or background update service is installed.

## Credits and Licences

By Andre Louis, with development assistance from OpenAI Codex. The native
runtime is [Gradium's Phonon](https://github.com/gradium-ai/xn-ptts), based on
Kyutai's Pocket TTS and Mimi. Voices come from
[Gradium's catalogue](https://huggingface.co/gradium/phonon-voices).
Rate and pitch processing use [Sonic by Bill Cox](https://github.com/waywardgeek/sonic).

Application code is GPL-3.0-or-later. Third-party runtime code is MIT OR
Apache-2.0; the catalogue and Sonic are Apache-2.0. The bundled
[40M multilingual model](https://huggingface.co/gradium/phonon-40m-multilingual)
is CC BY-NC 4.0, restricting commercial use. It was converted to Core ML, not
retrained. Original notices are included. This is an independent project, not
an official or endorsed Gradium or Apple product.

## Building

The project uses Swift Package Manager and XcodeGen. Run `swift test` for unit
tests, then `xcodegen generate` and build the generated PhononMac scheme in
Xcode. The app and speech extension must be signed with the same developer team
and shared app-group entitlement for installation.

Model assets are not duplicated in the source repository. Obtain the matching
multilingual Core ML export using Gradium's export tools, or copy the Models
resource directory from a release app into `Resources/Models` under its original
licence. Also copy `Projection.bin` from the same release app's resources into
`Resources`; it contains the matching model's speaker projection for imported
voices. Preserve the model inventory and ASCII voice resource names.
Do not substitute another model checkpoint without rebuilding and testing its
configuration. The provider generates audio locally and does not contact GitHub.
