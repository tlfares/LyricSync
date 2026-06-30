# LyricSync

**iOS/Mac app that transcribes and/or syncs lyrics from any audio file, using Apple Intelligence or Mistral AI.**

Import a song, get lyrics with timestamps, and export ready-to-use files for any media player supporting LRC.

## Features

- **Import any audio file** — M4A, MP3, WAV, AIFF
- **Transcription** — Apple Intelligence : on-device or Private Cloud Compute, or Mistral AI Voxtral
- **Smart punctuation** — Mistral LLM perfects punctuation and line breaks where natural
- **Paste existing lyrics** — You can also paste your own text to sync it.
- **Export M4A** with embedded lyrics, sideloadable to the iOS Music app (but NOT synced as Apple refuses to display any synced lyrics for non-AppleMusic songs.
- **Export LRC** files for any media player that supports them.
- **Edit lyrics** after transcription — fix any mistakes inline
- **Low‑confidence warnings** — spots words the model isn't sure about

## Requirements

- iOS 17+ or macOS 14+
- (Optional) Mistral AI API key for FAR BETTER transcription

## Install

Download the latest release:

- **iOS**: `LyricSync.ipa` — sideload with AltStore, SideStore, or similar
- **macOS**: `LyricSync.app` — unzip and drag to Applications

> Speech recognition requires a physical device — not available in the iOS simulator.
