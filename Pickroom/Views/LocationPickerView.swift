import CoreLocation
import MapKit
import SwiftUI

/// Picks a point on the map and writes it onto photos.
///
/// The map is here because a RAW file from a camera without a GPS module has
/// no coordinates at all, and typing latitude and longitude by hand is not a
/// thing anyone does. Searching for the venue and clicking it is.
struct LocationPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var placeName: String?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var scope: LocationScope = .current
    @State private var searchTask: Task<Void, Never>?

    private var pickedLocation: PhotoLocation? {
        guard let coordinate else { return nil }
        return PhotoLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: placeName
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            map
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .onAppear(perform: startAtExistingLocation)
        .onDisappear { searchTask?.cancel() }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search for a place", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)

            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.self) { item in
                            searchResultRow(item)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func searchResultRow(_ item: MKMapItem) -> some View {
        Button {
            choose(item)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Unnamed place")
                    .font(.callout)
                if let address = item.placemark.title {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(placeName ?? "Location", coordinate: coordinate)
                        .tint(.red)
                }
            }
            .mapStyle(.standard)
            .onTapGesture { point in
                guard let tapped = proxy.convert(point, from: .local) else { return }
                coordinate = tapped
                placeName = nil
                nameCoordinate(tapped)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let pickedLocation {
                    Text(pickedLocation.display)
                        .font(.callout.weight(.medium))
                    Text(pickedLocation.coordinateDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Click the map or search for a place")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            if model.availableLocationScopes.count > 1 {
                Picker("Apply to", selection: $scope) {
                    ForEach(model.availableLocationScopes, id: \.self) { scope in
                        Text(label(for: scope)).tag(scope)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if model.locatedAssetCount(for: scope) > 0 {
                Button(removeLabel, role: .destructive) {
                    // Confirmed outside the sheet: stacking an alert on top of
                    // a sheet reads as a glitch, and this is not undoable.
                    model.requestLocationClear(scope: scope)
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) { dismiss() }

            Button(applyLabel) {
                guard let pickedLocation else { return }
                Task {
                    await model.applyLocation(pickedLocation, scope: scope)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(pickedLocation == nil || model.isTaggingLocation)
        }
        .padding(12)
    }

    /// Says the count out loud, so a wider scope cannot be applied by
    /// accident just because the picker was left where it was.
    private var applyLabel: String {
        let count = model.assets(for: scope).count
        return count == 1 ? "Apply to 1 Photo" : "Apply to \(count) Photos"
    }

    private var removeLabel: String {
        let count = model.locatedAssetCount(for: scope)
        return count == 1 ? "Remove Location" : "Remove from \(count)"
    }

    private func label(for scope: LocationScope) -> String {
        switch scope {
        case .current: "This photo"
        case .selection: "\(model.assets(for: .selection).count) selected"
        case .filtered: "All \(model.assets(for: .filtered).count) in view"
        }
    }

    private func startAtExistingLocation() {
        // The narrowest scope the user actually asked for. Defaulting to the
        // widest one writes a location into every photo in view on a click
        // meant for one, and there is no undo for that.
        scope = model.defaultLocationScope

        guard let existing = model.currentAsset?.metadata.location else { return }
        let center = CLLocationCoordinate2D(
            latitude: existing.latitude,
            longitude: existing.longitude
        )
        coordinate = center
        placeName = existing.name
        camera = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )
    }

    private func choose(_ item: MKMapItem) {
        let center = item.placemark.coordinate
        coordinate = center
        placeName = item.name
        results = []
        query = item.name ?? query
        camera = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed

            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }

            results = Array((response?.mapItems ?? []).prefix(12))
            isSearching = false
        }
    }

    /// Turns a clicked point into something readable. Purely cosmetic — the
    /// coordinates are what gets written either way — so a failure is silent.
    private func nameCoordinate(_ coordinate: CLLocationCoordinate2D) {
        Task {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
            guard !Task.isCancelled else { return }

            let placemark = placemarks?.first
            placeName = [placemark?.name, placemark?.locality]
                .compactMap { $0 }
                .first
        }
    }
}
