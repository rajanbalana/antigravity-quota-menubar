import SwiftUI

struct QuotaProgressRow: View {
    let label: String
    let bucket: QuotaBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let bucket = bucket {
                    Text("\(Int(round(bucket.remainingPercent)))% remaining")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(bucket.statusColor)
                } else {
                    Text("N/A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let bucket = bucket {
                ProgressView(value: bucket.remainingPercent, total: 100.0)
                    .tint(bucket.statusColor)

                HStack {
                    Text("Resets \(bucket.formattedCountdown)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Used: \(String(format: "%.1f", bucket.usedPercent))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

public struct QuotaMenuView: View {
    @ObservedObject var service: QuotaService

    public init(service: QuotaService) {
        self.service = service
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Antigravity Quota")
                        .font(.headline)
                    if let plan = service.state.planName {
                        Text(plan)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                Button(action: {
                    Task {
                        await service.refresh()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(service.state.isLoading ? 360 : 0))
                        .animation(service.state.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: service.state.isLoading)
                }
                .buttonStyle(.borderless)
                .disabled(service.state.isLoading)
                .help("Refresh quota")
            }

            Divider()

            if let error = service.state.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Gemini Section
            VStack(alignment: .leading, spacing: 8) {
                Label("Google Gemini", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                QuotaProgressRow(label: "5-Hour Window", bucket: service.state.gemini5h)
                QuotaProgressRow(label: "Weekly Limit", bucket: service.state.geminiWeekly)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Claude / GPT (3P) Section
            VStack(alignment: .leading, spacing: 8) {
                Label("Claude & GPT (3P)", systemImage: "cube.box")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                QuotaProgressRow(label: "5-Hour Window", bucket: service.state.thirdParty5h)
                QuotaProgressRow(label: "Weekly Limit", bucket: service.state.thirdPartyWeekly)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // Footer
            HStack {
                if let updated = service.state.lastUpdated {
                    Text("Updated \(updated, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
