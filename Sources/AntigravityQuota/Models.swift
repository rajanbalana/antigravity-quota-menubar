import Foundation
import SwiftUI

public struct QuotaBucket: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let group: String
    public let remainingFraction: Double // 0.0 ... 1.0
    public let resetTime: Date?

    public init(id: String, label: String, group: String, remainingFraction: Double, resetTime: Date?) {
        self.id = id
        self.label = label
        self.group = group
        self.remainingFraction = remainingFraction
        self.resetTime = resetTime
    }

    public var usedPercent: Double {
        max(0.0, min(100.0, (1.0 - remainingFraction) * 100.0))
    }

    public var remainingPercent: Double {
        max(0.0, min(100.0, remainingFraction * 100.0))
    }

    public var statusColor: Color {
        if remainingPercent > 50 {
            return .green
        } else if remainingPercent > 20 {
            return .yellow
        } else {
            return .red
        }
    }

    public var formattedCountdown: String {
        guard let resetTime = resetTime else { return "Unknown" }
        let diff = resetTime.timeIntervalSince(Date())
        if diff <= 0 {
            return "Resetting now"
        }
        let totalMinutes = Int(diff) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "in \(days)d \(remHours)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
}

public struct AccountQuotaState: Identifiable, Sendable {
    public let id: String
    public var defaultName: String
    public var email: String?
    public var gemini5h: QuotaBucket?
    public var geminiWeekly: QuotaBucket?
    public var thirdParty5h: QuotaBucket?
    public var thirdPartyWeekly: QuotaBucket?
    public var planName: String?
    public var lastUpdated: Date?
    public var errorMessage: String?
    public var isLoading: Bool

    public init(
        id: String,
        defaultName: String,
        email: String? = nil,
        gemini5h: QuotaBucket? = nil,
        geminiWeekly: QuotaBucket? = nil,
        thirdParty5h: QuotaBucket? = nil,
        thirdPartyWeekly: QuotaBucket? = nil,
        planName: String? = nil,
        lastUpdated: Date? = nil,
        errorMessage: String? = nil,
        isLoading: Bool = false
    ) {
        self.id = id
        self.defaultName = defaultName
        self.email = email
        self.gemini5h = gemini5h
        self.geminiWeekly = geminiWeekly
        self.thirdParty5h = thirdParty5h
        self.thirdPartyWeekly = thirdPartyWeekly
        self.planName = planName
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
        self.isLoading = isLoading
    }

    public var displayName: String {
        if let email = email, !email.isEmpty {
            return email
        }
        return defaultName
    }

    public var shortLabel: String {
        if id == "account-1" { return "A1" }
        if id == "account-2" { return "A2" }
        return String(id.prefix(2)).uppercased()
    }

    public var primaryPercent: Int? {
        if let g5h = gemini5h {
            return Int(round(g5h.remainingPercent))
        }
        return nil
    }
}

public struct QuotaState: Sendable {
    public var accounts: [AccountQuotaState] = []
    public var lastUpdated: Date? = nil
    public var globalErrorMessage: String? = nil
    public var isLoading: Bool = false

    public init(
        accounts: [AccountQuotaState] = [],
        lastUpdated: Date? = nil,
        globalErrorMessage: String? = nil,
        isLoading: Bool = false
    ) {
        self.accounts = accounts
        self.lastUpdated = lastUpdated
        self.globalErrorMessage = globalErrorMessage
        self.isLoading = isLoading
    }

    // Backward-compatible accessors for Account 1 (Primary)
    public var primaryAccount: AccountQuotaState? {
        accounts.first
    }
    public var secondAccount: AccountQuotaState? {
        accounts.count > 1 ? accounts[1] : nil
    }

    public var gemini5h: QuotaBucket? { primaryAccount?.gemini5h }
    public var geminiWeekly: QuotaBucket? { primaryAccount?.geminiWeekly }
    public var thirdParty5h: QuotaBucket? { primaryAccount?.thirdParty5h }
    public var thirdPartyWeekly: QuotaBucket? { primaryAccount?.thirdPartyWeekly }
    public var planName: String? { primaryAccount?.planName }
    public var errorMessage: String? { globalErrorMessage ?? primaryAccount?.errorMessage }

    public var primaryPercent: Int? {
        primaryAccount?.primaryPercent
    }
}