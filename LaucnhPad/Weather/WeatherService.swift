import Foundation
import Combine
import CoreLocation
import AppKit

// MARK: - Modèles de Données Météo en Temps Réel

enum WeatherLocationMode: String, Sendable {
    case auto
    case manual
}

struct WeatherHourlyPoint: Codable, Equatable, Sendable {
    let time: String
    let temp: Int
    let symbol: String
}

struct WeatherDailyPoint: Codable, Equatable, Sendable {
    let isoDate: String
    let symbol: String
    let low: Int
    let high: Int
}

struct LiveWeatherSnapshot: Codable, Equatable, Sendable {
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let unit: String // "C" ou "F"
    let temp: Int
    let feelsLike: Int
    let high: Int
    let low: Int
    let condition: String // "sunny", "clear", "cloudy", "rainy", "snowy", "stormy"
    let humidity: Int
    let windSpeedValue: Int
    let precipProb: Int
    let uvIndex: Int
    let sunrise: String
    let sunset: String
    let isDay: Bool
    let hourly: [WeatherHourlyPoint]
    let daily: [WeatherDailyPoint]
    let updatedAt: Date
    let isAutoDetected: Bool
    let isPreciseLocation: Bool
}

struct WeatherCitySearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let region: String?
    let country: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double

    var subtitle: String {
        [region, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(name) != .orderedSame }
            .joined(separator: ", ")
    }

    static let popularCities: [WeatherCitySearchResult] = [
        WeatherCitySearchResult(id: "paris", name: "Paris", region: "Île-de-France", country: "France", countryCode: "FR", latitude: 48.8534, longitude: 2.3488),
        WeatherCitySearchResult(id: "lyon", name: "Lyon", region: "Auvergne-Rhône-Alpes", country: "France", countryCode: "FR", latitude: 45.7485, longitude: 4.8467),
        WeatherCitySearchResult(id: "marseille", name: "Marseille", region: "Provence-Alpes-Côte d'Azur", country: "France", countryCode: "FR", latitude: 43.2970, longitude: 5.3811),
        WeatherCitySearchResult(id: "toulouse", name: "Toulouse", region: "Occitanie", country: "France", countryCode: "FR", latitude: 43.6043, longitude: 1.4437),
        WeatherCitySearchResult(id: "nice", name: "Nice", region: "Provence-Alpes-Côte d'Azur", country: "France", countryCode: "FR", latitude: 43.7031, longitude: 7.2661),
        WeatherCitySearchResult(id: "bruxelles", name: "Bruxelles", region: "Région de Bruxelles-Capitale", country: "Belgique", countryCode: "BE", latitude: 50.8505, longitude: 4.3488),
        WeatherCitySearchResult(id: "geneve", name: "Genève", region: "Genève", country: "Suisse", countryCode: "CH", latitude: 46.2022, longitude: 6.1457),
        WeatherCitySearchResult(id: "montreal", name: "Montréal", region: "Québec", country: "Canada", countryCode: "CA", latitude: 45.5088, longitude: -73.5878),
        WeatherCitySearchResult(id: "london", name: "London", region: "England", country: "United Kingdom", countryCode: "GB", latitude: 51.5085, longitude: -0.1257),
        WeatherCitySearchResult(id: "new-york", name: "New York", region: "New York", country: "United States", countryCode: "US", latitude: 40.7143, longitude: -74.0060),
        WeatherCitySearchResult(id: "madrid", name: "Madrid", region: "Madrid", country: "España", countryCode: "ES", latitude: 40.4165, longitude: -3.7026),
        WeatherCitySearchResult(id: "berlin", name: "Berlin", region: "Berlin", country: "Deutschland", countryCode: "DE", latitude: 52.5244, longitude: 13.4105),
        WeatherCitySearchResult(id: "roma", name: "Roma", region: "Lazio", country: "Italia", countryCode: "IT", latitude: 41.8919, longitude: 12.5113),
        WeatherCitySearchResult(id: "lisboa", name: "Lisboa", region: "Lisboa", country: "Portugal", countryCode: "PT", latitude: 38.7167, longitude: -9.1333),
        WeatherCitySearchResult(id: "tokyo", name: "Tokyo", region: "Tokyo", country: "Japan", countryCode: "JP", latitude: 35.6895, longitude: 139.6917)
    ]
}

