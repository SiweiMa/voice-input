# VoiceInput

VoiceInput is a macOS menu bar app that lets you hold the `Fn` key to dictate text, transcribe it, optionally refine it with an LLM, and paste the result into the active app.

It supports two transcription backends:

- Apple Speech for fully local macOS speech recognition
- OpenAI-compatible speech transcription endpoints for remote transcription

## Features

- Menu bar app with no dock icon
- Hold `Fn` to start recording, release to stop
- Live recording overlay with waveform and transcript preview
- Automatic paste into the focused app
- Language switching from the menu bar
- Optional transcript refinement through an OpenAI-compatible chat endpoint
- Built-in settings window for speech provider and API configuration

## Requirements

- macOS 14 or newer
- Xcode command line tools with Swift 5.10+
- Permissions for:
  - Microphone
  - Input Monitoring
  - Accessibility
  - Speech Recognition when using Apple Speech

## Quick Start

Build and launch the app:

```bash
make run
```

Install it into `/Applications`:

```bash
make install
```

Run tests:

```bash
swift test
```

## How To Use

1. Launch the app.
2. Approve the macOS permission prompts.
3. Open the menu bar item to pick a language or open `Settings...`.
4. Hold `Fn` while speaking.
5. Release `Fn` to transcribe and paste into the active app.

By default, the app starts with Apple Speech and a default language of Simplified Chinese. You can change the language at any time from the menu bar.

## Settings

The settings window lets you choose between:

- `Apple Speech`
- `OpenAI`

If you choose `OpenAI`, configure:

- API Base URL
- API Key
- Speech Model

If you enable refinement, also configure:

- Refinement Model

The app expects OpenAI-compatible endpoints. A typical base URL looks like:

```text
https://api.openai.com/v1
```

For speech transcription, the app sends audio to:

```text
/audio/transcriptions
```

## Permissions Notes

VoiceInput depends on several macOS permissions to work correctly:

- `Input Monitoring` is required to detect the `Fn` key reliably.
- `Accessibility` is required to paste text into the active app.
- `Microphone` is required for recording.
- `Speech Recognition` is required only when using Apple Speech.

If the menu bar app shows warnings, grant the missing permission in System Settings and relaunch the app.

## Development

Common commands:

```bash
make build
make run
make install
make clean
swift test
```

Project layout:

- `Sources/VoiceInput`: app source
- `Tests/VoiceInputTests`: unit tests
- `AppResources/Info.plist`: app bundle metadata

## Architecture Overview

- `AppController` coordinates permissions, recording, transcription, refinement, and paste injection.
- `FnKeyMonitor` listens for `Fn` key press and release events.
- `SpeechTranscriber` switches between Apple and OpenAI transcription backends.
- `RecordingOverlayController` manages the on-screen recording UI.
- `LLMRefiner` optionally cleans up dictated text before paste.
