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

struct AccountQuotaCard: View {
    let account: AccountQuotaState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Account Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.shortLabel)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Text(account.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let plan = account.planName {
                        Text(plan)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let pct = account.primaryPercent {
                    Text("\(pct)%")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(account.gemini5h?.statusColor ?? .primary)
                }
            }

            if let error = account.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption2)
                        .lineLimit(3)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Gemini Section
            VStack(alignment: .leading, spacing: 6) {
                Label("Google Gemini", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                QuotaProgressRow(label: "5-Hour Window", bucket: account.gemini5h)
                QuotaProgressRow(label: "Weekly Limit", bucket: account.geminiWeekly)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Claude / GPT (3P) Section
            VStack(alignment: .leading, spacing: 6) {
                Label("Claude & GPT (3P)", systemImage: "cube.box")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                QuotaProgressRow(label: "5-Hour Window", bucket: account.thirdParty5h)
                QuotaProgressRow(label: "Weekly Limit", bucket: account.thirdPartyWeekly)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

public struct QuotaMenuView: View {
    @ObservedObject var service: QuotaService

    public init(service: QuotaService) {
        self.service = service
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Antigravity Quota")
                        .font(.headline)
                    if service.state.accounts.count > 1 {
                        Text("\(service.state.accounts.count) Accounts Connected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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

            // Tab Picker when multiple accounts exist
            if service.state.accounts.count > 1 {
                Picker("", selection: Binding(
                    get: { service.selectedTab },
                    set: { service.selectedTab = $0 }
                )) {
                    Text("All").tag("all")
                    ForEach(service.state.accounts) { acct in
                        Text(acct.displayName).tag(acct.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            if let globalError = service.state.globalErrorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(globalError)
                        .font(.caption)
                        .lineLimit(3)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Accounts List / Card View
            if service.state.accounts.isEmpty && !service.state.isLoading {
                VStack(spacing: 6) {
                    Text("No accounts found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add credentials in Keychain or ~/.gemini")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        ForEach(service.state.accounts) { acct in
                            if service.selectedTab == "all" || service.selectedTab == acct.id || service.state.accounts.count <= 1 {
                                AccountQuotaCard(account: acct)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: service.state.accounts.count > 1 ? 460 : 360)
            }

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
        .frame(width: 340)
    }
}