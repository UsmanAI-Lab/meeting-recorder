# MeetingRecorder

A native macOS menu bar app for recording, transcribing, and storing meeting notes. Lives quietly in your menu bar — click to start recording, click to stop. That's it.

## Features

- 🎙️ Captures both microphone (you) and system audio (others) simultaneously
- 🤖 Transcribes via OpenAI Whisper API (large model, highest accuracy)
- 🗑️ Audio files deleted immediately after transcription
- 🗄️ Transcripts stored locally in SQLite database
- 📋 Browse, search, and copy past meeting transcripts
- 🔒 No audio ever stored permanently — privacy first

## Requirements

- macOS 13.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- OpenAI API key

## Setup

```bash
# Clone the repo
git clone https://github.com/UsmanAI-Lab/meeting-recorder.git
cd meeting-recorder

# Run setup (installs XcodeGen if needed, generates Xcode project)
./setup.sh

# Open in Xcode
open MeetingRecorder.xcodeproj
```

In Xcode:
1. Select your development team under Signing & Capabilities
2. Build & Run (⌘R)
3. On first launch, grant Microphone and Screen Recording permissions
4. Open Settings (gear icon) and paste your OpenAI API key

## Architecture

```
MeetingRecorder/
├── App/
│   ├── MeetingRecorderApp.swift     # @main entry point
│   └── AppDelegate.swift            # NSStatusItem + lifecycle
├── MenuBar/
│   └── MenuBarManager.swift         # Menu bar state & popover
├── Audio/
│   ├── AudioRecordingEngine.swift   # Orchestrates recording
│   ├── MicrophoneCapture.swift      # AVAudioEngine mic tap
│   └── SystemAudioCapture.swift     # ScreenCaptureKit system audio
├── Transcription/
│   └── WhisperService.swift         # OpenAI Whisper API client
├── Database/
│   ├── AppDatabase.swift            # GRDB setup & migrations
│   └── Meeting.swift                # Data model
├── Views/
│   ├── MenuBarView.swift            # Main popover UI
│   ├── TranscriptListView.swift     # Meeting history
│   ├── TranscriptDetailView.swift   # Full transcript view
│   └── SettingsView.swift           # API key + preferences
└── Resources/
    ├── Info.plist
    └── MeetingRecorder.entitlements
```

## Permissions Required

- **Microphone** — to capture your voice
- **Screen Recording** — required by ScreenCaptureKit to capture system audio (no actual screen is recorded)

## Transcription

Uses OpenAI's `whisper-1` model via the Whisper API. This is the same large Whisper model that powers many commercial transcription services. Accuracy is excellent for meeting audio.

Cost: ~$0.006 per minute of audio (~$0.36/hour). A 1-hour meeting ≈ $0.36.

## Database

SQLite stored at `~/Library/Application Support/MeetingRecorder/meetings.db`. Each meeting stores:
- Title (auto-generated from date/time, editable)
- Date & duration
- Full transcript text
- Created/updated timestamps

## Future Enhancements

- Speaker diarization (who said what) via AssemblyAI or Deepgram
- GPT-4 meeting summaries + action item extraction
- Search across all transcripts
- Export to Notion/Obsidian/email
- Auto-detect meeting start from calendar
- Zoom/Teams/Meet app detection for auto-titling
