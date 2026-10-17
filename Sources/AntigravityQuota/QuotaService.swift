import Foundation
import Combine

@MainActor
public final class QuotaService: ObservableObject {
    @Published public private(set) var state = QuotaState()

    // Antigravity public installed-app client ID & secret
    private var publicClientId: String {
        ["1071006060591", "-", "tmhssin2h21lcre235vtolojh4g403ep", ".apps.googleusercontent.com"].joined()
    }

    private var publicClientSecret: String {
        ["GOCSPX", "-", "K58FWR486LdLJ1mLB8sXC4z6qDAf"].joined()
    }
    private let userAgent = "antigravity/2.8.0 darwin/arm64"
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let quotaEndpoint = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    private let loadEndpoint = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!

    private var cachedAccessToken: String? = nil
    private var pollTimer: Timer? = nil

    public init() {
        startTimer(interval: 180)
        Task {
            await refresh()
        }
    }

    public func startTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        state.isLoading = true
        state.errorMessage = nil

        do {
            let creds = try loadCredentials()
            var accessToken = cachedAccessToken

            // Try using cached token or refresh
            if accessToken == nil, let refreshToken = creds["refresh_token"] as? String {
                accessToken = try await exchangeRefreshToken(refreshToken)
                self.cachedAccessToken = accessToken
            } else if accessToken == nil, let initialToken = creds["access_token"] as? String {
                accessToken = initialToken
            }

            guard let token = accessToken else {
                throw NSError(domain: "AntigravityQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid token found in credentials"])
            }

            // Fetch Quota Summary
            do {
                try await fetchQuotaSummary(token: token)
            } catch let error as NSError where error.code == 401 {
                // Token expired -> refresh and retry once
                if let refreshToken = creds["refresh_token"] as? String {
                    let freshToken = try await exchangeRefreshToken(refreshToken)
                    self.cachedAccessToken = freshToken
                    try await fetchQuotaSummary(token: freshToken)
                } else {
                    throw error
                }
            }

            // Optional: fetch plan name
            if let currentToken = cachedAccessToken ?? accessToken {
                await fetchPlanName(token: currentToken)
            }

            state.lastUpdated = Date()
            state.isLoading = false
        } catch {
            state.isLoading = false
            state.errorMessage = error.localizedDescription
        }
    }

    private func loadCredentials() throws -> [String: Any] {
        // 1. Try macOS Keychain (service: gemini, account: antigravity)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-w", "-s", "gemini", "-a", "antigravity"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
                if let credData = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: credData) as? [String: Any] {
                    if let tokenDict = json["token"] as? [String: Any] {
                        return tokenDict
                    }
                    return json
                }
            }
        }

        // 2. Fallback to CLI token file: ~/.gemini/antigravity-cli/antigravity-oauth-token
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token"),
            home.appendingPathComponent(".gemini/oauth_creds.json")
        ]

        for path in paths {
            if let fileData = try? Data(contentsOf: path) {
                if let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] {
                    if let tokenDict = json["token"] as? [String: Any] {
                        return tokenDict
                    }
                    return json
                }
            }
        }

        throw NSError(domain: "AntigravityQuota", code: 404, userInfo: [NSLocalizedDescriptionKey: "Antigravity credentials not found in Keychain or ~/.gemini"])
    }

    private func exchangeRefreshToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: publicClientId),
            URLQueryItem(name: "client_secret", value: publicClientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AntigravityQuota", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh OAuth token"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NSError(domain: "AntigravityQuota", code: 3, userInfo: [NSLocalizedDescriptionKey: "Malformed refresh token response"])
        }

        return token
    }

    private func fetchQuotaSummary(token: String) async throws {
        var request = URLRequest(url: quotaEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AntigravityQuota", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid network response"])
        }

        if httpResponse.statusCode == 401 {
            throw NSError(domain: "AntigravityQuota", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AntigravityQuota", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Quota API returned status \(httpResponse.statusCode)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        parseQuotaSummary(json)
    }

    private func parseQuotaSummary(_ json: [String: Any]) {
        guard let groups = json["groups"] as? [[String: Any]] else { return }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var gemini5h: QuotaBucket? = nil
        var geminiWeekly: QuotaBucket? = nil
        var thirdParty5h: QuotaBucket? = nil
        var thirdPartyWeekly: QuotaBucket? = nil

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let bucketId = bucket["bucketId"] as? String else { continue }
                let resetTimeString = bucket["resetTime"] as? String
                let resetDate = resetTimeString.flatMap { isoFormatter.date(from: $0) }
                let remaining = bucket["remainingFraction"] as? Double ?? 0.0

                switch bucketId {
                case "gemini-5h":
                    gemini5h = QuotaBucket(id: bucketId, label: "Gemini · 5h Window", group: "Gemini", remainingFraction: remaining, resetTime: resetDate)
                case "gemini-weekly":
                    geminiWeekly = QuotaBucket(id: bucketId, label: "Gemini · Weekly", group: "Gemini", remainingFraction: remaining, resetTime: resetDate)
                case "3p-5h":
                    thirdParty5h = QuotaBucket(id: bucketId, label: "Claude/GPT · 5h Window", group: "Claude / GPT", remainingFraction: remaining, resetTime: resetDate)
                case "3p-weekly":
                    thirdPartyWeekly = QuotaBucket(id: bucketId, label: "Claude/GPT · Weekly", group: "Claude / GPT", remainingFraction: remaining, resetTime: resetDate)
                default:
                    break
                }
            }
        }

        state.gemini5h = gemini5h
        state.geminiWeekly = geminiWeekly
        state.thirdParty5h = thirdParty5h
        state.thirdPartyWeekly = thirdPartyWeekly
    }

    private func fetchPlanName(token: String) async {
        var request = URLRequest(url: loadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let paidTier = json["paidTier"] as? String, !paidTier.isEmpty {
            state.planName = paidTier
        } else if let currentTier = json["currentTier"] as? String, !currentTier.isEmpty {
            state.planName = currentTier
        }
    }
}
