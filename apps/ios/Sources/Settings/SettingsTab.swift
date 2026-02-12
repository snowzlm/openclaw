import OpenClawKit
import Network
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class ConnectStatusStore {
    var text: String?
}

extension ConnectStatusStore: @unchecked Sendable {}

struct SettingsTab: View {
    @Environment(NodeAppModel.self) private var appModel: NodeAppModel
    @Environment(VoiceWakeManager.self) private var voiceWake: VoiceWakeManager
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("node.displayName") private var displayName: String = "iOS Node"
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false
    @AppStorage("talk.button.enabled") private var talkButtonEnabled: Bool = true
    @AppStorage("camera.enabled") private var cameraEnabled: Bool = true
    @AppStorage("location.enabledMode") private var locationEnabledModeRaw: String = OpenClawLocationMode.off.rawValue
    @AppStorage("location.preciseEnabled") private var locationPreciseEnabled: Bool = true
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("gateway.preferredStableID") private var preferredGatewayStableID: String = ""
    @AppStorage("gateway.lastDiscoveredStableID") private var lastDiscoveredGatewayStableID: String = ""
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("gateway.manual.port") private var manualGatewayPort: Int = 18789
    @AppStorage("gateway.manual.tls") private var manualGatewayTLS: Bool = true
    @AppStorage("gateway.discovery.domain") private var discoveryDomain: String = ""
    @AppStorage("gateway.discovery.debugLogs") private var discoveryDebugLogsEnabled: Bool = false
    @AppStorage("canvas.debugStatusEnabled") private var canvasDebugStatusEnabled: Bool = false
    @AppStorage("onboarding.requestID") private var onboardingRequestID: Int = 0
    @State private var connectStatus = ConnectStatusStore()
    @State private var connectingGatewayID: String?
    @State private var localIPAddress: String?
    @State private var lastLocationModeRaw: String = OpenClawLocationMode.off.rawValue
    @State private var gatewayToken: String = ""
    @State private var gatewayPassword: String = ""
    @State private var resetOnboardingConfirmPresented: Bool = false
    @State private var discoveryRestartTask: Task<Void, Never>?

    private var gatewayIssue: GatewayConnectionIssue {
        GatewayConnectionIssue.detect(from: self.appModel.gatewayStatusText)
    }

    private var gatewayAuthMissing: Bool { self.gatewayIssue.needsAuthToken }

    private var gatewayPairingRequired: Bool { self.gatewayIssue.needsPairing }

    private var gatewayPairingRequestId: String? { self.gatewayIssue.requestId }

