import Foundation

/// Decodes CodexBar CLI `usage --format json` output into domain snapshots.
///
/// Two rules dominate:
/// 1. `usage.primary/secondary/tertiary` are **positional** fields, not period
///    names. The window kind is derived from `windowMinutes`, never from the
///    field name — so a source that reorders them still decodes correctly.
/// 2. An out-of-range or non-finite `usedPercent` marks the window
///    `unavailable`; it is never silently clamped to 0/100.
public enum CodexBarUsageDecoder {
    public static let engineId = "codexbar"

    public enum DecodeError: Error, Equatable {
        case notAnArray
        case empty
        case providerNotFound(String)
    }

    /// Decodes the whole CLI payload and returns the snapshot for one provider.
    public static func decode(_ data: Data, provider: String, now: Date = Date()) throws -> ProviderQuotaSnapshot {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let array = root as? [[String: Any]] else { throw DecodeError.notAnArray }
        guard !array.isEmpty else { throw DecodeError.empty }
        guard let entry = array.first(where: { ($0["provider"] as? String) == provider }) else {
            throw DecodeError.providerNotFound(provider)
        }
        return snapshot(from: entry, provider: provider, now: now)
    }

    /// Decodes every provider present in the payload.
    public static func decodeAll(_ data: Data, now: Date = Date()) throws -> [ProviderQuotaSnapshot] {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let array = root as? [[String: Any]] else { throw DecodeError.notAnArray }
        return array.compactMap { entry in
            guard let provider = entry["provider"] as? String else { return nil }
            return snapshot(from: entry, provider: provider, now: now)
        }
    }

    static func snapshot(from entry: [String: Any], provider: String, now: Date) -> ProviderQuotaSnapshot {
        // An `error` object means the provider could not be read (e.g. not
        // logged in). That is a distinct state, not an empty quota.
        if let error = entry["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? ""
            let availability: DataAvailability =
                message.localizedCaseInsensitiveContains("session")
                || message.localizedCaseInsensitiveContains("login")
                || message.localizedCaseInsensitiveContains("cookie")
                ? .unauthenticated : .unavailable
            return ProviderQuotaSnapshot(
                id: "\(provider):default", providerId: provider, accountKey: nil,
                sourceEngineId: engineId, windows: [], fetchedAt: now,
                availability: availability, diagnosticCode: "provider_error"
            )
        }

        let usage = entry["usage"] as? [String: Any] ?? [:]
        let pace = entry["pace"] as? [String: Any] ?? [:]
        let accountKey = (usage["identity"] as? [String: Any])?["accountEmail"] as? String

        var windows: [QuotaWindow] = []
        for (position, key) in ["primary", "secondary", "tertiary"].enumerated() {
            guard let raw = usage[key] as? [String: Any] else { continue }
            let paceEntry = pace[key] as? [String: Any]
            windows.append(window(from: raw, pace: paceEntry, position: position))
        }

        let availability: DataAvailability = windows.contains { $0.availability == .valid }
            ? .valid
            : (windows.isEmpty ? .unavailable : .stale)

        return ProviderQuotaSnapshot(
            id: "\(provider):\(accountKey ?? "default")",
            providerId: provider,
            accountKey: accountKey,
            sourceEngineId: engineId,
            windows: windows,
            fetchedAt: now,
            availability: availability
        )
    }

    static func window(from raw: [String: Any], pace: [String: Any]?, position: Int) -> QuotaWindow {
        let windowMinutes = raw["windowMinutes"] as? Int
        let kind = QuotaWindow.kind(forWindowMinutes: windowMinutes)
        let durationSeconds = windowMinutes.map { TimeInterval($0 * 60) }
        let resetAt = (raw["resetsAt"] as? String).flatMap(parseDate)

        let usedPercent = numeric(raw["usedPercent"])
        let remaining = remainingFraction(fromUsedPercent: usedPercent)
        let availability: DataAvailability = remaining == nil ? .unavailable : .valid

        let expectedUsed = numeric(pace?["expectedUsedPercent"])
        let expectedRemaining = expectedUsed.flatMap { used -> Double? in
            guard used.isFinite, (0...100).contains(used) else { return nil }
            return 1 - used / 100
        }

        let label: String
        switch kind {
        case .session: label = "5h"
        case .weekly: label = "Weekly"
        case .monthly: label = "Monthly"
        case .custom: label = windowMinutes.map { "\($0)m" } ?? "Window"
        }

        return QuotaWindow(
            id: "\(kind.rawValue)-\(position)",
            label: label,
            kind: kind,
            durationSeconds: durationSeconds,
            remainingFraction: remaining,
            resetAt: resetAt,
            expectedRemainingFraction: expectedRemaining,
            updatedAt: (raw["updatedAt"] as? String).flatMap(parseDate),
            availability: availability
        )
    }

    /// Converts `usedPercent` to a remaining fraction. Returns nil (never a
    /// clamped value) when the input is missing, non-finite, or out of 0...100.
    static func remainingFraction(fromUsedPercent usedPercent: Double?) -> Double? {
        guard let usedPercent, usedPercent.isFinite, (0...100).contains(usedPercent) else {
            return nil
        }
        return (100 - usedPercent) / 100
    }

    /// JSONSerialization yields `NSNumber`; a JSON `NaN` would arrive as a
    /// non-finite Double and is rejected by the caller's range check.
    private static func numeric(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}