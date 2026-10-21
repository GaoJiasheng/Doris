import Foundation
import SwiftUI
import Combine

/// One-shot snapshot of "what's the weather where the user is right now."
public struct WeatherSnapshot: Equatable {
    public var temperatureC: Double
    public var weatherCode: Int
    public var symbolName: String
    public var isDay: Bool
    public var windSpeedKmh: Double
    public var windDirectionDeg: Double
    public var uvIndex: Double
    public var precipitationProbability: Double
    public var locationName: String
    public var fetchedAt: Date
}

/// Pulls the user's location (IP-based, no permission prompt) and the current
/// weather for that location from Open-Meteo. Refreshes every 10 minutes
/// in the background.
///
/// **Singleton** — there's exactly one weather state for the whole app.
/// Previously each view showing weather owned its own `@StateObject`
/// `WeatherViewModel`, and every panel open created a fresh one — a
/// network round-trip per open. Now opens just observe the shared instance — the
/// background timer is the only thing that fetches.
@MainActor
public final class WeatherViewModel: ObservableObject {
    public static let shared = WeatherViewModel()

    @Published public private(set) var snapshot: WeatherSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: String?

    /// How often the background loop refetches. 10 min is plenty for an
    /// ambient weather pill — current conditions don't move that fast,
    /// and the IP-based location lookup + Open-Meteo API both have
    /// rate-limit hygiene we should respect.
    private static let refreshInterval: TimeInterval = 10 * 60

    private var refreshTask: Task<Void, Never>?

    private init() {}

    public func start() {
        // Idempotent — multiple `start()` calls (e.g. from each
        // weather card's onAppear) do nothing once the loop is already
        // running. The first call kicks off the perpetual refresh task;
        // subsequent calls are no-ops.
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refresh() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let location = await fetchLocation()
            let weather = try await fetchWeather(at: location)
            snapshot = WeatherSnapshot(
                temperatureC: weather.temperatureC,
                weatherCode: weather.code,
                symbolName: WeatherCode.symbol(for: weather.code, isDay: weather.isDay),
                isDay: weather.isDay,
                windSpeedKmh: weather.windSpeedKmh,
                windDirectionDeg: weather.windDirectionDeg,
                uvIndex: weather.uvIndex,
                precipitationProbability: weather.precipitationProbability,
                locationName: location.shortName,
                fetchedAt: Date()
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Location

    private struct Location {
        var latitude: Double
        var longitude: Double
        var shortName: String
    }

    /// IP-based geolocation. On any failure (network, blocked, malformed
    /// response, missing fields) we fall back to Singapore so the bubble
    /// still has something to show.
    private static var singaporeFallback: Location {
        Location(latitude: 1.3521, longitude: 103.8198,
                 shortName: L("Singapore", "新加坡"))
    }

    private func fetchLocation() async -> Location {
        let url = URL(string: "https://ipapi.co/json/")!
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("doris/0.2", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(IPAPIResponse.self, from: data)
            guard let lat = decoded.latitude, let lon = decoded.longitude else {
                return Self.singaporeFallback
            }
            let parts = [decoded.city, decoded.region_code ?? decoded.country_code]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let name = parts.isEmpty ? "—" : parts.joined(separator: ", ")
            return Location(latitude: lat, longitude: lon, shortName: name)
        } catch {
            return Self.singaporeFallback
        }
    }

    private struct IPAPIResponse: Decodable {
        let city: String?
        let region_code: String?
        let country_code: String?
        let latitude: Double?
        let longitude: Double?
    }

    // MARK: - Weather

    private struct OMResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double?
            let wind_direction_10m: Double?
            let uv_index: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let precipitation_probability: [Double?]?
        }
        let current: Current
        let hourly: Hourly?
    }

    private struct WeatherFetch {
        var temperatureC: Double
        var code: Int
        var isDay: Bool
        var windSpeedKmh: Double
        var windDirectionDeg: Double
        var uvIndex: Double
        var precipitationProbability: Double
    }

