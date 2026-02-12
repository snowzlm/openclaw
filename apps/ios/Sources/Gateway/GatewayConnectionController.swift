import OpenClawKit
import Darwin
import Foundation
import Network
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class GatewayConnectionController {
    struct LastAttemptedEndpoint: Equatable {
        enum Source: Equatable {
            case discovered
            case manual
            case autoConnect
        }

        var host: String
        var port: Int
        var useTLS: Bool
        var source: Source
    }

    private(set) var gateways: [GatewayDiscoveryModel.DiscoveredGateway] = []
    private(set) var discoveryStatusText: String = "Idle"
    private(set) var discoveryDebugLog: [GatewayDiscoveryModel.DebugLogEntry] = []
    private(set) var lastAttemptedEndpoint: LastAttemptedEndpoint?

    private let discovery = GatewayDiscoveryModel()
    private weak var appModel: NodeAppModel?
    private var didAutoConnect = false

    private static let lastHostDefaultsKey = "gateway.lastHost"
    private static let lastPortDefaultsKey = "gateway.lastPort"
    private static let lastTlsDefaultsKey = "gateway.lastTls"

    init(appModel: NodeAppModel, startDiscovery: Bool = true) {
        self.appModel = appModel

        GatewaySettingsStore.bootstrapPersistence()
        let defaults = UserDefaults.standard
        self.discovery.setDebugLoggingEnabled(defaults.bool(forKey: "gateway.discovery.debugLogs"))
        if let last = Self.loadLastConnection(defaults: defaults) {
            self.lastAttemptedEndpoint = LastAttemptedEndpoint(
                host: last.host,
                port: last.port,
                useTLS: last.useTLS,
                source: .autoConnect)
        }

        self.updateFromDiscovery()
        self.observeDiscovery()

        if startDiscovery {
            self.discovery.start()
        }
    }

    func setDiscoveryDebugLoggingEnabled(_ enabled: Bool) {
        self.discovery.setDebugLoggingEnabled(enabled)
    }

    func setScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            self.discovery.stop()
        case .active, .inactive:
            self.discovery.start()
        @unknown default:
            self.discovery.start()
        }
    }

    func allowAutoConnectAgain() {
        self.didAutoConnect = false
        self.maybeAutoConnect()
    }

    func restartDiscovery() {
        self.discovery.stop()
        self.didAutoConnect = false
        self.discovery.start()
        self.updateFromDiscovery()
    }

    func connect(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        let instanceId = UserDefaults.standard.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)
        guard let host = self.resolveGatewayHost(gateway) else { return }
        let port = gateway.gatewayPort ?? 18789
        let tlsParams = self.resolveDiscoveredTLSParams(gateway: gateway)
        guard let url = self.buildGatewayURL(
            host: host,
            port: port,
            useTLS: tlsParams?.required == true)
        else { return }
        self.recordLastAttempt(host: host, port: port, useTLS: tlsParams?.required == true, source: .discovered)
        self.didAutoConnect = true
        self.startAutoConnect(
            url: url,
            gatewayStableID: gateway.stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    func connectManual(host: String, port: Int, useTLS: Bool) async {
        let instanceId = UserDefaults.standard.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)
        let stableID = self.manualStableID(host: host, port: port)
        let tlsParams = self.resolveManualTLSParams(stableID: stableID, tlsEnabled: useTLS)
        guard let url = self.buildGatewayURL(
            host: host,
            port: port,
            useTLS: tlsParams?.required == true)
        else { return }
        self.recordLastAttempt(host: host, port: port, useTLS: tlsParams?.required == true, source: .manual)
        self.didAutoConnect = true
        self.startAutoConnect(
            url: url,
            gatewayStableID: stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    private func updateFromDiscovery() {
        let newGateways = self.discovery.gateways
        self.gateways = newGateways
        self.discoveryStatusText = self.discovery.statusText
        self.discoveryDebugLog = self.discovery.debugLog
        self.updateLastDiscoveredGateway(from: newGateways)
        self.maybeAutoConnect()
    }

    private func observeDiscovery() {
        withObservationTracking {
            _ = self.discovery.gateways
            _ = self.discovery.statusText
            _ = self.discovery.debugLog
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateFromDiscovery()
                self.observeDiscovery()
            }
        }
    }

    private func maybeAutoConnect() {
        guard !self.didAutoConnect else { return }
        guard let appModel = self.appModel else { return }
        guard appModel.gatewayServerName == nil else { return }

        let defaults = UserDefaults.standard
        let manualEnabled = defaults.bool(forKey: "gateway.manual.enabled")

        let instanceId = defaults.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !instanceId.isEmpty else { return }

        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)

        if manualEnabled {
            let manualHost = defaults.string(forKey: "gateway.manual.host")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !manualHost.isEmpty else { return }

            let manualPort = defaults.integer(forKey: "gateway.manual.port")
            let resolvedPort = manualPort > 0 ? manualPort : 18789
            let manualTLS = defaults.bool(forKey: "gateway.manual.tls")

            let stableID = self.manualStableID(host: manualHost, port: resolvedPort)
            let tlsParams = self.resolveManualTLSParams(stableID: stableID, tlsEnabled: manualTLS)

            guard let url = self.buildGatewayURL(
                host: manualHost,
                port: resolvedPort,
                useTLS: tlsParams?.required == true)
            else { return }

            self.recordLastAttempt(
                host: manualHost,
                port: resolvedPort,
                useTLS: tlsParams?.required == true,
                source: .autoConnect)
            self.didAutoConnect = true
            self.startAutoConnect(
                url: url,
                gatewayStableID: stableID,
                tls: tlsParams,
                token: token,
                password: password)
            return
        }

        let preferredStableID = defaults.string(forKey: "gateway.preferredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastDiscoveredStableID = defaults.string(forKey: "gateway.lastDiscoveredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let candidates = [preferredStableID, lastDiscoveredStableID].filter { !$0.isEmpty }
        guard let targetStableID = candidates.first(where: { id in
            self.gateways.contains(where: { $0.stableID == id })
        }) else { return }

        guard let target = self.gateways.first(where: { $0.stableID == targetStableID }) else { return }
        guard let host = self.resolveGatewayHost(target) else { return }
        let port = target.gatewayPort ?? 18789
        let tlsParams = self.resolveDiscoveredTLSParams(gateway: target)
        guard let url = self.buildGatewayURL(host: host, port: port, useTLS: tlsParams?.required == true)
        else { return }

        self.recordLastAttempt(host: host, port: port, useTLS: tlsParams?.required == true, source: .autoConnect)
        self.didAutoConnect = true
        self.startAutoConnect(
            url: url,
            gatewayStableID: target.stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    private func updateLastDiscoveredGateway(from gateways: [GatewayDiscoveryModel.DiscoveredGateway]) {
        let defaults = UserDefaults.standard
        let preferred = defaults.string(forKey: "gateway.preferredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingLast = defaults.string(forKey: "gateway.lastDiscoveredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Avoid overriding user intent (preferred/lastDiscovered are also set on manual Connect).
        guard preferred.isEmpty, existingLast.isEmpty else { return }
        guard let first = gateways.first else { return }

        defaults.set(first.stableID, forKey: "gateway.lastDiscoveredStableID")
        GatewaySettingsStore.saveLastDiscoveredGatewayStableID(first.stableID)
    }

    private func startAutoConnect(
        url: URL,
        gatewayStableID: String,
        tls: GatewayTLSParams?,
        token: String?,
        password: String?)
    {
        guard let appModel else { return }
        let connectOptions = self.makeConnectOptions()

        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                appModel.gatewayStatusText = "Connecting…"
            }
            appModel.connectToGateway(
                url: url,
                gatewayStableID: gatewayStableID,
                tls: tls,
                token: token,
                password: password,
                connectOptions: connectOptions)
        }
    }

    private func resolveDiscoveredTLSParams(gateway: GatewayDiscoveryModel.DiscoveredGateway) -> GatewayTLSParams? {
        let stableID = gateway.stableID
        let stored = GatewayTLSStore.loadFingerprint(stableID: stableID)

        if gateway.tlsEnabled || gateway.tlsFingerprintSha256 != nil || stored != nil {
            return GatewayTLSParams(
                required: true,
                expectedFingerprint: gateway.tlsFingerprintSha256 ?? stored,
                allowTOFU: stored == nil,
                storeKey: stableID)
        }

        return nil
    }

    private func resolveManualTLSParams(stableID: String, tlsEnabled: Bool) -> GatewayTLSParams? {
        let stored = GatewayTLSStore.loadFingerprint(stableID: stableID)
        if tlsEnabled || stored != nil {
            return GatewayTLSParams(
                required: true,
                expectedFingerprint: stored,
                allowTOFU: stored == nil,
                storeKey: stableID)
        }

        return nil
    }

    private func resolveGatewayHost(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> String? {
        if let lanHost = gateway.lanHost?.trimmingCharacters(in: .whitespacesAndNewlines), !lanHost.isEmpty {
            return lanHost
        }
        if let tailnet = gateway.tailnetDns?.trimmingCharacters(in: .whitespacesAndNewlines), !tailnet.isEmpty {
            return tailnet
        }
        return nil
    }

    func reconnectLastAttempt() async {
        if let lastAttemptedEndpoint {
            await self.connectManual(
                host: lastAttemptedEndpoint.host,
                port: lastAttemptedEndpoint.port,
                useTLS: lastAttemptedEndpoint.useTLS)
            return
        }
        guard let fallback = Self.loadLastConnection(defaults: .standard) else { return }
        await self.connectManual(host: fallback.host, port: fallback.port, useTLS: fallback.useTLS)
    }

    private func recordLastAttempt(
        host: String,
        port: Int,
        useTLS: Bool,
        source: LastAttemptedEndpoint.Source)
    {
        self.saveLastConnection(host: host, port: port, useTLS: useTLS)
        self.lastAttemptedEndpoint = LastAttemptedEndpoint(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            useTLS: useTLS,
            source: source)
    }

    private func saveLastConnection(host: String, port: Int, useTLS: Bool) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, port > 0, port <= 65535 else { return }
        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: Self.lastHostDefaultsKey)
        defaults.set(port, forKey: Self.lastPortDefaultsKey)
        defaults.set(useTLS, forKey: Self.lastTlsDefaultsKey)
    }

    static func loadLastConnection(defaults: UserDefaults = .standard) -> (host: String, port: Int, useTLS: Bool)? {
        let host = defaults.string(forKey: Self.lastHostDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = defaults.integer(forKey: Self.lastPortDefaultsKey)
        let tls = defaults.bool(forKey: Self.lastTlsDefaultsKey)
        guard !host.isEmpty, port > 0, port <= 65535 else { return nil }
        return (host, port, tls)
    }

    private func buildGatewayURL(host: String, port: Int, useTLS: Bool) -> URL? {
        let scheme = useTLS ? "wss" : "ws"
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    private func manualStableID(host: String, port: Int) -> String {
        "manual|\(host.lowercased())|\(port)"
    }

    private func makeConnectOptions() -> GatewayConnectOptions {
        let defaults = UserDefaults.standard
        let displayName = self.resolvedDisplayName(defaults: defaults)

        return GatewayConnectOptions(
            role: "node",
            scopes: [],
            caps: self.currentCaps(),
            commands: self.currentCommands(),
            permissions: [:],
            clientId: "openclaw-ios",
            clientMode: "node",
            clientDisplayName: displayName)
    }

    private func resolvedDisplayName(defaults: UserDefaults) -> String {
        let key = "node.displayName"
        let existing = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existing.isEmpty, existing != "iOS Node" { return existing }

        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = deviceName.isEmpty ? "iOS Node" : deviceName

        if existing.isEmpty || existing == "iOS Node" {
            defaults.set(candidate, forKey: key)
        }

        return candidate
    }

    private func currentCaps() -> [String] {
        var caps = [OpenClawCapability.canvas.rawValue, OpenClawCapability.screen.rawValue]

        // Default-on: if the key doesn't exist yet, treat it as enabled.
        let cameraEnabled =
            UserDefaults.standard.object(forKey: "camera.enabled") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "camera.enabled")
        if cameraEnabled { caps.append(OpenClawCapability.camera.rawValue) }

        let voiceWakeEnabled = UserDefaults.standard.bool(forKey: VoiceWakePreferences.enabledKey)
        if voiceWakeEnabled { caps.append(OpenClawCapability.voiceWake.rawValue) }

        let locationModeRaw = UserDefaults.standard.string(forKey: "location.enabledMode") ?? "off"
        let locationMode = OpenClawLocationMode(rawValue: locationModeRaw) ?? .off
        if locationMode != .off { caps.append(OpenClawCapability.location.rawValue) }

        return caps
    }

    private func currentCommands() -> [String] {
        var commands: [String] = [
            OpenClawCanvasCommand.present.rawValue,
            OpenClawCanvasCommand.hide.rawValue,
            OpenClawCanvasCommand.navigate.rawValue,
            OpenClawCanvasCommand.evalJS.rawValue,
            OpenClawCanvasCommand.snapshot.rawValue,
            OpenClawCanvasA2UICommand.push.rawValue,
            OpenClawCanvasA2UICommand.pushJSONL.rawValue,
            OpenClawCanvasA2UICommand.reset.rawValue,
            OpenClawScreenCommand.record.rawValue,
            OpenClawSystemCommand.notify.rawValue,
            OpenClawSystemCommand.which.rawValue,
            OpenClawSystemCommand.run.rawValue,
            OpenClawSystemCommand.execApprovalsGet.rawValue,
            OpenClawSystemCommand.execApprovalsSet.rawValue,
        ]

        let caps = Set(self.currentCaps())
        if caps.contains(OpenClawCapability.camera.rawValue) {
            commands.append(OpenClawCameraCommand.list.rawValue)
            commands.append(OpenClawCameraCommand.snap.rawValue)
            commands.append(OpenClawCameraCommand.clip.rawValue)
        }
        if caps.contains(OpenClawCapability.location.rawValue) {
            commands.append(OpenClawLocationCommand.get.rawValue)
        }

        return commands
    }

    private func platformString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let name = switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPadOS"
        case .phone:
            "iOS"
        default:
            "iOS"
        }
        return "\(name) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private func deviceFamily() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPad"
        case .phone:
            "iPhone"
        default:
            "iOS"
        }
    }

    private func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            String(bytes: ptr.prefix { $0 != 0 }, encoding: .utf8)
        }
        let trimmed = machine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

#if DEBUG
extension GatewayConnectionController {
    func _test_resolvedDisplayName(defaults: UserDefaults) -> String {
        self.resolvedDisplayName(defaults: defaults)
    }

    func _test_currentCaps() -> [String] {
        self.currentCaps()
    }

    func _test_currentCommands() -> [String] {
        self.currentCommands()
    }

    func _test_platformString() -> String {
        self.platformString()
    }

    func _test_deviceFamily() -> String {
        self.deviceFamily()
    }

    func _test_modelIdentifier() -> String {
        self.modelIdentifier()
    }

    func _test_appVersion() -> String {
        self.appVersion()
    }

    func _test_setGateways(_ gateways: [GatewayDiscoveryModel.DiscoveredGateway]) {
        self.gateways = gateways
    }

    func _test_triggerAutoConnect() {
        self.maybeAutoConnect()
    }

    func _test_setLastAttemptedEndpoint(_ endpoint: LastAttemptedEndpoint?) {
        self.lastAttemptedEndpoint = endpoint
    }
}
#endif
