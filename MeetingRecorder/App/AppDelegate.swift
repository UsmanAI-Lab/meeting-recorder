import AppKit
import SwiftUI

// MARK: - AppDelegate

@available(macOS 13.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Menu Bar

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: MeetingCoordinator?

    // MARK: - Application Did Finish Launching

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Set up the shared coordinator
        let coordinator = MeetingCoordinator()
        self.coordinator = coordinator

        // Build the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(coordinator)
        )
        self.popover = popover

        // Create the status bar item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Meeting Recorder")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Observe recording state to update menu bar icon
        Task {
            for await _ in coordinator.$recordingState.values {
                await MainActor.run { self.updateStatusItemIcon() }
            }
        }

        print("[AppDelegate] Meeting Recorder launched.")
    }

    // MARK: - Popover Toggle

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover, let button = statusItem?.button else { return }

        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            // Right click: show context menu
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        guard let coordinator else { return }
        let menu = NSMenu()

        if coordinator.isRecording {
            let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else if !coordinator.isBusy {
            let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Meeting Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func startRecording() {
        coordinator?.startRecording()
    }

    @objc private func stopRecording() {
        coordinator?.stopRecording()
    }

    // MARK: - Icon Updates

    private func updateStatusItemIcon() {
        guard let coordinator, let button = statusItem?.button else { return }

        if coordinator.isRecording {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
            // Tint red while recording
            button.image = tintedImage(
                NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording"),
                tint: .systemRed
            )
        } else if coordinator.isTranscribing {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Transcribing")
        } else {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Meeting Recorder")
        }
    }

    private func tintedImage(_ image: NSImage?, tint: NSColor) -> NSImage? {
        guard let image else { return nil }
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        tint.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    // MARK: - App Termination

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure any in-progress recording is cleanly stopped
        if let coordinator, coordinator.isRecording {
            Task {
                await coordinator.engine.stopRecording()
            }
        }
    }
}
