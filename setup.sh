#!/bin/bash
set -e

echo "🎙️  MeetingRecorder Setup"
echo "========================"

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Install from https://brew.sh first."
    exit 1
fi

# Install XcodeGen if needed
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Installing XcodeGen..."
    brew install xcodegen
else
    echo "✅ XcodeGen already installed"
fi

# Generate Xcode project
echo "🔧 Generating Xcode project..."
xcodegen generate

echo ""
echo "✅ Done! Next steps:"
echo "   1. Open: open MeetingRecorder.xcodeproj"
echo "   2. In Xcode → Signing & Capabilities → select your development team"
echo "   3. Build & Run (⌘R)"
echo "   4. Grant Microphone + Screen Recording permissions when prompted"
echo "   5. Click the menu bar icon → Settings → add your OpenAI API key"
echo ""
echo "Happy recording."
