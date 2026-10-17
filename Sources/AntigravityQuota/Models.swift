import Foundation
import SwiftUI

public struct QuotaBucket: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let group: String
    public let remainingFraction: Double // 0.0 ... 1.0
    public let resetTime: Date?

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

public struct QuotaState: Sendable {
    public var gemini5h: QuotaBucket? = nil
    public var geminiWeekly: QuotaBucket? = nil
    public var thirdParty5h: QuotaBucket? = nil
    public var thirdPartyWeekly: QuotaBucket? = nil
    public var planName: String? = nil
    public var lastUpdated: Date? = nil
    public var errorMessage: String? = nil
    public var isLoading: Bool = false

    public var primaryPercent: Int? {
        if let g5h = gemini5h {
            return Int(round(g5h.remainingPercent))
        }
        return nil
    }
}
