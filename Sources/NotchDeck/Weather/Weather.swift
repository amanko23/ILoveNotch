// SPDX-License-Identifier: MIT
import CoreLocation
import Foundation
import Observation

/// One forecast from Open-Meteo: now, and the next few days.
public struct Forecast: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var date: String
        public var code: Int
        public var high: Double
        public var low: Double
        /// Percent, where the model gives one.
        public var rainChance: Int?
    }

    public var temperature: Double
    public var feelsLike: Double
    public var code: Int
    public var isDay: Bool
    public var days: [Day]
    public var fetched: Date
    /// Where it's for: a city, or nil when only coordinates are known.
    public var place: String?
    public var fahrenheit: Bool

    public var condition: WeatherCondition { WeatherCondition(code: code) }
    public var symbol: String { condition.symbol(day: isDay) }

    /// "21°".
    public static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    /// A day's short name: "Today", "Tue".
    public static func dayName(_ date: String, today: Date = .now) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        if Calendar.current.isDate(day, inSameDayAs: today) { return "Today" }
        return day.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// What the WMO weather code Open-Meteo reports means, in words and as an SF Symbol.
public struct WeatherCondition: Equatable, Sendable {
    public var code: Int

    public var text: String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81: "Showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm, hail"
        default: "—"
        }
    }

    public func symbol(day: Bool = true) -> String {
        switch code {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

/// Open-Meteo's free forecast API: no account and no key. Coordinates are rounded to a tenth of
/// a degree (about 10 km) before they leave the Mac.
enum OpenMeteo {
    /// Open-Meteo's snake_case keys, read with `convertFromSnakeCase`: `temperature_2m` is
    /// `temperature2m`.
    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature2m: Double
            var apparentTemperature: Double
            var weatherCode: Int
            var isDay: Int
        }

        struct Daily: Decodable {
            var time: [String]
            var weatherCode: [Int]
            var temperature2mMax: [Double]
            var temperature2mMin: [Double]
            var precipitationProbabilityMax: [Int?]?
        }

        var current: Current
        var daily: Daily
    }

    private struct Places: Decodable {
        struct Place: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
        }

        var results: [Place]?
    }

    static func forecastURL(latitude: Double, longitude: Double, fahrenheit: Bool) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.1f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.1f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        return components?.url
    }

    static func forecast(latitude: Double, longitude: Double, fahrenheit: Bool, place: String?) async throws
        -> Forecast
    {
        guard let url = forecastURL(latitude: latitude, longitude: longitude, fahrenheit: fahrenheit) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decodeForecast(data, place: place, fahrenheit: fahrenheit)
    }

    static func decodeForecast(_ data: Data, place: String?, fahrenheit: Bool, now: Date = .now) throws -> Forecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        let daily = response.daily
        let count = min(
            daily.time.count, daily.weatherCode.count, daily.temperature2mMax.count, daily.temperature2mMin.count)
        let rain = daily.precipitationProbabilityMax ?? []
        let days = (0..<count).map { index in
            Forecast.Day(
                date: daily.time[index], code: daily.weatherCode[index], high: daily.temperature2mMax[index],
                low: daily.temperature2mMin[index], rainChance: rain.indices.contains(index) ? rain[index] : nil)
        }
        let current = response.current
        return Forecast(
            temperature: current.temperature2m, feelsLike: current.apparentTemperature, code: current.weatherCode,
            isDay: current.isDay == 1, days: days, fetched: now, place: place, fahrenheit: fahrenheit)
    }

    /// Finds a city by name with Open-Meteo's geocoding API: its name, as found, and coordinates.
    static func place(named name: String) async throws -> (name: String, latitude: Double, longitude: Double)? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let found = try JSONDecoder().decode(Places.self, from: data).results?.first else { return nil }
        return (found.name, found.latitude, found.longitude)
    }
}

/// Where the weather is for: the Mac's location, asked for once through Core Location, or a city
/// the user typed in Settings.
@MainActor
@Observable
public final class WeatherModel: NSObject {
    public enum Status: Equatable, Sendable {
        case idle
        case locating
        case loading
        /// Location access is off and no city is set.
        case needsLocation
        case failed(String)
    }

    public private(set) var forecast: Forecast?
    public private(set) var status = Status.idle
    /// A city typed in Settings, used instead of the Mac's location.
    public var city: String {
        didSet {
            defaults.set(city, forKey: Key.city)
            cityCoordinates = nil
        }
    }
    /// nil follows the region's measurement system.
    public var prefersFahrenheit: Bool? {
        didSet { defaults.set(prefersFahrenheit, forKey: Key.fahrenheit) }  // nil removes it
    }

