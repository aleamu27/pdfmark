import AppKit
import SwiftUI
import ApplicationServices

/// First-launch window explaining what PDFMark does and walking the user
/// through granting Accessibility access (required to read the page Preview
/// is showing and the file it has open). Shown once automatically; can be
/// re-opened later from the status item menu.
enum OnboardingWindow {
    private static let hasShownKey = "PDFMarkHasShownOnboarding"
    private static var controller: NSWindowController?

    static var hasShownBefore: Bool {
        UserDefaults.standard.bool(forKey: hasShownKey)
    }

    static func showIfNeeded() {
        guard !hasShownBefore else { return }
        show()
    }

    static func show() {
        UserDefaults.standard.set(true, forKey: hasShownKey)

        if controller == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to PDFMark"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: OnboardingView())
            controller = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Welcome to PDFMark")
                    .font(.title2.bold())
                Text("Set a real bookmark on the page you're reading in Preview, without leaving the keyboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                step(number: "1", text: "Open a PDF in Preview and scroll to the page you want to mark.")
                step(number: "2", text: "Click the bookmark icon in the menu bar at the top of the screen.")
                step(number: "3", text: "Confirm the page number in the box that appears, and press Enter.")
                step(number: "4", text: "The bookmark is saved directly in the PDF file — visible in Preview's table of contents (⌘⌥3) and as a small red ribbon on the page itself.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Accessibility access")
                    .font(.headline)
                Text("PDFMark needs Accessibility access to see which page and file you have open in Preview. This is granted in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted ? "Access granted" : "Access not granted yet")
                        .font(.callout)
                    Spacer()
                    Button(accessibilityTrusted ? "Check again" : "Grant access…") {
                        requestAccess()
                    }
                }

                if !accessibilityTrusted {
                    Text("Just granted access in System Settings but still seeing orange here? macOS requires PDFMark to be restarted (quit and reopen the app) before the change takes effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 460)
    }

    private func step(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.red.opacity(0.15)))
                .foregroundStyle(.red)
            Text(text)
                .font(.callout)
            Spacer()
        }
    }

    private func requestAccess() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
