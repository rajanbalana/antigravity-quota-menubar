import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let service = QuotaService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from macOS Dock so it runs strictly as a status bar accessory
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct AntigravityQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            QuotaMenuView(service: appDelegate.service)
        } label: {
            StatusLabel(service: appDelegate.service)
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusLabel: View {
    @ObservedObject var service: QuotaService

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
            if let pct = service.state.primaryPercent {
                Text("\(pct)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else if service.state.isLoading {
                Text("...")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else {
                Text("AGY")
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}