    private func fetchWeather(at loc: Location) async throws -> WeatherFetch {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(loc.latitude)),
            .init(name: "longitude", value: String(loc.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m,uv_index"),
            .init(name: "hourly", value: "precipitation_probability"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "wind_speed_unit", value: "kmh"),
            .init(name: "timezone", value: "auto"),
        ]
        var req = URLRequest(url: c.url!, timeoutInterval: 8)
        req.setValue("doris/0.2", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = try JSONDecoder().decode(OMResponse.self, from: data)

        // Pick the hourly precipitation_probability bucket that contains the
        // "current" timestamp. Open-Meteo's `current.time` is rounded to the
        // 15-minute mark (e.g. "...T11:30") whereas `hourly.time[i]` is the
        // top of each hour ("...T11:00"), so we match on the YYYY-MM-DDTHH
        // prefix (first 13 chars) — that's the bucket the current observation
        // falls in.
        var rainChance: Double = 0
        let hourPrefix = String(r.current.time.prefix(13))
        if let hourly = r.hourly,
           let probs = hourly.precipitation_probability,
           let idx = hourly.time.firstIndex(where: { $0.hasPrefix(hourPrefix) }),
           idx < probs.count,
           let p = probs[idx] {
            rainChance = p
        }

        // Sanity floor: if the *observed* condition is some form of
        // precipitation (drizzle / rain / snow / showers / thunderstorm) but
        // the model still has a 0% bucket, surface a non-zero number so the
        // UI doesn't lie about the obvious. The forecast bucket is
        // authoritative when it agrees with reality.
        let isPrecipitatingNow: Bool = {
            switch r.current.weather_code {
            case 51...57, 61...67, 71...77, 80...86, 95, 96, 99: return true
            default: return false
            }
        }()
        if isPrecipitatingNow && rainChance < 60 {
            rainChance = 100
        }

        return WeatherFetch(
            temperatureC: r.current.temperature_2m,
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            windSpeedKmh: r.current.wind_speed_10m ?? 0,
            windDirectionDeg: r.current.wind_direction_10m ?? 0,
            uvIndex: r.current.uv_index ?? 0,
            precipitationProbability: rainChance
        )
    }
}

// MARK: - Wind / UV helpers

public enum WindScale {
    /// Beaufort label for a km/h wind speed.
    @MainActor public
    static func beaufort(_ kmh: Double) -> String {
        switch kmh {
        case ..<1:    return L("Calm",          "无风")
        case ..<6:    return L("Light air",     "软风")
        case ..<12:   return L("Light breeze",  "轻风")
        case ..<20:   return L("Gentle breeze", "微风")
        case ..<29:   return L("Moderate",      "和风")
        case ..<39:   return L("Fresh",         "清风")
        case ..<50:   return L("Strong",        "强风")
        case ..<62:   return L("Near gale",     "疾风")
        case ..<75:   return L("Gale",          "大风")
        case ..<89:   return L("Strong gale",   "烈风")
        case ..<103:  return L("Storm",         "狂风")
        default:      return L("Hurricane",     "飓风")
        }
    }

    /// Compass abbreviation for a meteorological "from" direction in degrees.
    @MainActor public
    static func compass(_ deg: Double) -> String {
        let d = ((deg.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let en = ["N","NE","E","SE","S","SW","W","NW"]
        let zh = ["北","东北","东","东南","南","西南","西","西北"]
        let idx = Int((d + 22.5) / 45) % 8
        return L(en[idx], zh[idx])
    }
}

public enum UVScale {
    @MainActor public
    static func label(_ uv: Double) -> String {
        switch uv {
        case ..<3:   return L("Low",       "低")
        case ..<6:   return L("Moderate",  "中等")
        case ..<8:   return L("High",      "高")
        case ..<11:  return L("Very High", "很高")
        default:     return L("Extreme",   "极高")
        }
    }

    public static func tint(_ uv: Double) -> Color {
        switch uv {
        case ..<3:   return Color(red: 0.30, green: 0.85, blue: 0.55)   // green
        case ..<6:   return Color(red: 1.00, green: 0.85, blue: 0.30)   // yellow
        case ..<8:   return Color(red: 1.00, green: 0.55, blue: 0.20)   // orange
        case ..<11:  return Color(red: 1.00, green: 0.30, blue: 0.30)   // red
        default:     return Color(red: 0.85, green: 0.30, blue: 0.85)   // violet
        }
    }
}

public enum RainScale {
    @MainActor public
    static func label(_ pct: Double) -> String {
        switch pct {
        case ..<20:  return L("Unlikely",    "几乎不会")
        case ..<50:  return L("Possible",    "可能")
        case ..<80:  return L("Likely",      "很有可能")
        default:     return L("Very likely", "非常可能")
        }
    }

    public static func tint(_ pct: Double) -> Color {
        let cyan = Color(red: 0.0, green: 0.85, blue: 1.0)
        switch pct {
        case ..<20:  return cyan.opacity(0.55)
        case ..<50:  return cyan.opacity(0.85)
        case ..<80:  return Color(red: 0.30, green: 0.65, blue: 1.0)
        default:     return Color(red: 0.55, green: 0.45, blue: 1.0)
        }
    }
}

/// Maps Open-Meteo's WMO weather codes to short labels + SF Symbols.
public enum WeatherCode {
    /// Localized condition text. Resolved at view-time so language toggling updates live.
    @MainActor public
    static func text(for code: Int) -> String {
        switch code {
        case 0:           return L("Clear",            "晴")
        case 1:           return L("Mostly Clear",     "晴间多云")
        case 2:           return L("Partly Cloudy",    "局部多云")
        case 3:           return L("Overcast",         "阴")
        case 45, 48:      return L("Fog",              "雾")
        case 51, 53, 55:  return L("Drizzle",          "毛毛雨")
        case 56, 57:      return L("Freezing Drizzle", "冻毛毛雨")
        case 61, 63, 65:  return L("Rain",             "雨")
        case 66, 67:      return L("Freezing Rain",    "冻雨")
        case 71, 73, 75:  return L("Snow",             "雪")
        case 77:          return L("Snow Grains",      "米雪")
        case 80, 81, 82:  return L("Rain Showers",     "阵雨")
        case 85, 86:      return L("Snow Showers",     "阵雪")
        case 95:          return L("Thunderstorm",     "雷暴")
        case 96, 99:      return L("Thunderstorm",     "雷暴")
        default:          return "—"
        }
    }

    public static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0:        return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1:        return isDay ? "sun.max.fill" : "moon.fill"
        case 2:        return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:        return "cloud.fill"
        case 45, 48:   return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57:   return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67:   return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77:       return "snowflake"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86:   return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default:       return "questionmark"
        }
    }
}
