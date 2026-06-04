//
//  ContentView.swift
//  BareGPS
//
//  Created by David Owens on 09/04/2026.
//

import CoreLocation
import MapLibre
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("gridReferenceSystem") private var gridReferenceSystemRawValue = GridReferenceSystem.automatic.rawValue
    @AppStorage("showSnailTrail") private var showSnailTrail = true
    @AppStorage("showWaypointsOnMap") private var showWaypointsOnMap = true
    @AppStorage("waypointMapDisplayMode") private var waypointMapDisplayModeRawValue = WaypointMapDisplayMode.all.rawValue
    @AppStorage("selectedWaypointSetID") private var selectedWaypointSetIDRawValue = ""
    @State private var tracker = GPSTracker()
    @State private var ui = ContentViewState()
    @State private var cachedAreas = CachedAreaStorage.load()
    @State private var cacheStatusClearTask: Task<Void, Never>?
    @State private var trackerStatusClearTask: Task<Void, Never>?

    private var selectedMapPointCoordinate: CLLocationCoordinate2D? {
        guard let selectedMapPointDetails = ui.selectedMapPointDetails, selectedMapPointDetails.showsTemporaryMarker, !selectedMapPointDetails.isActiveTarget else { return nil }
        return selectedMapPointDetails.coordinate
    }

    private var activeTargetCoordinate: CLLocationCoordinate2D? {
        ui.activeNavigationTarget?.coordinate
    }

    private var activeTargetWaypointID: UUID? {
        ui.activeNavigationTarget?.waypointID
    }

    private var focusedWaypointID: UUID? {
        ui.focusedWaypoint?.id
    }

    private var waypointMapDisplayModeBinding: Binding<WaypointMapDisplayMode> {
        Binding(
            get: { WaypointMapDisplayMode(rawValue: waypointMapDisplayModeRawValue) ?? .all },
            set: { waypointMapDisplayModeRawValue = $0.rawValue }
        )
    }

    private var selectedWaypointSetIDBinding: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: selectedWaypointSetIDRawValue) },
            set: { selectedWaypointSetIDRawValue = $0?.uuidString ?? "" }
        )
    }

    private var mapWaypoints: [GPXWaypoint] {
        guard showWaypointsOnMap else { return [] }

        let displayMode = WaypointMapDisplayMode(rawValue: waypointMapDisplayModeRawValue) ?? .all
        guard displayMode == .selectedSet else {
            return tracker.waypointSets.flatMap(\.uniqueWaypointsForDisplay)
        }

        let selectedWaypointSet = tracker.waypointSets.first(where: { $0.id == UUID(uuidString: selectedWaypointSetIDRawValue) })
            ?? tracker.waypointSets.first(where: { !$0.waypoints.isEmpty })
        var filteredWaypoints = selectedWaypointSet?.uniqueWaypointsForDisplay ?? []

        if let focusedWaypoint = ui.focusedWaypoint,
           !filteredWaypoints.contains(where: { $0.id == focusedWaypoint.id }) {
            filteredWaypoints.append(focusedWaypoint)
        }

        return filteredWaypoints
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TrackMapView(
                    points: tracker.mapPrimaryPoints,
                    guidePoints: tracker.mapGuidePoints,
                    waypoints: mapWaypoints,
                    cachedAreas: cachedAreas,
                    isRecording: tracker.isRecording,
                    showSnailTrail: showSnailTrail,
                    liveSnailTrailPoints: tracker.liveSnailTrailPoints,
                    mapStyle: ui.selectedMapStyle,
                    orientation: ui.mapOrientation,
                    userLocationCenterID: ui.userLocationCenterID,
                    northUpResetID: ui.northUpResetID,
                    cacheVisibleAreaID: ui.cacheVisibleAreaID,
                    focusCachedAreaID: ui.focusCachedAreaID,
                    focusedCachedArea: ui.selectedCachedArea,
                    cacheAreaName: ui.cacheAreaName,
                    cacheDepth: ui.cacheDepth,
                    flyoverRequest: ui.flyoverRequest,
                    flyoverSpeed: ui.flyoverSpeed,
                    selectedMapPoint: selectedMapPointCoordinate,
                    currentLocationCoordinate: tracker.latestLocation?.coordinate,
                    activeTargetCoordinate: activeTargetCoordinate,
                    activeTargetWaypointID: activeTargetWaypointID,
                    focusedWaypointID: focusedWaypointID,
                    focusWaypointID: ui.focusWaypointID,
                    focusedWaypoint: ui.focusedWaypoint,
                    onMapPointSelected: handleMapPointSelection,
                    onWaypointSelected: handleWaypointSelection,
                    onHeadingChange: { heading in
                        ui.mapHeading = heading
                    },
                    onVisibleCacheContextChange: { context in
                        ui.visibleCacheContext = context
                    },
                    onFlyoverMetricsChange: { metrics in
                        ui.flyoverMetrics = metrics
                    },
                    onCacheStatus: { message, didComplete in
                        setCacheStatusMessage(message, autoClear: didComplete)
                        if didComplete, !CachedAreaStorage.load().isEmpty {
                            cachedAreas = CachedAreaStorage.load()
                        }
                    }
                )
                .ignoresSafeArea()

                GeometryReader { proxy in
                    let isLandscape = proxy.size.width > proxy.size.height

                    MapOverlay(
                        metrics: ui.flyoverMetrics ?? tracker.metrics,
                        gridReferenceText: ui.flyoverRequest == nil ? currentGridReferenceText : "--",
                        accuracyText: ui.flyoverRequest == nil ? currentAccuracyText : "--",
                        isRecording: tracker.isRecording,
                        canResumeRecording: tracker.canResumeRecording,
                        canSave: tracker.canSave,
                        isTrackSaved: tracker.currentTrackIsSaved,
                        canReset: tracker.hasCurrentTrack,
                        statusMessage: tracker.statusMessage ?? ui.cacheStatusMessage,
                        attribution: ui.selectedMapStyle.attribution,
                        scaleBar: mapScale(for: ui.visibleCacheContext, mapWidth: proxy.size.width),
                        selectedMapPointDetails: ui.selectedMapPointDetails,
                        activeTargetDetails: activeTargetDetails,
                        selectedMapStyle: Binding(
                            get: { ui.selectedMapStyle },
                            set: { ui.selectedMapStyle = $0 }
                        ),
                        hasCachedVisibleArea: isVisibleAreaCached,
                        isLandscape: isLandscape,
                        onOptions: {
                            ui.showingOptions = true
                        },
                        onAbout: {
                            ui.showingAbout = true
                        },
                        onTracks: {
                            ui.showingTracks = true
                        },
                        onWaypoints: {
                            ui.showingWaypoints = true
                        },
                        onCompass: {
                            ui.showingCompass = true
                        },
                        onCenterLocation: {
                            ui.userLocationCenterID += 1
                        },
                        onNorthUp: {
                            ui.mapOrientation = .northUp
                            ui.northUpResetID += 1
                        },
                        mapHeading: ui.mapHeading,
                        onStartStop: tracker.toggleRecording,
                        onReset: tracker.resetCurrentTrack,
                        onSave: tracker.saveCurrentTrack,
                        isFlyoverActive: ui.flyoverRequest != nil,
                        flyoverSpeed: Binding(
                            get: { ui.flyoverSpeed },
                            set: { ui.flyoverSpeed = $0 }
                        ),
                        isGoToPanelCollapsed: Binding(
                            get: { ui.isGoToPanelCollapsed },
                            set: { ui.isGoToPanelCollapsed = $0 }
                        ),
                        onStopFlyover: stopFlyover,
                        onGoToTarget: activateGoToTarget,
                        onClearGoToTarget: clearGoToTarget,
                        onCreateWaypoint: beginCreateWaypoint
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(
                get: { ui.showingAbout },
                set: { ui.showingAbout = $0 }
            )) {
                AboutSheet()
            }
            .sheet(isPresented: Binding(
                get: { ui.showingOptions },
                set: { ui.showingOptions = $0 }
            )) {
                OptionsSheet(
                    cachedAreas: cachedAreas,
                    gridReferenceSystem: gridReferenceSystemBinding,
                    showSnailTrail: $showSnailTrail,
                    automaticGridReferenceSystem: GridReferenceSystem.automaticSelection(for: tracker.latestLocation?.coordinate),
                    locationAuthorizationSummary: tracker.locationAuthorizationSummary,
                    onDeleteCachedAreas: deleteCachedAreas,
                    onClearAllCachedAreas: clearAllCachedAreas,
                    onCacheVisibleArea: {
                        ui.cacheDepth = .standard
                        ui.cacheAreaName = ""
                        ui.showingCacheNamePrompt = true
                    },
                    onCacheVisibleAreaDeep: {
                        ui.cacheDepth = .deep
                        ui.cacheAreaName = ""
                        ui.showingCacheNamePrompt = true
                    },
                    onSelectCachedArea: { area in
                        selectCachedArea(area)
                    },
                    onOpenLocationSettings: openAppSettings
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { ui.showingCompass },
                set: { ui.showingCompass = $0 }
            )) {
                CompassView(heading: tracker.latestHeading)
            }
            .alert("Create Waypoint", isPresented: Binding(
                get: { ui.showingCreateWaypointPrompt },
                set: { ui.showingCreateWaypointPrompt = $0 }
            )) {
                TextField("Waypoint name", text: Binding(
                    get: { ui.waypointName },
                    set: { ui.waypointName = $0 }
                ))

                Button("Save") {
                    createWaypoint()
                }
                .disabled(ui.waypointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Save the selected map point to the waypoint list.")
            }
            .alert("Name Waypoint Set", isPresented: Binding(
                get: { ui.showingWaypointSetNamePrompt },
                set: { ui.showingWaypointSetNamePrompt = $0 }
            )) {
                TextField("Set name", text: Binding(
                    get: { ui.waypointSetName },
                    set: { ui.waypointSetName = $0 }
                ))

                Button("Save") {
                    saveImportedWaypointSet()
                }
                .disabled(ui.waypointSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Skip", role: .cancel) {
                    finishImportWithoutWaypointSet()
                }
            } message: {
                Text("Give this imported waypoint set a useful name.")
            }
            .alert("Name Cached Area", isPresented: Binding(
                get: { ui.showingCacheNamePrompt },
                set: { ui.showingCacheNamePrompt = $0 }
            )) {
                TextField("Area name", text: Binding(
                    get: { ui.cacheAreaName },
                    set: { ui.cacheAreaName = $0 }
                ))

                Button("Cache") {
                    startVisibleAreaCache()
                }
                .disabled(ui.cacheAreaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel", role: .cancel) { }
            } message: {
                Text(ui.cacheDepth == .deep
                    ? "Give this deeper offline map area a useful name. This option stores a wider zoom range and downloads more tiles."
                    : "Give this offline map area a useful name, for example Carrauntoohil or Lakes loop.")
            }
            .sheet(isPresented: Binding(
                get: { ui.showingTracks },
                set: { ui.showingTracks = $0 }
            )) {
                TracksSheet(
                    tracker: tracker,
                    onImport: {
                        beginImportFlow()
                    },
                    onFlyoverDisplayedTrack: startDisplayedTrackFlyover,
                    onFlyoverSavedTrack: startFlyover(for:)
                )
            }
            .sheet(isPresented: Binding(
                get: { ui.showingWaypoints },
                set: { ui.showingWaypoints = $0 }
            )) {
                WaypointsSheet(
                    tracker: tracker,
                    showWaypointsOnMap: $showWaypointsOnMap,
                    waypointMapDisplayMode: waypointMapDisplayModeBinding,
                    selectedWaypointSetID: selectedWaypointSetIDBinding,
                    gridReferenceSystem: GridReferenceSystem(rawValue: gridReferenceSystemRawValue) ?? .automatic,
                    onImport: {
                        beginImportFlow()
                    },
                    onSelectWaypoint: focusWaypoint
                )
            }
            .confirmationDialog(
                "Import GPX and stop recording?",
                isPresented: Binding(
                    get: { ui.showingImportRecordingPrompt },
                    set: { ui.showingImportRecordingPrompt = $0 }
                ),
                titleVisibility: .visible
            ) {
                Button("Stop and Import", role: .destructive) {
                    tracker.stopRecording()
                    ui.showingTracks = false
                    ui.showingWaypoints = false
                    ui.showingImporter = true
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Importing a GPX file will stop the current recording and replace the live track on the map.")
            }
            .alert(
                "Location Access Needed",
                isPresented: Binding(
                    get: { tracker.needsLocationSettings },
                    set: { _ in }
                )
            ) {
                Button("Open Settings") {
                    openAppSettings()
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("BareGPS needs location access to show your position, elevation, and record tracks.")
            }
            .fileImporter(
                isPresented: Binding(
                    get: { ui.showingImporter },
                    set: { ui.showingImporter = $0 }
                ),
                allowedContentTypes: [.gpx, .xml],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .task {
                await tracker.loadPersistedData()
                tracker.prepareLocationServices()
                cachedAreas = CachedAreaStorage.load()
            }
            .onChange(of: tracker.importedWaypoints) { _, newWaypoints in
                guard case let .waypoint(activeWaypointTarget)? = ui.activeNavigationTarget else { return }
                if !newWaypoints.contains(where: { $0.id == activeWaypointTarget.id }) {
                    ui.activeNavigationTarget = nil
                }
            }
            .onChange(of: tracker.latestLocation) { _, latestLocation in
                guard
                    !ui.hasAutoCenteredOnUserLocation,
                    ui.flyoverRequest == nil,
                    tracker.displayedPoints.isEmpty,
                    latestLocation != nil
                else {
                    return
                }

                ui.hasAutoCenteredOnUserLocation = true
                ui.userLocationCenterID += 1
            }
            .onChange(of: tracker.isRecording) { _, isRecording in
                if isRecording {
                    stopFlyover()
                }
            }
            .onChange(of: tracker.displayedPoints) { _, points in
                guard let flyoverRequest = ui.flyoverRequest else { return }
                if flyoverRequest.points != points {
                    stopFlyover()
                }
            }
            .onChange(of: tracker.displayedPoints) { _, points in
                guard points.isEmpty, !tracker.isRecording, ui.flyoverRequest == nil, tracker.latestLocation != nil else {
                    return
                }

                ui.userLocationCenterID += 1
            }
            .onChange(of: tracker.statusMessage) { _, message in
                trackerStatusClearTask?.cancel()

                guard let message, shouldAutoClearTrackerStatus(message) else {
                    trackerStatusClearTask = nil
                    return
                }

                trackerStatusClearTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if tracker.statusMessage == message {
                            tracker.clearStatusMessage()
                        }
                        trackerStatusClearTask = nil
                    }
                }
            }
        }
    }

    private func scheduleCacheStatusClear() {
        cacheStatusClearTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
                    await MainActor.run {
                        ui.cacheStatusMessage = nil
                        cacheStatusClearTask = nil
                    }
                }
            }

    private func setCacheStatusMessage(_ message: String, autoClear: Bool = true) {
        cacheStatusClearTask?.cancel()
        ui.cacheStatusMessage = message

        if autoClear {
            scheduleCacheStatusClear()
        } else {
            cacheStatusClearTask = nil
        }
    }

    private func shouldAutoClearTrackerStatus(_ message: String) -> Bool {
        if message == "Recording..." || message == "Recording. Background location mode is not enabled." {
            return false
        }

        if message.contains("Location access") || message.contains("Allow location access") {
            return false
        }

        return true
    }

    private var gridReferenceSystemBinding: Binding<GridReferenceSystem> {
        Binding(
            get: { GridReferenceSystem(rawValue: gridReferenceSystemRawValue) ?? .automatic },
            set: { gridReferenceSystemRawValue = $0.rawValue }
        )
    }

    private var effectiveGridReferenceSystem: GridReferenceSystem? {
        let selectedSystem = GridReferenceSystem(rawValue: gridReferenceSystemRawValue) ?? .automatic
        if selectedSystem == .automatic {
            return GridReferenceSystem.automaticSelection(for: tracker.latestLocation?.coordinate ?? tracker.displayedPoints.last?.coordinate)
        }
        return selectedSystem
    }

    private var currentGridReferenceText: String {
        guard
            let coordinate = tracker.latestLocation?.coordinate ?? tracker.displayedPoints.last?.coordinate,
            let reference = GridReferenceFormatter.reference(
                for: coordinate,
                system: GridReferenceSystem(rawValue: gridReferenceSystemRawValue) ?? .automatic,
                automaticSystem: effectiveGridReferenceSystem
            )
        else {
            return "--"
        }

        return reference.value
    }

    private var currentAccuracyText: String {
        guard let latestLocation = tracker.latestLocation, latestLocation.horizontalAccuracy >= 0 else { return "--" }
        return "\(Int(latestLocation.horizontalAccuracy.rounded())) m"
    }

    private var activeTargetDetails: MapPointDetails? {
        guard let activeNavigationTarget = ui.activeNavigationTarget else { return nil }
        switch activeNavigationTarget {
        case let .point(coordinate):
            return details(for: coordinate, title: "Go To Point", detailText: nil, waypoint: nil, isActiveTarget: true)
        case let .waypoint(waypoint):
            return details(for: waypoint, isActiveTarget: true)
        }
    }

    private func handleMapPointSelection(_ coordinate: CLLocationCoordinate2D) {
        ui.focusedWaypoint = nil
        if ui.selectedMapPointDetails != nil {
            ui.selectedMapPointDetails = nil
            return
        }

        ui.selectedMapPointDetails = details(for: coordinate, title: "Selected Point", detailText: nil, waypoint: nil, isActiveTarget: false)
    }

    private func handleWaypointSelection(_ waypoint: GPXWaypoint) {
        ui.focusedWaypoint = waypoint
        if ui.selectedMapPointDetails != nil {
            ui.selectedMapPointDetails = nil
            return
        }
        ui.selectedMapPointDetails = details(for: waypoint, isActiveTarget: activeTargetWaypointID == waypoint.id)
    }

    private func activateGoToTarget() {
        guard let selectedMapPointDetails = ui.selectedMapPointDetails else { return }
        ui.isGoToPanelCollapsed = false

        if let waypoint = selectedMapPointDetails.waypoint {
            ui.activeNavigationTarget = .waypoint(waypoint)
            ui.selectedMapPointDetails = details(for: waypoint, isActiveTarget: true)
        } else {
            ui.activeNavigationTarget = .point(selectedMapPointDetails.coordinate)
            ui.selectedMapPointDetails = details(
                for: selectedMapPointDetails.coordinate,
                title: "Go To Point",
                detailText: nil,
                waypoint: nil,
                isActiveTarget: true
            )
        }
    }

    private func clearGoToTarget() {
        ui.activeNavigationTarget = nil
        ui.isGoToPanelCollapsed = false
        if let selectedMapPointDetails = ui.selectedMapPointDetails {
            if let waypoint = selectedMapPointDetails.waypoint {
                ui.selectedMapPointDetails = details(for: waypoint, isActiveTarget: false)
            } else {
                ui.selectedMapPointDetails = details(
                    for: selectedMapPointDetails.coordinate,
                    title: "Selected Point",
                    detailText: nil,
                    waypoint: nil,
                    isActiveTarget: false
                )
            }
        }
    }

    private func beginCreateWaypoint() {
        guard ui.selectedMapPointDetails?.waypoint == nil else { return }
        ui.waypointName = ""
        ui.showingCreateWaypointPrompt = true
    }

    private func createWaypoint() {
        guard let coordinate = ui.selectedMapPointDetails?.coordinate else { return }
        let trimmedName = ui.waypointName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let waypoint = tracker.addWaypoint(named: trimmedName, coordinate: coordinate) {
            ui.selectedMapPointDetails = details(for: waypoint, isActiveTarget: activeTargetWaypointID == waypoint.id)
        }
        ui.waypointName = ""
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let importedContent = try GPXParser.importedContent(from: url)
            tracker.importTrackContent(importedContent, from: url)

            guard !importedContent.waypoints.isEmpty else {
                tracker.setImportStatus(for: importedContent)
                return
            }

            ui.pendingImportedContent = importedContent
            ui.pendingImportedWaypointSet = importedContent.waypoints
            ui.waypointSetName = defaultWaypointSetName(from: url)
            ui.showingWaypointSetNamePrompt = true
        } catch {
            tracker.setStatusMessage("Import failed: \(error.localizedDescription)")
        }
    }

    private func saveImportedWaypointSet() {
        guard let importedContent = ui.pendingImportedContent else { return }
        let trimmedName = ui.waypointSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        tracker.addImportedWaypointSet(named: trimmedName, waypoints: ui.pendingImportedWaypointSet)
        tracker.setImportStatus(for: importedContent, waypointSetName: trimmedName)
        clearPendingWaypointImport()
    }

    private func finishImportWithoutWaypointSet() {
        guard let importedContent = ui.pendingImportedContent else { return }
        tracker.setImportStatus(for: importedContent)
        clearPendingWaypointImport()
    }

    private func clearPendingWaypointImport() {
        ui.pendingImportedContent = nil
        ui.pendingImportedWaypointSet = []
        ui.waypointSetName = ""
    }

    private func defaultWaypointSetName(from url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "Imported Waypoints" : baseName
    }

    private func focusWaypoint(_ waypoint: GPXWaypoint) {
        ui.selectedMapPointDetails = nil
        ui.focusedWaypoint = waypoint
        ui.focusWaypointID += 1
    }

    private func details(
        for coordinate: CLLocationCoordinate2D,
        title: String,
        detailText: String?,
        waypoint: GPXWaypoint?,
        isActiveTarget: Bool
    ) -> MapPointDetails {
        let resolvedSystem = effectiveGridReferenceSystem
        let reference = GridReferenceFormatter.reference(
            for: coordinate,
            system: GridReferenceSystem(rawValue: gridReferenceSystemRawValue) ?? .automatic,
            automaticSystem: resolvedSystem
        )?.value ?? "--"

        let originCoordinate = tracker.latestLocation?.coordinate ?? tracker.displayedPoints.last?.coordinate
        let bearing = bearingValue(from: originCoordinate, to: coordinate)
        let arrowRotation = arrowRotation(for: bearing)

        return MapPointDetails(
            title: title,
            detailText: detailText,
            coordinate: coordinate,
            distanceText: distanceText(from: originCoordinate, to: coordinate),
            bearing: bearing,
            arrowRotation: arrowRotation,
            bearingText: bearing.map { "\(Int($0.rounded()))° \(compassPoint(for: $0))" } ?? "--",
            gridReferenceText: reference,
            showsTemporaryMarker: waypoint == nil,
            waypoint: waypoint,
            isActiveTarget: isActiveTarget
        )
    }

    private func details(for waypoint: GPXWaypoint, isActiveTarget: Bool) -> MapPointDetails {
        let detailText = waypoint.details
        return details(for: waypoint.coordinate, title: waypoint.name, detailText: detailText, waypoint: waypoint, isActiveTarget: isActiveTarget)
    }

    private func mapScale(for context: VisibleCacheContext?, mapWidth: CGFloat) -> MapScale? {
        guard let context, mapWidth > 0 else { return nil }

        let centerLatitude = (context.south + context.north) / 2
        let westPoint = CLLocation(latitude: centerLatitude, longitude: context.west)
        let eastPoint = CLLocation(latitude: centerLatitude, longitude: context.east)
        let visibleWidthMeters = westPoint.distance(from: eastPoint)
        guard visibleWidthMeters > 0 else { return nil }

        let metersPerPoint = visibleWidthMeters / mapWidth
        let targetWidth = min(120.0, max(72.0, mapWidth * 0.18))
        let roundedDistance = roundedScaleDistance(for: metersPerPoint * targetWidth)
        let barWidth = roundedDistance / metersPerPoint

        return MapScale(
            label: scaleLabel(for: roundedDistance),
            width: barWidth
        )
    }

    private func roundedScaleDistance(for distance: Double) -> Double {
        guard distance > 0 else { return 0 }

        let exponent = floor(log10(distance))
        let base = pow(10, exponent)
        let normalized = distance / base

        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }

        return multiplier * base
    }

    private func scaleLabel(for distance: Double) -> String {
        if distance >= 1000 {
            let kilometers = distance / 1000
            if kilometers.rounded() == kilometers {
                return "\(Int(kilometers)) km"
            }
            return String(format: "%.1f km", kilometers)
        }

        return "\(Int(distance.rounded())) m"
    }

    private func distanceText(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> String {
        guard let origin else { return "--" }

        let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))

        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        }

        return "\(Int(distance.rounded())) m"
    }

    private func bearingText(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> String {
        guard let origin else { return "--" }

        let bearing = initialBearing(from: origin, to: destination)
        return "\(Int(bearing.rounded()))° \(compassPoint(for: bearing))"
    }

    private func bearingValue(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> CLLocationDirection? {
        guard let origin else { return nil }
        return initialBearing(from: origin, to: destination)
    }

    private func arrowRotation(for bearing: CLLocationDirection?) -> CLLocationDirection? {
        guard let bearing else { return nil }
        let normalizedBearing = normalizeDirection(bearing)

        if let course = tracker.latestLocation?.course, course >= 0 {
            let normalizedCourse = normalizeDirection(course)
            return normalizeDirection(normalizedBearing - normalizedCourse)
        }

        if let heading = tracker.latestHeading {
            let normalizedHeading = normalizeDirection(heading)
            return normalizeDirection(normalizedBearing - normalizedHeading)
        }

        return normalizedBearing
    }

    private func initialBearing(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDirection {
        let originLatitude = origin.latitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let longitudeDelta = (destination.longitude - origin.longitude) * .pi / 180

        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let xComponent = cos(originLatitude) * sin(destinationLatitude)
        let yComponent = sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        let bearing = atan2(y, xComponent - yComponent) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    private func compassPoint(for bearing: CLLocationDirection) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let positive = normalizeDirection(bearing)
        let index = Int(((positive + 22.5) / 45).rounded(.down)) % points.count
        return points[index]
    }

    private func normalizeDirection(_ direction: CLLocationDirection) -> CLLocationDirection {
        let normalized = direction.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private var isVisibleAreaCached: Bool {
        guard let visibleCacheContext = ui.visibleCacheContext else { return false }
        return cachedAreas.contains { $0.covers(visibleCacheContext) }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func startVisibleAreaCache() {
        ui.cacheAreaName = ui.cacheAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ui.cacheAreaName.isEmpty else { return }
        ui.cacheVisibleAreaID += 1
    }

    private func beginImportFlow() {
        if tracker.isRecording {
            ui.showingImportRecordingPrompt = true
        } else {
            ui.showingTracks = false
            ui.showingWaypoints = false
            ui.showingImporter = true
        }
    }

    private func startDisplayedTrackFlyover() {
        startFlyover(points: tracker.displayedPoints)
    }

    private func startFlyover(for track: SavedTrack) {
        tracker.loadTrack(track)
        startFlyover(points: track.points)
    }

    private func startFlyover(points: [TrackPoint]) {
        guard points.count > 1 else { return }
        ui.nextFlyoverRequestID += 1
        ui.selectedMapPointDetails = nil
        ui.activeNavigationTarget = nil
        ui.showingTracks = false
        ui.selectedMapStyle = .satellite
        ui.flyoverMetrics = nil
        ui.flyoverRequest = FlyoverRequest(id: ui.nextFlyoverRequestID, points: points)
    }

    private func stopFlyover() {
        ui.flyoverRequest = nil
        ui.flyoverMetrics = nil
        ui.selectedMapStyle = .openTopo
    }

    private func selectCachedArea(_ area: CachedArea) {
        ui.selectedMapStyle = area.mapStyleName == MapDisplayStyle.satellite.rawValue ? .satellite : .openTopo
        ui.selectedCachedArea = area
        ui.selectedMapPointDetails = nil
        ui.focusCachedAreaID += 1
    }

    private func deleteCachedAreas(at offsets: IndexSet) {
        CachedAreaStorage.delete(at: offsets)
        cachedAreas = CachedAreaStorage.load()
    }

    private func clearAllCachedAreas() {
        CachedAreaStorage.clearAll()
        cachedAreas = []
        MLNOfflineStorage.shared.clearAmbientCache { error in
            if let error {
                setCacheStatusMessage("Could not clear map tile cache: \(error.localizedDescription)")
            } else {
                setCacheStatusMessage("Cleared cached map areas.")
            }
        }
    }
}

#Preview {
    ContentView()
}