    var body: some View {
        NavigationStack {
            Form {
                Section("Node") {
                    TextField("Name", text: self.$displayName)
                    Text(self.instanceId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("IP", value: self.localIPAddress ?? "—")
                        .contextMenu {
                            if let ip = self.localIPAddress {
                                Button {
                                    UIPasteboard.general.string = ip
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    LabeledContent("Platform", value: self.platformString())
                    LabeledContent("Version", value: self.appVersion())
                    LabeledContent("Model", value: self.modelIdentifier())
                }

                Section("Gateway") {
                    LabeledContent("Discovery", value: self.gatewayController.discoveryStatusText)
                    LabeledContent("Status", value: self.appModel.gatewayStatusText)

                    if self.gatewayAuthMissing {
                        TextField("Gateway Auth Token", text: self.$gatewayToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("Paste from: openclaw config get gateway.auth.token")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if self.gatewayPairingRequired {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device pairing required")
                                .font(.headline)

                            Text("On gateway host:")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button("Copy: openclaw devices list") {
                                UIPasteboard.general.string = "openclaw devices list"
                            }

                            if let id = self.gatewayPairingRequestId {
                                Button("Copy: openclaw devices approve \(id)") {
                                    UIPasteboard.general.string = "openclaw devices approve \(id)"
                                }
                            } else {
                                Button("Copy: openclaw devices approve <requestId>") {
                                    UIPasteboard.general.string = "openclaw devices approve <requestId>"
                                }
                            }

                            Text("After approval, the iOS node should reconnect automatically.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Restart Discovery") {
                        self.gatewayController.restartDiscovery()
                    }
                    .disabled(self.connectingGatewayID != nil)

                    if let serverName = self.appModel.gatewayServerName {
                        LabeledContent("Server", value: serverName)
                        if let addr = self.appModel.gatewayRemoteAddress {
                            let parts = Self.parseHostPort(from: addr)
                            let urlString = Self.httpURLString(host: parts?.host, port: parts?.port, fallback: addr)
                            LabeledContent("Address") {
                                Text(urlString)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = urlString
                                } label: {
                                    Label("Copy URL", systemImage: "doc.on.doc")
                                }

                                if let parts {
                                    Button {
                                        UIPasteboard.general.string = parts.host
                                    } label: {
                                        Label("Copy Host", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        UIPasteboard.general.string = "\(parts.port)"
                                    } label: {
                                        Label("Copy Port", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }

                        Button("Disconnect", role: .destructive) {
                            self.appModel.disconnectGateway()
                        }

                        self.gatewayList(showing: .availableOnly)
                    } else {
                        self.gatewayList(showing: .all)
                    }

                    if let text = self.connectStatus.text {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("Advanced") {
                        Toggle("Use Manual Gateway", isOn: self.$manualGatewayEnabled)

                        TextField("Host", text: self.$manualGatewayHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Port", value: self.$manualGatewayPort, format: .number)
                            .keyboardType(.numberPad)

                        Toggle("Use TLS", isOn: self.$manualGatewayTLS)

                        TextField("Discovery Domain (optional)", text: self.$discoveryDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: self.discoveryDomain) { _, _ in
                                self.scheduleDiscoveryRestart()
                            }

                        Text("For tailnet / unicast DNS-SD (example: openclaw.internal.).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await self.connectManual() }
                        } label: {
                            if self.connectingGatewayID == "manual" {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    Text("Connecting…")
                                }
                            } else {
                                Text("Connect (Manual)")
                            }
                        }
                        .disabled(self.connectingGatewayID != nil || self.manualGatewayHost
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || self.manualGatewayPort <= 0 || self.manualGatewayPort > 65535)

                        Text(
                            "Use this when mDNS/Bonjour discovery is blocked. "
                                + "The gateway WebSocket listens on port 18789 by default.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Toggle("Discovery Debug Logs", isOn: self.$discoveryDebugLogsEnabled)
                            .onChange(of: self.discoveryDebugLogsEnabled) { _, newValue in
                                self.gatewayController.setDiscoveryDebugLoggingEnabled(newValue)
                            }

                        NavigationLink("Discovery Logs") {
                            GatewayDiscoveryDebugLogView()
                        }

                        Toggle("Debug Canvas Status", isOn: self.$canvasDebugStatusEnabled)

                        TextField("Gateway Auth Token", text: self.$gatewayToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Gateway Password", text: self.$gatewayPassword)
                    }
                }

                Section("Voice") {
                    Toggle("Voice Wake", isOn: self.$voiceWakeEnabled)
                        .onChange(of: self.voiceWakeEnabled) { _, newValue in
                            self.appModel.setVoiceWakeEnabled(newValue)
                        }
                    Toggle("Talk Mode", isOn: self.$talkEnabled)
                        .onChange(of: self.talkEnabled) { _, newValue in
                            self.appModel.setTalkEnabled(newValue)
                        }
                    // Keep this separate so users can hide the side bubble without disabling Talk Mode.
                    Toggle("Show Talk Button", isOn: self.$talkButtonEnabled)

                    NavigationLink {
                        VoiceWakeWordsSettingsView()
                    } label: {
                        LabeledContent(
                            "Wake Words",
                            value: VoiceWakePreferences.displayString(for: self.voiceWake.triggerWords))
                    }
                }

                Section("Camera") {
                    Toggle("Allow Camera", isOn: self.$cameraEnabled)
                    Text("Allows the gateway to request photos or short video clips (foreground only).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Location") {
                    Picker("Location Access", selection: self.$locationEnabledModeRaw) {
                        Text("Off").tag(OpenClawLocationMode.off.rawValue)
                        Text("While Using").tag(OpenClawLocationMode.whileUsing.rawValue)
                        Text("Always").tag(OpenClawLocationMode.always.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Precise Location", isOn: self.$locationPreciseEnabled)
                        .disabled(self.locationMode == .off)

                    Text("Always requires system permission and may prompt to open Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Screen") {
                    Toggle("Prevent Sleep", isOn: self.$preventSleep)
                    Text("Keeps the screen awake while OpenClaw is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Troubleshooting") {
                    Button("Run Onboarding Again") {
                        OnboardingStateStore.markIncomplete()
                        self.onboardingRequestID += 1
                        self.dismiss()
                    }

                    Button("Reset Onboarding", role: .destructive) {
                        self.resetOnboardingConfirmPresented = true
                    }

                    Text("Clears node identity + pairing cache and keeps gateway auth credentials.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(
                "Reset onboarding?",
                isPresented: self.$resetOnboardingConfirmPresented,
                titleVisibility: .visible)
            {
                Button("Reset Onboarding", role: .destructive) {
                    self.resetOnboarding()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will disconnect from the gateway and generate a new node instance ID.")
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                self.localIPAddress = Self.primaryIPv4Address()
                self.lastLocationModeRaw = self.locationEnabledModeRaw
                let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedInstanceId.isEmpty {
                    self.gatewayToken = GatewaySettingsStore.loadGatewayToken(instanceId: trimmedInstanceId) ?? ""
                    self.gatewayPassword = GatewaySettingsStore.loadGatewayPassword(instanceId: trimmedInstanceId) ?? ""
                }
            }
            .onDisappear {
                self.discoveryRestartTask?.cancel()
                self.discoveryRestartTask = nil
            }
            .onChange(of: self.preferredGatewayStableID) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                GatewaySettingsStore.savePreferredGatewayStableID(trimmed)
            }
            .onChange(of: self.gatewayToken) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let instanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instanceId.isEmpty else { return }
                GatewaySettingsStore.saveGatewayToken(trimmed, instanceId: instanceId)
            }
            .onChange(of: self.gatewayPassword) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let instanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instanceId.isEmpty else { return }
                GatewaySettingsStore.saveGatewayPassword(trimmed, instanceId: instanceId)
            }
            .onChange(of: self.appModel.gatewayServerName) { _, _ in
                self.connectStatus.text = nil
            }
            .onChange(of: self.locationEnabledModeRaw) { _, newValue in
                let previous = self.lastLocationModeRaw
                self.lastLocationModeRaw = newValue
                guard let mode = OpenClawLocationMode(rawValue: newValue) else { return }
                Task {
                    let granted = await self.appModel.requestLocationPermissions(mode: mode)
                    if !granted {
                        await MainActor.run {
                            self.locationEnabledModeRaw = previous
                            self.lastLocationModeRaw = previous
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gatewayList(showing: GatewayListMode) -> some View {
        if self.gatewayController.gateways.isEmpty {
            Text("No gateways found yet.")
                .foregroundStyle(.secondary)
        } else {
            let connectedID = self.appModel.connectedGatewayID
            let rows = self.gatewayController.gateways.filter { gateway in
                let isConnected = gateway.stableID == connectedID
                switch showing {
                case .all:
                    return true
                case .availableOnly:
                    return !isConnected
                }
            }

            if rows.isEmpty, showing == .availableOnly {
                Text("No other gateways found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { gateway in
                    let hasLanHost = !(gateway.lanHost?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    let hasTailnetHost = !(gateway.tailnetDns?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    let hasHost = hasLanHost || hasTailnetHost

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gateway.name)
                            let detailLines = self.gatewayDetailLines(gateway)
                            ForEach(detailLines, id: \.self) { line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        Button {
                            Task { await self.connect(gateway) }
                        } label: {
                            if self.connectingGatewayID == gateway.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else if !hasHost {
                                Text("Resolving…")
                            } else {
                                Text("Connect")
                            }
                        }
                        .disabled(self.connectingGatewayID != nil || !hasHost)
                    }
                }
            }
        }
    }

    private enum GatewayListMode: Equatable {
        case all
        case availableOnly
    }

    private func platformString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var locationMode: OpenClawLocationMode {
        OpenClawLocationMode(rawValue: self.locationEnabledModeRaw) ?? .off
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
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

    private func connect(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        self.connectingGatewayID = gateway.id
        self.manualGatewayEnabled = false
        self.preferredGatewayStableID = gateway.stableID
        GatewaySettingsStore.savePreferredGatewayStableID(gateway.stableID)
        self.lastDiscoveredGatewayStableID = gateway.stableID
        GatewaySettingsStore.saveLastDiscoveredGatewayStableID(gateway.stableID)
        defer { self.connectingGatewayID = nil }

        await self.gatewayController.connect(gateway)
    }

    private func connectManual() async {
        let host = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            self.connectStatus.text = "Failed: host required"
            return
        }
        guard self.manualGatewayPort > 0, self.manualGatewayPort <= 65535 else {
            self.connectStatus.text = "Failed: invalid port"
            return
        }

        self.connectingGatewayID = "manual"
        self.manualGatewayEnabled = true
        defer { self.connectingGatewayID = nil }

        await self.gatewayController.connectManual(
            host: host,
            port: self.manualGatewayPort,
            useTLS: self.manualGatewayTLS)
    }

    private func scheduleDiscoveryRestart() {
        self.discoveryRestartTask?.cancel()
        self.discoveryRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.gatewayController.restartDiscovery()
        }
    }

    private static func primaryIPv4Address() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        var fallback: String?
        var en0: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let name = String(cString: ptr.pointee.ifa_name)
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if !isUp || isLoopback || family != UInt8(AF_INET) { continue }

            var addr = ptr.pointee.ifa_addr.pointee
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                &addr,
                socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST)
            guard result == 0 else { continue }
            let len = buffer.prefix { $0 != 0 }
            let bytes = len.map { UInt8(bitPattern: $0) }
            guard let ip = String(bytes: bytes, encoding: .utf8) else { continue }

            if name == "en0" { en0 = ip; break }
            if fallback == nil { fallback = ip }
        }

        return en0 ?? fallback
    }

    private static func parseHostPort(from address: String) -> SettingsHostPort? {
        SettingsNetworkingHelpers.parseHostPort(from: address)
    }

    private static func httpURLString(host: String?, port: Int?, fallback: String) -> String {
        SettingsNetworkingHelpers.httpURLString(host: host, port: port, fallback: fallback)
    }

    private func gatewayDetailLines(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> [String] {
        var lines: [String] = []
        if let lanHost = gateway.lanHost { lines.append("LAN: \(lanHost)") }
        if let tailnet = gateway.tailnetDns { lines.append("Tailnet: \(tailnet)") }

        let gatewayPort = gateway.gatewayPort
        let canvasPort = gateway.canvasPort
        if gatewayPort != nil || canvasPort != nil {
            let gw = gatewayPort.map(String.init) ?? "—"
            let canvas = canvasPort.map(String.init) ?? "—"
            lines.append("Ports: gateway \(gw) · canvas \(canvas)")
        }

        if lines.isEmpty {
            lines.append(gateway.debugID)
        }

        return lines
    }

    private func resetOnboarding() {
        let oldInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Best-effort: capture current connection info before disconnect (helps reset+reconnect on builds
        // that didn't yet persist lastHost/lastPort).
        let currentParts = self.appModel.gatewayRemoteAddress.flatMap(Self.parseHostPort(from:))

        // Keep gateway auth across onboarding resets (pairing identity changes; gateway auth doesn't).
        let preservedToken =
            GatewaySettingsStore.loadGatewayToken(instanceId: oldInstanceId) ?? self.gatewayToken
        let preservedPassword =
            GatewaySettingsStore.loadGatewayPassword(instanceId: oldInstanceId) ?? self.gatewayPassword

        self.appModel.disconnectGateway()

        // Gateway pairing can persist via device-scoped tokens; clear those too.
        DeviceAuthStore.reset()
        DeviceIdentityStore.reset()

        let freshInstanceId = UUID().uuidString
        self.instanceId = freshInstanceId
        GatewaySettingsStore.saveStableInstanceID(freshInstanceId)

        self.gatewayToken = preservedToken
        self.gatewayPassword = preservedPassword
        let trimmedToken = preservedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            GatewaySettingsStore.saveGatewayToken(trimmedToken, instanceId: freshInstanceId)
        }
        let trimmedPassword = preservedPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPassword.isEmpty {
            GatewaySettingsStore.saveGatewayPassword(trimmedPassword, instanceId: freshInstanceId)
        }

        self.connectStatus.text = "Onboarding reset"
        self.gatewayController.restartDiscovery()

        let defaults = UserDefaults.standard
        let manualEnabled = defaults.bool(forKey: "gateway.manual.enabled")
        let manualHost = defaults.string(forKey: "gateway.manual.host")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let manualPort = defaults.integer(forKey: "gateway.manual.port")
        let resolvedPort = manualPort > 0 ? manualPort : 18789
        let manualTLS = defaults.bool(forKey: "gateway.manual.tls")

        let fallback = GatewayConnectionController.loadLastConnection(defaults: defaults)

        let host: String
        let port: Int
        let tls: Bool
        if manualEnabled, !manualHost.isEmpty {
            host = manualHost
            port = resolvedPort
            tls = manualTLS
        } else if let fallback {
            host = fallback.host
            port = fallback.port
            tls = fallback.useTLS
        } else if let currentParts {
            host = currentParts.host
            port = currentParts.port
            tls = manualTLS
        } else {
            self.gatewayController.allowAutoConnectAgain()
            return
        }

        self.connectStatus.text = "Reconnecting to \(host)…"
        self.connectingGatewayID = "reset"
        Task {
            await self.gatewayController.connectManual(host: host, port: port, useTLS: tls)
            await MainActor.run { self.connectingGatewayID = nil }
        }
    }
}