    /// How old a forecast may get before it's fetched again.
    static let freshness: TimeInterval = 30 * 60
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var manager: CLLocationManager?
    /// Kept while it looks up the city's name.
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var cityCoordinates: (name: String, latitude: Double, longitude: Double)?
    @ObservationIgnored private var lastLocation: (latitude: Double, longitude: Double)?
    @ObservationIgnored private var placeName: String?
    @ObservationIgnored private var fetching: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        city = defaults.string(forKey: Key.city) ?? ""
        prefersFahrenheit = defaults.object(forKey: Key.fahrenheit) as? Bool
        if let data = defaults.data(forKey: Key.cache) {
            forecast = try? JSONDecoder().decode(Forecast.self, from: data)
        }
        super.init()
    }

    public var fahrenheit: Bool { prefersFahrenheit ?? (Locale.current.measurementSystem == .us) }

    /// Whether the Mac's location is in use, rather than a typed city.
    public var usesLocation: Bool { city.trimmingCharacters(in: .whitespaces).isEmpty }

    public var locationAccess: CLAuthorizationStatus { (manager ?? CLLocationManager()).authorizationStatus }

    /// Fetches a forecast when the last one is old, for another place, or in other units.
    public func refreshIfStale(now: Date = .now) {
        guard let forecast, now.timeIntervalSince(forecast.fetched) < Self.freshness,
            forecast.fahrenheit == fahrenheit, status != .needsLocation
        else { return refresh() }
    }

    /// Fetches a forecast now.
    public func refresh() {
        guard fetching == nil else { return }
        if usesLocation { locate() } else { lookUpCity() }
    }

    // MARK: Where

    private func lookUpCity() {
        let name = city.trimmingCharacters(in: .whitespaces)
        if let found = cityCoordinates {
            return fetch(latitude: found.latitude, longitude: found.longitude, place: found.name)
        }
        status = .loading
        fetching = Task { [weak self] in
            let found = try? await OpenMeteo.place(named: name)
            guard let self else { return }
            self.fetching = nil
            guard let found else {
                self.status = .failed("Couldn't find \(name). Check the city in Settings › Home.")
                return
            }
            self.cityCoordinates = found
            self.fetch(latitude: found.latitude, longitude: found.longitude, place: found.name)
        }
    }

    private func locate() {
        let manager = self.manager ?? CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .needsLocation
        default:
            status = .locating
            manager.requestLocation()
        }
    }

    fileprivate func located(latitude: Double, longitude: Double) {
        lastLocation = (latitude, longitude)
        let place = CLLocation(latitude: latitude, longitude: longitude)
        // The city's name, for the label; the forecast doesn't wait for it.
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(place) { [weak self] placemarks, _ in
            let name = placemarks?.first?.locality
            guard let self else { return }
            Task { @MainActor in self.named(name) }
        }
        fetch(latitude: latitude, longitude: longitude, place: placeName)
    }

    private func named(_ name: String?) {
        guard let name, name != placeName else { return }
        placeName = name
        if var forecast, forecast.place != name {
            forecast.place = name
            self.forecast = forecast
            save(forecast)
        }
    }

    fileprivate func locationFailed(denied: Bool) {
        status = denied ? .needsLocation : .failed("Couldn't find your location. Try again, or type a city.")
    }

    fileprivate func accessChanged() {
        guard usesLocation, status == .locating || status == .needsLocation else { return }
        locate()
    }

    // MARK: The forecast

    private func fetch(latitude: Double, longitude: Double, place: String?) {
        status = .loading
        let fahrenheit = fahrenheit
        fetching?.cancel()
        fetching = Task { [weak self] in
            do {
                let forecast = try await OpenMeteo.forecast(
                    latitude: latitude, longitude: longitude, fahrenheit: fahrenheit, place: place)
                guard let self else { return }
                self.forecast = forecast
                self.status = .idle
                self.save(forecast)
            } catch {
                self?.status = .failed("Couldn't load the weather. Check your connection.")
            }
            self?.fetching = nil
        }
    }

    private func save(_ forecast: Forecast) {
        if let data = try? JSONEncoder().encode(forecast) { defaults.set(data, forKey: Key.cache) }
    }

    private enum Key {
        static let city = "weather.city"
        static let fahrenheit = "weather.fahrenheit"
        static let cache = "weather.forecast"
    }
}

extension WeatherModel: CLLocationManagerDelegate {
    // Core Location calls back on the thread that made the manager: the main one.
    public nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let coordinate = locations.last?.coordinate else { return }
        let (latitude, longitude) = (coordinate.latitude, coordinate.longitude)
        MainActor.assumeIsolated { located(latitude: latitude, longitude: longitude) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { locationFailed(denied: denied) }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { accessChanged() }
    }
}
