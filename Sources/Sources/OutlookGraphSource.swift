import Foundation

struct MicrosoftDeviceCode: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct MicrosoftToken: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthResponseError: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum OutlookError: LocalizedError {
    case invalidClientID
    case service(String)
    case signInExpired

    var errorDescription: String? {
        switch self {
        case .invalidClientID: "Enter a Microsoft app client ID."
        case .service(let reason): reason
        case .signInExpired: "The sign-in code expired."
        }
    }
}

struct OutlookGraphSource {
    private let identityBase = "https://login.microsoftonline.com/common/oauth2/v2.0"

    func beginSignIn(clientID: String) async throws -> MicrosoftDeviceCode {
        guard !clientID.isEmpty else { throw OutlookError.invalidClientID }
        let (data, response) = try await postForm(
            "\(identityBase)/devicecode",
            ["client_id": clientID, "scope": "offline_access Mail.ReadBasic User.Read"]
        )
        guard response.statusCode == 200 else { throw serviceError(data) }
        return try JSONDecoder().decode(MicrosoftDeviceCode.self, from: data)
    }

    func finishSignIn(clientID: String, code: MicrosoftDeviceCode) async throws -> MicrosoftToken {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = max(5, code.interval)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let (data, response) = try await postForm(
                "\(identityBase)/token",
                [
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": clientID,
                    "device_code": code.deviceCode
                ]
            )
            if response.statusCode == 200 {
                return try JSONDecoder().decode(MicrosoftToken.self, from: data)
            }
            let error = try? JSONDecoder().decode(OAuthResponseError.self, from: data)
            switch error?.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw serviceError(data)
            }
        }
        throw OutlookError.signInExpired
    }

    func refresh(clientID: String, refreshToken: String) async throws -> MicrosoftToken {
        let (data, response) = try await postForm(
            "\(identityBase)/token",
            [
                "grant_type": "refresh_token",
                "client_id": clientID,
                "refresh_token": refreshToken,
                "scope": "offline_access Mail.ReadBasic User.Read"
            ]
        )
        guard response.statusCode == 200 else { throw serviceError(data) }
        return try JSONDecoder().decode(MicrosoftToken.self, from: data)
    }

    func fetchInbox(accessToken: String) async throws -> OutlookInbox {
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages")!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "id,receivedDateTime,isRead"),
            URLQueryItem(name: "$top", value: "20"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc")
        ]
        async let messages = get(components.url!, accessToken: accessToken)
        async let folder = get(URL(string: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox?$select=unreadItemCount")!, accessToken: accessToken)
        return try Self.decodeInbox(messages: await messages, folder: await folder)
    }

    static func decodeInbox(messages: Data, folder: Data) throws -> OutlookInbox {
        let list = try JSONDecoder().decode(MessageList.self, from: messages)
        let count = try JSONDecoder().decode(Folder.self, from: folder)
        return OutlookInbox(messages: list.value, unreadCount: count.unreadItemCount)
    }

    private func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw serviceError(data) }
        return data
    }

    private func postForm(_ url: String, _ fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OutlookError.service("No response from Microsoft.") }
        return (data, http)
    }

    private func serviceError(_ data: Data) -> OutlookError {
        let result = try? JSONDecoder().decode(OAuthResponseError.self, from: data)
        return .service(result?.errorDescription ?? result?.error ?? "Microsoft request failed.")
    }
}

struct OutlookInbox: Sendable {
    let messages: [OutlookMessage]
    let unreadCount: Int
}

struct OutlookMessage: Decodable, Sendable {
    let id: String
    let receivedDateTime: String
    let isRead: Bool
}

private struct MessageList: Decodable {
    let value: [OutlookMessage]
}

private struct Folder: Decodable {
    let unreadItemCount: Int
}

struct OutlookInboxTracker {
    private var initialized = false
    private var seenIDs = Set<String>()
    private var latestReceivedAt = Date.distantPast

    mutating func newEvents(from inbox: OutlookInbox, at now: Date = Date()) -> [SourceEvent] {
        let messages = inbox.messages.sorted { $0.receivedDateTime < $1.receivedDateTime }
        defer { initialized = true }
        var events: [SourceEvent] = []
        for message in messages {
            guard let received = Self.parseDate(message.receivedDateTime) else { continue }
            if initialized && received >= latestReceivedAt && !seenIDs.contains(message.id) {
                events.append(SourceEvent(id: "outlook:\(message.id)", sourceID: "outlook", kind: "newEmail", occurredAt: received))
            }
            latestReceivedAt = max(latestReceivedAt, received)
            seenIDs.insert(message.id)
        }
        if seenIDs.count > 1_000 {
            seenIDs = Set(messages.map(\.id))
        }
        return events.filter { now.timeIntervalSince($0.occurredAt) < 300 }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