// MARK: - Service Centralisé Météo & Localisation

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    @Published private(set) var locationMode: WeatherLocationMode
    @Published private(set) var activeCity: String
    @Published private(set) var activeCountry: String
    @Published private(set) var unit: String
    @Published private(set) var snapshot: LiveWeatherSnapshot?
    @Published private(set) var isDetectingLocation: Bool = false
    @Published private(set) var isFetchingWeather: Bool = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isPreciseLocation: Bool = false

    private var savedLatitude: Double?
    private var savedLongitude: Double?
    private let clManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastAutoLocateAttempt: Date = .distantPast
    private var inFlightWeatherTask: Task<Void, Never>?
    private var inFlightLocationTask: Task<Void, Never>?

    private var isHeadlessTestRun: Bool {
        ProcessInfo.processInfo.arguments.dropFirst().contains(where: { $0.hasPrefix("--") })
    }

    private override init() {
        let d = UserDefaults.standard
        let modeRaw = d.string(forKey: PrefKey.weatherLocationMode) ?? WeatherLocationMode.auto.rawValue
        let loadedMode = WeatherLocationMode(rawValue: modeRaw) ?? .auto
        var loadedCity = d.string(forKey: PrefKey.weatherCityName) ?? ""
        let loadedCountry = d.string(forKey: PrefKey.weatherCountryName) ?? ""

        let defaultUnit = Locale.current.measurementSystem == .metric ? "C" : "F"
        let storedUnit = d.string(forKey: PrefKey.weatherUnit) ?? defaultUnit
        let loadedUnit = (storedUnit == "F") ? "F" : "C"

        let hasCoords = d.object(forKey: PrefKey.weatherLatitude) != nil && d.object(forKey: PrefKey.weatherLongitude) != nil
        let loadedLat: Double? = hasCoords ? d.double(forKey: PrefKey.weatherLatitude) : nil
        let loadedLon: Double? = hasCoords ? d.double(forKey: PrefKey.weatherLongitude) : nil

        var loadedSnapshot: LiveWeatherSnapshot? = nil
        var loadedPrecise = false
        if let data = d.data(forKey: PrefKey.weatherCachedSnapshot),
           let decoded = try? JSONDecoder().decode(LiveWeatherSnapshot.self, from: data) {
            loadedSnapshot = decoded
            if loadedCity.isEmpty {
                loadedCity = decoded.city
            }
            loadedPrecise = decoded.isPreciseLocation
        }

        self.locationMode = loadedMode
        self.activeCity = loadedCity
        self.activeCountry = loadedCountry
        self.unit = loadedUnit
        self.savedLatitude = loadedLat
        self.savedLongitude = loadedLon
        self.snapshot = loadedSnapshot
        self.isPreciseLocation = loadedPrecise
        self.authorizationStatus = clManager.authorizationStatus
        super.init()

        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Actions Publiques

    /// Actualise la position et/ou la météo si les données sont absentes, expirées (>10 min) ou si l'unité diffère.
    func refreshIfNeeded(force: Bool = false, requestLocationPermission: Bool = false) {
        if locationMode == .manual, let lat = savedLatitude, let lon = savedLongitude {
            let needsFetch = force
                || snapshot == nil
                || snapshot?.unit != unit
                || snapshot?.city != activeCity
                || Date().timeIntervalSince(snapshot?.updatedAt ?? .distantPast) > 600
            if needsFetch {
                startWeatherFetch(
                    lat: lat,
                    lon: lon,
                    city: activeCity,
                    country: activeCountry,
                    isAuto: false,
                    isPrecise: false
                )
            }
            return
        }

        // Mode automatique : utiliser la position exacte macOS + repli IP immédiat
        refreshAutoLocationAndWeather(force: force, requestPermission: requestLocationPermission)
    }

    /// Force le passage en mode localisation automatique exacte.
    func useCurrentLocation(requestPermission: Bool = true) {
        locationMode = .auto
        UserDefaults.standard.set(WeatherLocationMode.auto.rawValue, forKey: PrefKey.weatherLocationMode)
        refreshAutoLocationAndWeather(force: true, requestPermission: requestPermission)
    }

    /// Sélectionne manuellement une ville et récupère sa météo en direct.
    func selectCity(_ city: WeatherCitySearchResult) {
        locationMode = .manual
        activeCity = city.name
        activeCountry = city.subtitle
        savedLatitude = city.latitude
        savedLongitude = city.longitude
        isPreciseLocation = false

        let d = UserDefaults.standard
        d.set(WeatherLocationMode.manual.rawValue, forKey: PrefKey.weatherLocationMode)
        d.set(city.name, forKey: PrefKey.weatherCityName)
        d.set(activeCountry, forKey: PrefKey.weatherCountryName)
        d.set(city.latitude, forKey: PrefKey.weatherLatitude)
        d.set(city.longitude, forKey: PrefKey.weatherLongitude)

        startWeatherFetch(
            lat: city.latitude,
            lon: city.longitude,
            city: city.name,
            country: activeCountry,
            isAuto: false,
            isPrecise: false
        )
    }

    /// Bascule l'unité ("C" ou "F"), convertit instantanément l'aperçu puis actualise depuis Open-Meteo.
    func setUnit(_ newUnit: String) {
        let normalized = (newUnit.uppercased() == "F") ? "F" : "C"
        guard unit != normalized else { return }
        let oldUnit = unit
        unit = normalized
        UserDefaults.standard.set(normalized, forKey: PrefKey.weatherUnit)

        if let cur = snapshot {
            func conv(_ v: Int) -> Int {
                if oldUnit == "C" && normalized == "F" {
                    return Int(round(Double(v) * 9.0 / 5.0 + 32.0))
                } else if oldUnit == "F" && normalized == "C" {
                    return Int(round((Double(v) - 32.0) * 5.0 / 9.0))
                }
                return v
            }
            let converted = LiveWeatherSnapshot(
                city: cur.city,
                country: cur.country,
                latitude: cur.latitude,
                longitude: cur.longitude,
                unit: normalized,
                temp: conv(cur.temp),
                feelsLike: conv(cur.feelsLike),
                high: conv(cur.high),
                low: conv(cur.low),
                condition: cur.condition,
                humidity: cur.humidity,
                windSpeedValue: oldUnit == "C" && normalized == "F"
                    ? Int(round(Double(cur.windSpeedValue) * 0.621371))
                    : (oldUnit == "F" && normalized == "C" ? Int(round(Double(cur.windSpeedValue) * 1.60934)) : cur.windSpeedValue),
                precipProb: cur.precipProb,
                uvIndex: cur.uvIndex,
                sunrise: cur.sunrise,
                sunset: cur.sunset,
                isDay: cur.isDay,
                hourly: cur.hourly.map { WeatherHourlyPoint(time: $0.time, temp: conv($0.temp), symbol: $0.symbol) },
                daily: cur.daily.map { WeatherDailyPoint(isoDate: $0.isoDate, symbol: $0.symbol, low: conv($0.low), high: conv($0.high)) },
                updatedAt: cur.updatedAt,
                isAutoDetected: cur.isAutoDetected,
                isPreciseLocation: cur.isPreciseLocation
            )
            applySnapshot(converted)
        }

        if let lat = savedLatitude, let lon = savedLongitude {
            startWeatherFetch(
                lat: lat,
                lon: lon,
                city: activeCity,
                country: activeCountry,
                isAuto: locationMode == .auto,
                isPrecise: isPreciseLocation
            )
        } else {
            refreshIfNeeded(force: true, requestLocationPermission: false)
        }
    }

    func openLocationPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recherche de Villes (Open-Meteo Geocoding)

    func searchCities(query: String) async -> [WeatherCitySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return WeatherCitySearchResult.popularCities }

        let lang = LocalizationManager.activeLanguageCode
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=10&language=\(lang)&format=json") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            struct GeoResponse: Decodable {
                struct Item: Decodable {
                    let id: Int
                    let name: String
                    let latitude: Double
                    let longitude: Double
                    let country_code: String?
                    let country: String?
                    let admin1: String?
                }
                let results: [Item]?
            }
            let decoded = try JSONDecoder().decode(GeoResponse.self, from: data)
            let items = decoded.results ?? []
            return items.map {
                WeatherCitySearchResult(
                    id: "\($0.id)",
                    name: $0.name,
                    region: $0.admin1,
                    country: $0.country,
                    countryCode: $0.country_code,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Géolocalisation Automatique (CoreLocation + Repli IP)

    private func refreshAutoLocationAndWeather(force: Bool, requestPermission: Bool) {
        let now = Date()
        let isFresh = snapshot != nil
            && snapshot?.isAutoDetected == true
            && snapshot?.unit == unit
            && now.timeIntervalSince(snapshot?.updatedAt ?? .distantPast) < 600

        if !force && isFresh && isPreciseLocation {
            return
        }

        let status = clManager.authorizationStatus
        authorizationStatus = status

        if force || now.timeIntervalSince(lastAutoLocateAttempt) > 20 {
            lastAutoLocateAttempt = now

            if isAuthorized(status) {
                isDetectingLocation = true
                clManager.requestLocation()
                // Si aucune coordonnée n'est encore connue, on charge aussi en parallèle par IP pour ne pas afficher un état vide
                if savedLatitude == nil || snapshot == nil {
                    triggerIPFallbackIfStillWaiting()
                }
                return
            } else if status == .notDetermined && requestPermission && !isHeadlessTestRun {
                isDetectingLocation = true
                clManager.requestWhenInUseAuthorization()
                // Affiche la météo locale via IP pendant que l'utilisateur répond à la fenêtre d'autorisation macOS
                triggerIPFallbackIfStillWaiting()
                return
            }
        }

        // Sans autorisation CoreLocation (ou pendant un test headless) : utiliser coordonnées IP ou déjà connues
        if force || snapshot == nil || snapshot?.unit != unit || now.timeIntervalSince(snapshot?.updatedAt ?? .distantPast) > 600 {
            if !isAuthorized(status) {
                triggerIPFallbackIfStillWaiting()
            } else if let lat = savedLatitude, let lon = savedLongitude {
                startWeatherFetch(
                    lat: lat,
                    lon: lon,
                    city: activeCity,
                    country: activeCountry,
                    isAuto: true,
                    isPrecise: isPreciseLocation
                )
            }
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status == .authorized
    }

    private func triggerIPFallbackIfStillWaiting() {
        inFlightLocationTask?.cancel()
        inFlightLocationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let ipLoc = await Self.fetchIPGeolocation() {
                guard !Task.isCancelled, self.locationMode == .auto else { return }
                // Ne pas écraser si CoreLocation vient déjà de résoudre la position exacte
                if self.isPreciseLocation && self.snapshot != nil && self.snapshot?.unit == self.unit {
                    self.isDetectingLocation = false
                    return
                }
                self.activeCity = ipLoc.city
                self.activeCountry = ipLoc.country
                self.savedLatitude = ipLoc.latitude
                self.savedLongitude = ipLoc.longitude
                self.isPreciseLocation = false
                self.persistLocationCoords(lat: ipLoc.latitude, lon: ipLoc.longitude, city: ipLoc.city, country: ipLoc.country)
                self.isDetectingLocation = false
                self.startWeatherFetch(
                    lat: ipLoc.latitude,
                    lon: ipLoc.longitude,
                    city: ipLoc.city,
                    country: ipLoc.country,
                    isAuto: true,
                    isPrecise: false
                )
            } else {
                self.isDetectingLocation = false
                if let lat = self.savedLatitude, let lon = self.savedLongitude {
                    self.startWeatherFetch(
                        lat: lat,
                        lon: lon,
                        city: self.activeCity,
                        country: self.activeCountry,
                        isAuto: true,
                        isPrecise: false
                    )
                }
            }
        }
    }

    nonisolated private static func fetchIPGeolocation() async -> (city: String, country: String, latitude: Double, longitude: Double)? {
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6.0
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct GeoJS: Decodable {
                let city: String?
                let country: String?
                let region: String?
                let latitude: String?
                let longitude: String?
            }
            let decoded = try JSONDecoder().decode(GeoJS.self, from: data)
            guard let latStr = decoded.latitude, let lonStr = decoded.longitude,
                  let lat = Double(latStr), let lon = Double(lonStr) else {
                return nil
            }
            let city = (decoded.city?.isEmpty == false ? decoded.city : decoded.region) ?? "Paris"
            let country = decoded.country ?? ""
            return (city, country, lat, lon)
        } catch {
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if self.locationMode == .auto && self.isAuthorized(status) {
                self.isDetectingLocation = true
                self.clManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleExactCoordinates(lat: lat, lon: lon)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isDetectingLocation = false
            if self.locationMode == .auto && self.snapshot == nil {
                self.triggerIPFallbackIfStillWaiting()
            }
        }
    }

    private func handleExactCoordinates(lat: Double, lon: Double) {
        guard locationMode == .auto else {
            isDetectingLocation = false
            return
        }
        inFlightLocationTask?.cancel()
        savedLatitude = lat
        savedLongitude = lon
        isPreciseLocation = true

        let location = CLLocation(latitude: lat, longitude: lon)
        let preferredLocale = Locale(identifier: LocalizationManager.activeLanguageCode)

        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location, preferredLocale: preferredLocale) { [weak self] placemarks, _ in
            let pm = placemarks?.first
            let city = pm?.locality
                ?? pm?.subLocality
                ?? pm?.subAdministrativeArea
                ?? pm?.administrativeArea
                ?? ""
            let country = pm?.country ?? ""

            Task { @MainActor [weak self] in
                guard let self, self.locationMode == .auto else { return }
                self.isDetectingLocation = false
                let resolvedCity = city.isEmpty ? (self.activeCity.isEmpty ? loc("weather.city_default") : self.activeCity) : city
                self.activeCity = resolvedCity
                self.activeCountry = country
                self.persistLocationCoords(lat: lat, lon: lon, city: resolvedCity, country: country)
                self.startWeatherFetch(
                    lat: lat,
                    lon: lon,
                    city: resolvedCity,
                    country: country,
                    isAuto: true,
                    isPrecise: true
                )
            }
        }
    }

    private func persistLocationCoords(lat: Double, lon: Double, city: String, country: String) {
        let d = UserDefaults.standard
        d.set(lat, forKey: PrefKey.weatherLatitude)
        d.set(lon, forKey: PrefKey.weatherLongitude)
        d.set(city, forKey: PrefKey.weatherCityName)
        d.set(country, forKey: PrefKey.weatherCountryName)
    }

    // MARK: - Requête Open-Meteo Forecast

    private func startWeatherFetch(
        lat: Double,
        lon: Double,
        city: String,
        country: String,
        isAuto: Bool,
        isPrecise: Bool
    ) {
        inFlightWeatherTask?.cancel()
        isFetchingWeather = true
        let targetUnit = unit

        inFlightWeatherTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let fetched = await Self.fetchOpenMeteoForecast(
                lat: lat,
                lon: lon,
                city: city,
                country: country,
                unit: targetUnit,
                isAuto: isAuto,
                isPrecise: isPrecise
            )
            guard !Task.isCancelled else { return }
            self.isFetchingWeather = false
            if let fetched {
                self.applySnapshot(fetched)
            }
        }
    }

    private func applySnapshot(_ newSnapshot: LiveWeatherSnapshot) {
        self.snapshot = newSnapshot
        self.activeCity = newSnapshot.city
        self.activeCountry = newSnapshot.country
        self.isPreciseLocation = newSnapshot.isPreciseLocation

        if let data = try? JSONEncoder().encode(newSnapshot) {
            UserDefaults.standard.set(data, forKey: PrefKey.weatherCachedSnapshot)
        }

        WidgetManager.shared.updateWeather(
            city: newSnapshot.city,
            unit: newSnapshot.unit,
            temp: newSnapshot.temp,
            condition: newSnapshot.condition,
            feelsLike: newSnapshot.feelsLike
        )
        NotificationCenter.default.post(name: .weatherDataDidUpdate, object: newSnapshot)
    }

    nonisolated private static func fetchOpenMeteoForecast(
        lat: Double,
        lon: Double,
        city: String,
        country: String,
        unit: String,
        isAuto: Bool,
        isPrecise: Bool
    ) async -> LiveWeatherSnapshot? {
        let unitQuery = (unit == "F")
            ? "&temperature_unit=fahrenheit&wind_speed_unit=mph"
            : "&temperature_unit=celsius&wind_speed_unit=kmh"

        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&hourly=temperature_2m,weather_code,precipitation_probability,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,sunrise,sunset,precipitation_probability_max&forecast_days=7&timezone=auto\(unitQuery)"

        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10.0

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct ForecastResp: Decodable {
                struct Current: Decodable {
                    let time: String
                    let temperature_2m: Double
                    let apparent_temperature: Double
                    let relative_humidity_2m: Int
                    let weather_code: Int
                    let wind_speed_10m: Double
                    let is_day: Int
                }
                struct Hourly: Decodable {
                    let time: [String]
                    let temperature_2m: [Double]
                    let weather_code: [Int]
                    let precipitation_probability: [Int]?
                    let is_day: [Int]?
                }
                struct Daily: Decodable {
                    let time: [String]
                    let weather_code: [Int]
                    let temperature_2m_max: [Double]
                    let temperature_2m_min: [Double]
                    let uv_index_max: [Double]?
                    let sunrise: [String]?
                    let sunset: [String]?
                    let precipitation_probability_max: [Int]?
                }
                let current: Current
                let hourly: Hourly
                let daily: Daily
            }

            let f = try JSONDecoder().decode(ForecastResp.self, from: data)
            let isDay = (f.current.is_day == 1)
            let condition = conditionKey(forWMO: f.current.weather_code, isDay: isDay)

            let todayHigh = Int(round(f.daily.temperature_2m_max.first ?? f.current.temperature_2m))
            let todayLow = Int(round(f.daily.temperature_2m_min.first ?? f.current.temperature_2m))
            let uvIndex = Int(round(f.daily.uv_index_max?.first ?? 0))
            let precipProb = f.daily.precipitation_probability_max?.first ?? 0

            let currentHourPrefix = String(f.current.time.prefix(13)) // YYYY-MM-DDTHH
            let startHourIdx = f.hourly.time.firstIndex(where: { $0.hasPrefix(currentHourPrefix) }) ?? 0

            var hourlyPoints: [WeatherHourlyPoint] = []
            for step in 1...5 {
                let idx = min(startHourIdx + step * 3, max(0, f.hourly.time.count - 1))
                guard idx < f.hourly.time.count,
                      idx < f.hourly.temperature_2m.count,
                      idx < f.hourly.weather_code.count else { continue }
                let iso = f.hourly.time[idx]
                let hhmm = iso.count >= 16 ? String(iso.dropFirst(11).prefix(5)) : iso
                let hDay = (idx < (f.hourly.is_day?.count ?? 0)) ? (f.hourly.is_day?[idx] == 1) : true
                let sym = sfSymbol(forWMO: f.hourly.weather_code[idx], isDay: hDay)
                hourlyPoints.append(
                    WeatherHourlyPoint(
                        time: hhmm,
                        temp: Int(round(f.hourly.temperature_2m[idx])),
                        symbol: sym
                    )
                )
            }

            var dailyPoints: [WeatherDailyPoint] = []
            for idx in 0..<min(7, f.daily.time.count) {
                guard idx < f.daily.weather_code.count,
                      idx < f.daily.temperature_2m_min.count,
                      idx < f.daily.temperature_2m_max.count else { continue }
                dailyPoints.append(
                    WeatherDailyPoint(
                        isoDate: f.daily.time[idx],
                        symbol: sfSymbol(forWMO: f.daily.weather_code[idx], isDay: true),
                        low: Int(round(f.daily.temperature_2m_min[idx])),
                        high: Int(round(f.daily.temperature_2m_max[idx]))
                    )
                )
            }

            func extractHHMM(_ iso: String?) -> String {
                guard let iso, iso.count >= 16 else { return "--:--" }
                return String(iso.dropFirst(11).prefix(5))
            }

            return LiveWeatherSnapshot(
                city: city.isEmpty ? loc("weather.city_default") : city,
                country: country,
                latitude: lat,
                longitude: lon,
                unit: unit,
                temp: Int(round(f.current.temperature_2m)),
                feelsLike: Int(round(f.current.apparent_temperature)),
                high: todayHigh,
                low: todayLow,
                condition: condition,
                humidity: f.current.relative_humidity_2m,
                windSpeedValue: Int(round(f.current.wind_speed_10m)),
                precipProb: precipProb,
                uvIndex: uvIndex,
                sunrise: extractHHMM(f.daily.sunrise?.first),
                sunset: extractHHMM(f.daily.sunset?.first),
                isDay: isDay,
                hourly: hourlyPoints,
                daily: dailyPoints,
                updatedAt: Date(),
                isAutoDetected: isAuto,
                isPreciseLocation: isPrecise
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func conditionKey(forWMO code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sunny" : "clear"
        case 1:
            return isDay ? "sunny" : "clear"
        case 2, 3, 45, 48:
            return "cloudy"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return "rainy"
        case 71, 73, 75, 77, 85, 86:
            return "snowy"
        case 95, 96, 99:
            return "stormy"
        default:
            return "cloudy"
        }
    }

    nonisolated private static func sfSymbol(forWMO code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sun.max" : "moon.stars"
        case 1, 2:
            return isDay ? "cloud.sun" : "cloud.moon"
        case 3:
            return "cloud"
        case 45, 48:
            return "cloud.fog"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow"
        case 95, 96, 99:
            return "cloud.bolt.rain"
        default:
            return "cloud"
        }
    }
}
