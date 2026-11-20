import SwiftUI
import CoreLocation

/// Sélecteur de localisation et de ville pour les widgets Météo (Position exacte macOS ou recherche manuelle).
struct WeatherCityPickerSheet: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var locManager = LocalizationManager.shared

    var onTextFocusChanged: ((Bool) -> Void)? = nil
    let onClose: () -> Void

    @State private var searchText: String = ""
    @State private var searchResults: [WeatherCitySearchResult] = WeatherCitySearchResult.popularCities
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        let _ = locManager.effectiveLanguageCode
        VelvetAuraModalContainer(cornerRadius: 22) { _ in
            VStack(spacing: 14) {
                headerBar
                autoLocationCard
                searchBar
                cityListSection
            }
            .padding(20)
            .frame(width: 520, height: 520)
        }
        .onAppear {
            searchResults = WeatherCitySearchResult.popularCities
            onTextFocusChanged?(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFieldFocused = true
            }
        }
        .onDisappear {
            searchTask?.cancel()
            onTextFocusChanged?(false)
        }
        .onChange(of: searchText) { _, newValue in
            performDebouncedSearch(query: newValue)
        }
    }

    // MARK: - En-tête + Sélecteur °C / °F + ESC

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.62, blue: 1.0), Color(red: 0.08, green: 0.36, blue: 0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(loc("weather.picker.title"))
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.primary)
                Text(currentLocationSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Bouton unité °C / °F
            HStack(spacing: 2) {
                ForEach(["C", "F"], id: \.self) { u in
                    let isSelected = weatherService.unit == u
                    Button {
                        weatherService.setUnit(u)
                    } label: {
                        Text("°\(u)")
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .black : .primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.white : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.12), in: Capsule())

            VelvetAuraEscapePill()
        }
    }

    private var currentLocationSummary: String {
        if let snap = weatherService.snapshot {
            let modeLabel = weatherService.locationMode == .auto
                ? loc("weather.picker.mode_auto_short")
                : loc("weather.picker.mode_manual_short")
            return "\(snap.city) • \(snap.temp)°\(snap.unit) (\(modeLabel))"
        }
        return weatherService.activeCity.isEmpty ? loc("weather.picker.subtitle_default") : weatherService.activeCity
    }

    // MARK: - Carte Position Automatique Exacte

    private var autoLocationCard: some View {
        let isAuto = (weatherService.locationMode == .auto)
        let isDenied = (weatherService.authorizationStatus == .denied || weatherService.authorizationStatus == .restricted)

        return VStack(spacing: 8) {
            Button {
                weatherService.useCurrentLocation(requestPermission: true)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isAuto ? Color.cyan.opacity(0.24) : Color.white.opacity(0.10))
                            .frame(width: 32, height: 32)
                        if weatherService.isDetectingLocation {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(isAuto ? Color.cyan : .white.opacity(0.8))
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("weather.picker.auto_title"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(autoSubtitle(isDenied: isDenied))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer()

                    if isAuto {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.cyan)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isAuto ? Color.cyan.opacity(0.12) : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(isAuto ? Color.cyan.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(loc("weather.picker.permission_denied"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        weatherService.openLocationPrivacySettings()
                    } label: {
                        Text(loc("weather.picker.open_settings"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func autoSubtitle(isDenied: Bool) -> String {
        if weatherService.isDetectingLocation {
            return loc("weather.picker.detecting")
        }
        if weatherService.locationMode == .auto, !weatherService.activeCity.isEmpty {
            let detail = weatherService.isPreciseLocation
                ? loc("weather.picker.precise_badge")
                : (isDenied ? loc("weather.picker.ip_fallback_badge") : loc("weather.picker.approx_badge"))
            return "\(weatherService.activeCity) — \(detail)"
        }
        return loc("weather.picker.auto_desc")
    }

    // MARK: - Barre de Recherche & Liste des Villes

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            TextField(loc("weather.picker.search_placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
                .focused($searchFieldFocused)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var cityListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? loc("weather.picker.popular_header")
                 : loc("weather.picker.results_header"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 4)

            if searchResults.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(loc("weather.picker.no_results"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(searchResults) { city in
                            cityRow(city)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func cityRow(_ city: WeatherCitySearchResult) -> some View {
        let isCurrent = weatherService.locationMode == .manual
            && weatherService.activeCity.caseInsensitiveCompare(city.name) == .orderedSame

        return Button {
            weatherService.selectCity(city)
            onClose()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.cyan : .white.opacity(0.65))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(city.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if !city.subtitle.isEmpty {
                        Text(city.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let code = city.countryCode, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.cyan)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Color.cyan.opacity(0.14) : Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func performDebouncedSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearching = false
            searchResults = WeatherCitySearchResult.popularCities
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await weatherService.searchCities(query: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
}
