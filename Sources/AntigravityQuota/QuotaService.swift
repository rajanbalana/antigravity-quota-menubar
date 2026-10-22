import Foundation
import Combine

public struct AccountDefinition: Sendable {
    public let id: String
    public let defaultName: String
    public let keychainCandidates: [(service: String, account: String)]
    public let fileCandidates: [String]

    public init(
        id: String,
        defaultName: String,
        keychainCandidates: [(service: String, account: String)],
        fileCandidates: [String]
    ) {
        self.id = id
        self.defaultName = defaultName
        self.keychainCandidates = keychainCandidates
        self.fileCandidates = fileCandidates
    }
}

@MainActor
public final class QuotaService: ObservableObject {
    @Published public private(set) var state = QuotaState()
    @Published public var selectedTab: String = "all"

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

    private var cachedAccessTokens: [String: String] = [:]
    private var pollTimer: Timer? = nil

    private let accountDefinitions: [AccountDefinition] = [
        AccountDefinition(
            id: "account-1",
            defaultName: "Account 1",
            keychainCandidates: [
                (service: "gemini", account: "antigravity"),
                (service: "gemini", account: "antigravity-1"),
                (service: "gemini", account: "antigravity-primary")
            ],
            fileCandidates: [
                ".gemini/antigravity-cli/antigravity-oauth-token",
                ".gemini/oauth_creds.json",
                ".antigravity-accounts/account-1/.gemini/antigravity-cli/antigravity-oauth-token"
            ]
        ),
        AccountDefinition(
            id: "account-2",
            defaultName: "Account 2",
            keychainCandidates: [
                (service: "gemini", account: "antigravity-2"),
                (service: "gemini", account: "antigravity-account-2"),
                (service: "gemini-2", account: "antigravity"),
                (service: "gemini", account: "antigravity-acct2")
            ],
            fileCandidates: [
                ".antigravity-accounts/account-2/.gemini/antigravity-cli/antigravity-oauth-token",
                ".gemini/antigravity-cli-acct2/antigravity-oauth-token",
                ".gemini/antigravity-cli-2/antigravity-oauth-token",
                ".gemini/antigravity-oauth-token-2",
                ".gemini/antigravity-cli/antigravity-oauth-token-2",
                ".gemini/oauth_creds_2.json",
                ".gemini/oauth_creds-2.json"
            ]
        )
    ]

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
        state.globalErrorMessage = nil

        var updatedAccounts: [AccountQuotaState] = []

        for def in accountDefinitions {
            guard let creds = loadCredentials(for: def) else {
                continue
            }

            var acctState = AccountQuotaState(
                id: def.id,
                defaultName: def.defaultName,
                email: extractEmail(from: creds),
                isLoading: true
            )

            do {
                var accessToken = cachedAccessTokens[def.id]

                if accessToken == nil, let refreshToken = creds["refresh_token"] as? String {
                    accessToken = try await exchangeRefreshToken(refreshToken)
                    cachedAccessTokens[def.id] = accessToken
                } else if accessToken == nil, let initialToken = creds["access_token"] as? String {
                    accessToken = initialToken
                }

                guard let token = accessToken else {
                    throw NSError(domain: "AntigravityQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid token found in credentials"])
                }

                // Fetch Quota Summary
                do {
                    let buckets = try await fetchQuotaSummary(token: token)
                    acctState.gemini5h = buckets.gemini5h
                    acctState.geminiWeekly = buckets.geminiWeekly
                    acctState.thirdParty5h = buckets.thirdParty5h
                    acctState.thirdPartyWeekly = buckets.thirdPartyWeekly
                } catch let error as NSError where error.code == 401 {
                    // Token expired -> refresh and retry once
                    if let refreshToken = creds["refresh_token"] as? String {
                        let freshToken = try await exchangeRefreshToken(refreshToken)
                        cachedAccessTokens[def.id] = freshToken
                        let buckets = try await fetchQuotaSummary(token: freshToken)
                        acctState.gemini5h = buckets.gemini5h
                        acctState.geminiWeekly = buckets.geminiWeekly
                        acctState.thirdParty5h = buckets.thirdParty5h
                        acctState.thirdPartyWeekly = buckets.thirdPartyWeekly
                    } else {
                        throw error
                    }
                }

                // Optional: fetch plan name
                if let currentToken = cachedAccessTokens[def.id] ?? accessToken {
                    acctState.planName = await fetchPlanName(token: currentToken)
                }

                acctState.lastUpdated = Date()
                acctState.isLoading = false
            } catch {
                acctState.isLoading = false
                acctState.errorMessage = error.localizedDescription
            }

            updatedAccounts.append(acctState)
        }

        if updatedAccounts.isEmpty {
            state.globalErrorMessage = "Antigravity credentials not found in Keychain or ~/.gemini"
        }

        state.accounts = updatedAccounts
        state.lastUpdated = Date()
        state.isLoading = false
    }

    private func loadCredentials(for def: AccountDefinition) -> [String: Any]? {
        // 1. Try Keychain candidates
        for candidate in def.keychainCandidates {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-w", "-s", candidate.service, "-a", candidate.account]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
                    if let credData = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: credData) as? [String: Any] {
                        return normalizeCredentials(json)
                    }
                }
            }
        }

        // 2. Try file paths
        let home = FileManager.default.homeDirectoryForCurrentUser
        for relativePath in def.fileCandidates {
            let path = home.appendingPathComponent(relativePath)
            if let fileData = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] {
                return normalizeCredentials(json)
            }
        }

        return nil
    }

    private func normalizeCredentials(_ json: [String: Any]) -> [String: Any] {
        var credsDict: [String: Any] = [:]
        if let tokenDict = json["token"] as? [String: Any] {
            credsDict = tokenDict
        } else {
            credsDict = json
        }
        if let idToken = json["id_token"] as? String, credsDict["id_token"] == nil {
            credsDict["id_token"] = idToken
        }
        if let email = json["email"] as? String, credsDict["email"] == nil {
            credsDict["email"] = email
        }
        return credsDict
    }

    private func extractEmail(from creds: [String: Any]) -> String? {
        if let email = creds["email"] as? String, !email.isEmpty {
            return email
        }
        guard let idToken = creds["id_token"] as? String else { return nil }
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        return email
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

    private func fetchQuotaSummary(token: String) async throws -> (gemini5h: QuotaBucket?, geminiWeekly: QuotaBucket?, thirdParty5h: QuotaBucket?, thirdPartyWeekly: QuotaBucket?) {
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil, nil)
        }
        return parseQuotaSummary(json)
    }

    private func parseQuotaSummary(_ json: [String: Any]) -> (gemini5h: QuotaBucket?, geminiWeekly: QuotaBucket?, thirdParty5h: QuotaBucket?, thirdPartyWeekly: QuotaBucket?) {
        guard let groups = json["groups"] as? [[String: Any]] else { return (nil, nil, nil, nil) }
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

        return (gemini5h, geminiWeekly, thirdParty5h, thirdPartyWeekly)
    }

    private func fetchPlanName(token: String) async -> String? {
        var request = URLRequest(url: loadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let paidTier = json["paidTier"] as? String, !paidTier.isEmpty {
            return paidTier
        } else if let currentTier = json["currentTier"] as? String, !currentTier.isEmpty {
            return currentTier
        }
        return nil
    }
}