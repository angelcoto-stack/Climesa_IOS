import Foundation

/// Protocolo Phoenix de Supabase Realtime (vsn 1.0.0, JSON). Código puro para probarlo sin red.
/// Equivale a web/src/lib/live.ts y a domain/Realtime.kt de Android.
public enum RealtimeProtocol {
    private static let prefix = "realtime:"
    public static let publicChannel = "publico"

    public static func topic(_ channel: String) -> String { prefix + channel }

    public static func websocketURL(supabaseURL: String, publishableKey: String) -> String {
        var base = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") { base = "wss://" + String(base.dropFirst(8)) }
        else if base.hasPrefix("http://") { base = "ws://" + String(base.dropFirst(7)) }
        return "\(base)/realtime/v1/websocket?apikey=\(publishableKey)&vsn=1.0.0"
    }

    /// Ruta de la consulta de recuperación tras una caída (una sola por reconexión).
    public static func catchUpPath(after cursor: String) -> String {
        let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "0"
        return "/eventos?after=\(encoded)"
    }

    /// Los canales distintos de `publico` son privados y exigen el token de la sesión.
    public static func join(channel: String, ref: String, accessToken: String) -> String {
        let config: [String: Any] = [
            "broadcast": ["ack": false, "self": false] as [String: Any],
            "presence": ["key": ""] as [String: Any],
            "postgres_changes": [Any](),
            "private": channel != publicChannel
        ]
        let payload: [String: Any] = ["config": config, "access_token": accessToken]
        return frame(topic: topic(channel), event: "phx_join", payload: payload, ref: ref, joinRef: ref)
    }

    /// Latido del protocolo para mantener abierto el socket; no consulta datos.
    public static func heartbeat(ref: String) -> String {
        frame(topic: "phoenix", event: "heartbeat", payload: [String: Any](), ref: ref, joinRef: nil)
    }

    private static func frame(topic: String, event: String, payload: [String: Any], ref: String, joinRef: String?) -> String {
        var object: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": ref]
        if let joinRef { object["join_ref"] = joinRef }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    public static func parse(_ text: String) -> RealtimeFrame {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let topic = root["topic"] as? String,
              topic.hasPrefix(prefix) else { return .ignored }
        let channel = String(topic.dropFirst(prefix.count))
        let payload = root["payload"] as? [String: Any]
        switch (root["event"] as? String) ?? "" {
        case "phx_reply":
            return .joinReply(channel: channel, ok: (payload?["status"] as? String) == "ok")
        case "phx_close", "phx_error":
            return .channelClosed(channel: channel)
        case "broadcast":
            guard let body = payload?["payload"] as? [String: Any] else { return .ignored }
            let declared = ((body["tipo"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let type = declared.isEmpty ? ((payload?["event"] as? String) ?? "") : declared
            if type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .ignored }
            return .broadcast(channel: channel, event: makeEvent(type: type, entity: body["entidad"], id: body["id"], version: body["version"]))
        default:
            return .ignored
        }
    }

    /// Interpreta la respuesta de `GET /eventos?after=<seq>`. Devuelve nil si no es un objeto JSON.
    public static func parseCatchUp(data: Data) -> CatchUp? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let rows = (root["events"] as? [Any]) ?? []
        let events: [DomainEvent] = rows.compactMap { row in
            guard let item = row as? [String: Any] else { return nil }
            return makeEvent(type: item["type"], entity: item["entity"], id: item["id"], version: item["version"])
        }
        let cursor = stringValue(root["cursor"])
        return CatchUp(cursor: cursor.isEmpty ? "0" : cursor, events: events)
    }

    private static func makeEvent(type: Any?, entity: Any?, id: Any?, version: Any?) -> DomainEvent {
        DomainEvent(type: stringValue(type), entity: stringValue(entity), id: stringValue(id), version: number(version))
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    private static func number(_ value: Any?) -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}
