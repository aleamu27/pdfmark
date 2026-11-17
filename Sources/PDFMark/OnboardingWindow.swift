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
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to PDFMark"
            window.isReleasedWhenClosed = false
            window.center()
            let host = NSHostingView(rootView: OnboardingView())
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center()
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
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to PDFMark")
                    .font(.title2.bold())
                Text("Bookmark pages and add comments to the PDFs you read in Preview — saved right in the file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                step(number: "1", text: "Open a PDF in Preview and scroll to the page you want to mark.")
                step(number: "2", text: "Click the bookmark icon in the menu bar and choose Bookmark This Page or Add Comment…")
                step(number: "3", text: "For a comment, drag the note to the spot you want — on either page of a spread — and type your text.")
                step(number: "4", text: "Use Show All Comments… to edit, move, recolor or delete notes. Every change can be undone from the menu.")
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
                    if !accessibilityTrusted {
                        Button("Grant access…") { requestAccess() }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: accessibilityTrusted)

                if !accessibilityTrusted {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Already switched PDFMark on in System Settings? macOS applies it after a restart of PDFMark.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart PDFMark") { AppLocation.relaunch() }
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func requestAccess() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }
}
