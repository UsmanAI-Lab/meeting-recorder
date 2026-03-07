import SwiftUI

// MARK: - TranscriptDetailView

/// Full-screen view of a single meeting transcript.
@available(macOS 13.0, *)
struct TranscriptDetailView: View {

    @EnvironmentObject var coordinator: MeetingCoordinator
    @Environment(\.dismiss) var dismiss

    let meeting: Meeting

    @State private var copiedToClipboard = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()

                // Copy button
                Button {
                    copyTranscript()
                } label: {
                    Label(
                        copiedToClipboard ? "Copied!" : "Copy",
                        systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedToClipboard ? .green : .blue)
                .animation(.easeInOut, value: copiedToClipboard)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Meeting metadata
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(meeting.formattedDate, systemImage: "calendar")
                    if meeting.duration > 0 {
                        Label(meeting.formattedDuration, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Transcript text
            ScrollView {
                if meeting.transcript.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.alignleft")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No transcript available")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Text(meeting.transcript)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
        .frame(width: 560, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(meeting.transcript, forType: .string)
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}
