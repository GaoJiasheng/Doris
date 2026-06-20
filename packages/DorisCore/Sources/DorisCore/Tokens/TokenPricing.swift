#if os(macOS)

import Foundation

/// USD price per **million** tokens for a model, split by token kind.
public struct ModelRate: Sendable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double
    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

/// Best-effort cost estimation. Public list prices change often and plans
/// differ, so these are *defaults* — the settings layer can override per
/// model. Matching is by lowercased substring of the model id, longest
/// (most specific) pattern first.
public enum TokenPricing {
    /// User/settings overrides keyed by the same substring patterns.
    public static var overrides: [String: ModelRate] = [:]

    /// (pattern, rate) — order matters: first match on a longest-first scan wins.
    private static let table: [(String, ModelRate)] = [
        // Anthropic Claude
        ("claude-opus",   ModelRate(input: 15,   output: 75,  cacheWrite: 18.75, cacheRead: 1.5)),
        ("opus",          ModelRate(input: 15,   output: 75,  cacheWrite: 18.75, cacheRead: 1.5)),
        ("claude-sonnet", ModelRate(input: 3,    output: 15,  cacheWrite: 3.75,  cacheRead: 0.30)),
        ("sonnet",        ModelRate(input: 3,    output: 15,  cacheWrite: 3.75,  cacheRead: 0.30)),
        ("claude-haiku",  ModelRate(input: 0.80, output: 4,   cacheWrite: 1.0,   cacheRead: 0.08)),
        ("haiku",         ModelRate(input: 0.80, output: 4,   cacheWrite: 1.0,   cacheRead: 0.08)),
        // OpenAI
        ("gpt-4o-mini",   ModelRate(input: 0.15, output: 0.60, cacheWrite: 0,    cacheRead: 0.075)),
        ("gpt-4o",        ModelRate(input: 2.5,  output: 10,   cacheWrite: 0,    cacheRead: 1.25)),
        ("gpt-4.1",       ModelRate(input: 2.0,  output: 8,    cacheWrite: 0,    cacheRead: 0.5)),
        ("o3",            ModelRate(input: 2.0,  output: 8,    cacheWrite: 0,    cacheRead: 0.5)),
        ("o1",            ModelRate(input: 15,   output: 60,   cacheWrite: 0,    cacheRead: 7.5)),
        ("gpt-5",         ModelRate(input: 1.25, output: 10,   cacheWrite: 0,    cacheRead: 0.125)),
        ("gpt",           ModelRate(input: 2.5,  output: 10,   cacheWrite: 0,    cacheRead: 1.25)),
        ("codex",         ModelRate(input: 1.25, output: 10,   cacheWrite: 0,    cacheRead: 0.125)),
        // Google Gemini
        ("gemini-2.5-pro",   ModelRate(input: 1.25, output: 10,  cacheWrite: 0, cacheRead: 0.31)),
        ("gemini-2.5-flash", ModelRate(input: 0.30, output: 2.5, cacheWrite: 0, cacheRead: 0.075)),
        ("gemini-flash",     ModelRate(input: 0.30, output: 2.5, cacheWrite: 0, cacheRead: 0.075)),
        ("gemini",           ModelRate(input: 1.25, output: 10,  cacheWrite: 0, cacheRead: 0.31)),
    ]

    public static func rate(for model: String) -> ModelRate? {
        let m = model.lowercased()
        // Overrides win, longest pattern first.
        for (pat, rate) in overrides.sorted(by: { $0.key.count > $1.key.count }) where m.contains(pat) {
            return rate
        }
        for (pat, rate) in table.sorted(by: { $0.0.count > $1.0.count }) where m.contains(pat) {
            return rate
        }
        return nil
    }

    /// Cost in USD. Reasoning tokens (o-series / Codex) bill at the output
    /// rate. Unknown models → 0 (shown as "—" in the UI, tokens still count).
    public static func cost(model: String, input: Int, output: Int,
                            cacheCreate: Int, cacheRead: Int, reasoning: Int) -> Double {
        guard let r = rate(for: model) else { return 0 }
        let perM = 1_000_000.0
        return Double(input)       * r.input      / perM
             + Double(output + reasoning) * r.output / perM
             + Double(cacheCreate)  * r.cacheWrite / perM
             + Double(cacheRead)    * r.cacheRead  / perM
    }
}

#endif
