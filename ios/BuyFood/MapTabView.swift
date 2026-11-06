import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus
    private(set) var coordinate: CLLocationCoordinate2D?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestIfNeeded() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = last.coordinate
        Task { @MainActor in self.coordinate = coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Ein Supermarkt auf der Karte.
struct SupermarketPin: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

enum MapMode: String, CaseIterable, Identifiable {
    case karte = "Karte"
    case ziele = "Ziele"
    var id: String { rawValue }
}

struct MapTabView: View {
    let listID: String
    @State private var location = LocationAuthorizer()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mode: MapMode = .karte
    @State private var supermarkets: [SupermarketPin] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $mode) {
                ForEach(MapMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if mode == .karte {
                mapView
            } else {
                ZieleView(origin: location.coordinate)
            }
        }
        .onAppear { location.requestIfNeeded() }
    }

    private var mapView: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(supermarkets) { pin in
                Marker(pin.name, systemImage: "cart.fill", coordinate: pin.coordinate)
                    .tint(.green)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            searchSupermarkets(in: context.region)
        }
        .overlay(alignment: .top) {
            if location.status == .denied || location.status == .restricted {
                Text("Standortzugriff ist ausgeschaltet. Du kannst ihn in den Einstellungen erlauben.")
                    .font(.footnote)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding()
            }
        }
    }

    /// Sucht Supermärkte im sichtbaren Ausschnitt (nur Kategorie „Lebensmittel“).
    private func searchSupermarkets(in region: MKCoordinateRegion) {
        searchTask?.cancel()
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "Supermarkt"
            request.region = region
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                supermarkets = response.mapItems.compactMap { item in
                    guard let name = item.name else { return nil }
                    let c = item.placemark.coordinate
                    return SupermarketPin(id: "\(c.latitude),\(c.longitude)", name: name, coordinate: c)
                }
            } catch {
                // Keine Marker bei Fehlern (z. B. offline); die Karte bleibt benutzbar.
            }
        }
    }
}
