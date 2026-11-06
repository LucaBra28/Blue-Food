import CoreLocation
import MapKit
import Observation
import SwiftUI

/// Supermärkte in der Nähe, der nächste zuerst.
@Observable
@MainActor
final class NearbyStoresModel {
    struct Store: Identifiable {
        let id: String
        let name: String
        let address: String
        let distance: CLLocationDistance
        let mapItem: MKMapItem
    }

    private(set) var stores: [Store] = []
    private(set) var isLoading = false
    private(set) var hasSearched = false

    func load(around origin: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false; hasSearched = true }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Supermarkt"
        request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 5000, longitudinalMeters: 5000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])

        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        guard let response = try? await MKLocalSearch(request: request).start() else {
            stores = []
            return
        }

        stores = response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let c = item.placemark.coordinate
            let distance = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return Store(
                id: "\(c.latitude),\(c.longitude)",
                name: name,
                address: item.placemark.title ?? "",
                distance: distance,
                mapItem: item
            )
        }
        .sorted { $0.distance < $1.distance }
    }
}

struct ZieleView: View {
    let origin: CLLocationCoordinate2D?
    @State private var model = NearbyStoresModel()

    var body: some View {
        List {
            if origin == nil {
                ContentUnavailableView("Standort wird benötigt", systemImage: "location.slash",
                                       description: Text("Erlaube den Standortzugriff, dann werden die nächsten Läden angezeigt."))
            } else if model.isLoading && model.stores.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suche Läden in der Nähe …").foregroundStyle(.secondary)
                }
            } else if model.hasSearched && model.stores.isEmpty {
                ContentUnavailableView("Keine Läden gefunden", systemImage: "cart",
                                       description: Text("In deiner Umgebung wurden keine Supermärkte gefunden."))
            }

            ForEach(model.stores) { store in
                Button {
                    store.mapItem.openInMaps()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cart.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name).font(.body)
                            if !store.address.isEmpty {
                                Text(store.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(Measurement(value: store.distance, unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .refreshable { await reload() }
        .task(id: originKey) { await reload() }
    }

    /// Ändert sich nur, wenn sich der Standort merklich bewegt (rund 100 m).
    private var originKey: String {
        guard let origin else { return "none" }
        return String(format: "%.3f,%.3f", origin.latitude, origin.longitude)
    }

    private func reload() async {
        guard let origin else { return }
        await model.load(around: origin)
    }
}
