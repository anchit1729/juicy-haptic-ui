import Foundation

enum SlackError: LocalizedError {
    case invalidToken
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "Enter a Slack app token."
        case .service(let reason): reason
        }
    }
}

struct SlackSocketSource {
    func socketURL(appToken: String) async throws -> URL {
        guard !appToken.isEmpty else { throw SlackError.invalidToken }
        var request = URLRequest(url: URL(string: "https://slack.com/api/apps.connections.open")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(ConnectionResponse.self, from: data)
        guard result.ok, let address = result.url, let url = URL(string: address) else {
            throw SlackError.service(result.error ?? "Slack connection failed.")
        }
        return url
    }

    static func decode(_ data: Data) throws -> SlackEnvelope {
        try JSONDecoder().decode(SlackEnvelope.self, from: data)
    }

    static func acknowledgement(for envelope: SlackEnvelope) throws -> String? {
        guard let envelopeID = envelope.envelopeID else { return nil }
        let data = try JSONEncoder().encode(["envelope_id": envelopeID])
        return String(decoding: data, as: UTF8.self)
    }
}

private struct ConnectionResponse: Decodable {
    let ok: Bool
    let url: String?
    let error: String?
}

struct SlackEnvelope: Decodable {
    let envelopeID: String?
    let payload: SlackPayload?

    enum CodingKeys: String, CodingKey {
        case envelopeID = "envelope_id"
        case payload
    }

    func directMessage(allowedTeams: Set<String>, at now: Date = Date()) -> SourceEvent? {
        guard let payload,
              payload.type == "event_callback",
              let event = payload.event,
              event.type == "message",
              event.channelType == "im",
              event.subtype == nil,
              let team = payload.teamID,
              allowedTeams.isEmpty || allowedTeams.contains(team),
              let id = payload.eventID else { return nil }
        let time = event.timestamp.flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? now
        guard abs(now.timeIntervalSince(time)) < 300 else { return nil }
        return SourceEvent(id: "slack:\(id)", sourceID: "slack", kind: "directMessage", occurredAt: time)
    }
}

struct SlackPayload: Decodable {
    let type: String?
    let teamID: String?
    let eventID: String?
    let event: SlackMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case teamID = "team_id"
        case eventID = "event_id"
        case event
    }
}

struct SlackMessage: Decodable {
    let type: String?
    let channelType: String?
    let subtype: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type
        case channelType = "channel_type"
        case subtype
        case timestamp = "ts"
    }
}
