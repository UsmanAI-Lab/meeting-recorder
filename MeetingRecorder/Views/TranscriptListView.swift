import SwiftUI

// MARK: - TranscriptListView

/// Scrollable list of past meetings.
@available(macOS 13.0, *)
struct TranscriptListView: View {

    let meetings: [Meeting]
    @EnvironmentObject var coordinator: MeetingCoordinator

    @State private var selectedMeeting: Meeting?
    @State private var showDetail = false
    @State private var meetingToRename: Meeting?
    @State private var renameTitle = ""
    @State private var showRenameAlert = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(meetings) { meeting in
                    MeetingRowView(meeting: meeting)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMeeting = meeting
                            showDetail = true
                        }
                        .contextMenu {
                            contextMenu(for: meeting)
                        }

                    if meeting.id != meetings.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(meetings.count) * 72, 320))
        .sheet(isPresented: $showDetail) {
            if let meeting = selectedMeeting {
                TranscriptDetailView(meeting: meeting)
                    .environmentObject(coordinator)
            }
        }
        .alert("Rename Meeting", isPresented: $showRenameAlert) {
            TextField("Meeting title", text: $renameTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let meeting = meetingToRename, !renameTitle.isEmpty {
                    coordinator.renameMeeting(meeting, title: renameTitle)
                }
            }
        } message: {
            Text("Enter a new name for this meeting.")
        }
    }

    @ViewBuilder
    private func contextMenu(for meeting: Meeting) -> some View {
        Button {
            UIPasteboard.copyToClipboard(meeting.transcript)
        } label: {
            Label("Copy Transcript", systemImage: "doc.on.doc")
        }

        Button {
            meetingToRename = meeting
            renameTitle = meeting.title
            showRenameAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            coordinator.deleteMeeting(meeting)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - MeetingRowView

@available(macOS 13.0, *)
private struct MeetingRowView: View {

    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(meeting.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if meeting.duration > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(meeting.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Transcript preview chevron
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Clipboard helper

private struct UIPasteboard {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
