import SwiftUI

struct OnboardingView: View {
    @ObservedObject var perms = PermissionsManager.shared
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(ThemeStore.shared.accent)
                VStack(alignment: .leading) {
                    Text("Welcome to Handwritten").font(.title2.bold())
                    Text("Two permissions are needed before it can type for you.")
                        .foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Lets Handwritten send keystrokes to other apps and read back what it typed.",
                granted: perms.accessibility,
                action: perms.requestAccessibility
            )
            PermissionRow(
                title: "Input Monitoring",
                detail: "Lets Escape stop typing and lets your clicks auto-pause it.",
                granted: perms.inputMonitoring,
                action: perms.requestInputMonitoring
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If a permission is already ON but still shows as missing")
                        .font(.callout.bold())
                    Text("This happens after updating or rebuilding the app. In System Settings, select Handwritten, click the minus (–) button to remove it, then add it again with +, or toggle it off and on. Then relaunch Handwritten.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Relaunch Handwritten") { AppRelauncher.relaunch() }
                Spacer()
                Button(perms.allGranted ? "Done" : "Continue Anyway") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { perms.refresh() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            } else {
                Text("Granted").foregroundStyle(.green).font(.callout.bold())
            }
        }
    }
}

enum AppRelauncher {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.6; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
