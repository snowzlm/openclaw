import OpenClawKit
import SwiftUI
import UIKit

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case mode
    case connect
    case auth
    case success

    var progressTitle: String {
        switch self {
        case .welcome:
            "Step 1 of 5"
        case .mode:
            "Step 2 of 5"
        case .connect:
            "Step 3 of 5"
        case .auth:
            "Step 4 of 5"
        case .success:
            "Step 5 of 5"
        }
    }
}

struct OnboardingWizardView: View {
    @Environment(NodeAppModel.self) private var appModel: NodeAppModel
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString
    @AppStorage("gateway.discovery.domain") private var discoveryDomain: String = ""
    @AppStorage("onboarding.developerMode") private var developerModeEnabled: Bool = false
    @State private var step: OnboardingStep = .welcome
    @State private var selectedMode: OnboardingConnectionMode?
    @State private var manualHost: String = ""
    @State private var manualPort: Int = 18789
    @State private var manualTLS: Bool = true
    @State private var gatewayToken: String = ""
    @State private var gatewayPassword: String = ""
    @State private var connectMessage: String?
    @State private var connectingGatewayID: String?
    @State private var issue: GatewayConnectionIssue = .none
    @State private var didMarkCompleted = false
    @State private var discoveryRestartTask: Task<Void, Never>?

    let allowSkip: Bool
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(self.step.progressTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                switch self.step {
                case .welcome:
                    self.welcomeStep
                case .mode:
                    self.modeStep
                case .connect:
                    self.connectStep
                case .auth:
                    self.authStep
                case .success:
                    self.successStep
                }
            }
            .navigationTitle("OpenClaw Setup")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if self.allowSkip {
                        Button("Close") {
                            self.onClose()
                        }
                    }
                }
            }
        }
        .onAppear {
            self.initializeState()
        }
        .onDisappear {
            self.discoveryRestartTask?.cancel()
            self.discoveryRestartTask = nil
        }
        .onChange(of: self.discoveryDomain) { _, _ in
            self.scheduleDiscoveryRestart()
        }
        .onChange(of: self.gatewayToken) { _, newValue in
            self.saveGatewayCredentials(token: newValue, password: self.gatewayPassword)
        }
        .onChange(of: self.gatewayPassword) { _, newValue in
            self.saveGatewayCredentials(token: self.gatewayToken, password: newValue)
        }
        .onChange(of: self.appModel.gatewayStatusText) { _, newValue in
            let next = GatewayConnectionIssue.detect(from: newValue)
            self.issue = next
            if self.step == .connect && (next.needsAuthToken || next.needsPairing) {
                self.step = .auth
            }
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.connectMessage = newValue
            }
        }
        .onChange(of: self.appModel.gatewayServerName) { _, newValue in
            guard newValue != nil else { return }
            self.step = .success
            if !self.didMarkCompleted, let selectedMode {
                OnboardingStateStore.markCompleted(mode: selectedMode)
                self.didMarkCompleted = true
            }
        }
    }

    private var welcomeStep: some View {
        Section("Welcome") {
            Text("Connect this iOS node to your OpenClaw gateway.")
            Text("Pick your connection mode, connect, then approve pairing if prompted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Continue") {
                self.step = .mode
            }
        }
    }

    @ViewBuilder
    private var modeStep: some View {
        Section("Connection Mode") {
            OnboardingModeRow(
                title: OnboardingConnectionMode.homeNetwork.title,
                subtitle: "LAN or Tailscale host",
                selected: self.selectedMode == .homeNetwork)
            {
                self.selectMode(.homeNetwork)
            }

            OnboardingModeRow(
                title: OnboardingConnectionMode.remoteDomain.title,
                subtitle: "VPS with domain",
                selected: self.selectedMode == .remoteDomain)
            {
                self.selectMode(.remoteDomain)
            }

            Toggle(
                "Developer mode",
                isOn: Binding(
                    get: { self.developerModeEnabled },
                    set: { newValue in
                        self.developerModeEnabled = newValue
                        if !newValue, self.selectedMode == .developerLocal {
                            self.selectedMode = nil
                        }
                    }))

            if self.developerModeEnabled {
                OnboardingModeRow(
                    title: OnboardingConnectionMode.developerLocal.title,
                    subtitle: "For local iOS app development",
                    selected: self.selectedMode == .developerLocal)
                {
                    self.selectMode(.developerLocal)
                }
            }
        }

        Section {
            Button("Continue") {
                self.step = .connect
            }
            .disabled(self.selectedMode == nil)
        }
    }

    @ViewBuilder
    private var connectStep: some View {
        if let selectedMode {
            Section("Connect") {
                Text(selectedMode.title)
                    .font(.headline)
                LabeledContent("Discovery", value: self.gatewayController.discoveryStatusText)
                LabeledContent("Status", value: self.appModel.gatewayStatusText)
            }

            switch selectedMode {
            case .homeNetwork:
                self.homeNetworkConnectSection
            case .remoteDomain:
                self.remoteDomainConnectSection
            case .developerLocal:
                self.developerConnectSection
            }
        } else {
            Section {
                Text("Choose a mode first.")
                Button("Back to Mode Selection") {
                    self.step = .mode
                }
            }
        }

        if let connectMessage {
            Section {
                Text(connectMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var homeNetworkConnectSection: some View {
        Group {
            Section("Discovered Gateways") {
                if self.gatewayController.gateways.isEmpty {
                    Text("No gateways found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(self.gatewayController.gateways) { gateway in
                        let hasHost = self.gatewayHasResolvableHost(gateway)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gateway.name)
                                if let host = gateway.lanHost ?? gateway.tailnetDns {
                                    Text(host)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await self.connectDiscoveredGateway(gateway) }
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

                Button("Restart Discovery") {
                    self.gatewayController.restartDiscovery()
                }
                .disabled(self.connectingGatewayID != nil)
            }

            self.manualConnectionFieldsSection(title: "Manual Fallback")
        }
    }

    private var remoteDomainConnectSection: some View {
        Group {
            self.manualConnectionFieldsSection(title: "Domain Settings")

            Section("TLS") {
                Text("TLS stays enabled by default for internet-facing gateways.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var developerConnectSection: some View {
        Group {
            Section("Developer Local") {
                TextField("Host", text: self.$manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", value: self.$manualPort, format: .number)
                    .keyboardType(.numberPad)
                Toggle("Use TLS", isOn: self.$manualTLS)

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
                        Text("Connect")
                    }
                }
                .disabled(!self.canConnectManual || self.connectingGatewayID != nil)
            }

            Section {
                Text("Default host is localhost. Use your Mac LAN IP if simulator networking requires it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authStep: some View {
        Group {
            Section("Authentication") {
                if self.issue.needsAuthToken {
                    TextField("Gateway Auth Token", text: self.$gatewayToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Gateway Password", text: self.$gatewayPassword)
                } else {
                    Text("Auth token looks valid.")
                }
            }

            if self.issue.needsPairing {
                Section("Pairing Approval") {
                    Text("On gateway host run:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Copy: openclaw devices list") {
                        UIPasteboard.general.string = "openclaw devices list"
                    }

                    if let id = self.issue.requestId {
                        Button("Copy: openclaw devices approve \(id)") {
                            UIPasteboard.general.string = "openclaw devices approve \(id)"
                        }
                    } else {
                        Button("Copy: openclaw devices approve <requestId>") {
                            UIPasteboard.general.string = "openclaw devices approve <requestId>"
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await self.retryLastAttempt() }
                } label: {
                    if self.connectingGatewayID == "retry" {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Retry Connection")
                    }
                }
                .disabled(self.connectingGatewayID != nil)
            }
        }
    }

    private var successStep: some View {
        Section("Connected") {
            let server = self.appModel.gatewayServerName ?? "gateway"
            Text("Connected to \(server).")
            if let addr = self.appModel.gatewayRemoteAddress {
                Text(addr)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Open OpenClaw") {
                self.onClose()
            }
        }
    }

    @ViewBuilder
    private func manualConnectionFieldsSection(title: String) -> some View {
        Section(title) {
            TextField("Host", text: self.$manualHost)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Port", value: self.$manualPort, format: .number)
                .keyboardType(.numberPad)
            Toggle("Use TLS", isOn: self.$manualTLS)
            TextField("Discovery Domain (optional)", text: self.$discoveryDomain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

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
                    Text("Connect")
                }
            }
            .disabled(!self.canConnectManual || self.connectingGatewayID != nil)
        }
    }

    private var canConnectManual: Bool {
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty && self.manualPort > 0 && self.manualPort <= 65535
    }

    private func initializeState() {
        if self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = GatewayConnectionController.loadLastConnection(defaults: .standard) {
                self.manualHost = last.host
                self.manualPort = last.port
                self.manualTLS = last.useTLS
            } else {
                self.manualHost = "openclaw.local"
                self.manualPort = 18789
                self.manualTLS = true
            }
        }
        if self.selectedMode == nil {
            self.selectedMode = OnboardingStateStore.lastMode()
        }
        if self.selectedMode == .developerLocal && self.manualHost == "openclaw.local" {
            self.manualHost = "localhost"
            self.manualTLS = false
        }

        let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstanceId.isEmpty {
            self.gatewayToken = GatewaySettingsStore.loadGatewayToken(instanceId: trimmedInstanceId) ?? ""
            self.gatewayPassword = GatewaySettingsStore.loadGatewayPassword(instanceId: trimmedInstanceId) ?? ""
        }
    }

    private func scheduleDiscoveryRestart() {
        self.discoveryRestartTask?.cancel()
        self.discoveryRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.gatewayController.restartDiscovery()
        }
    }

    private func saveGatewayCredentials(token: String, password: String) {
        let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstanceId.isEmpty else { return }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        GatewaySettingsStore.saveGatewayToken(trimmedToken, instanceId: trimmedInstanceId)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        GatewaySettingsStore.saveGatewayPassword(trimmedPassword, instanceId: trimmedInstanceId)
    }

    private func connectDiscoveredGateway(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        self.connectingGatewayID = gateway.id
        self.connectMessage = "Connecting to \(gateway.name)…"
        defer { self.connectingGatewayID = nil }
        await self.gatewayController.connect(gateway)
    }

    private func selectMode(_ mode: OnboardingConnectionMode) {
        self.selectedMode = mode
        self.applyModeDefaults(mode)
    }

    private func applyModeDefaults(_ mode: OnboardingConnectionMode) {
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hostIsDefaultLike = host.isEmpty || host == "openclaw.local" || host == "localhost"

        switch mode {
        case .homeNetwork:
            if hostIsDefaultLike { self.manualHost = "openclaw.local" }
            self.manualTLS = true
            if self.manualPort <= 0 || self.manualPort > 65535 { self.manualPort = 18789 }
        case .remoteDomain:
            if host == "openclaw.local" || host == "localhost" { self.manualHost = "" }
            self.manualTLS = true
            if self.manualPort <= 0 || self.manualPort > 65535 { self.manualPort = 18789 }
        case .developerLocal:
            if hostIsDefaultLike { self.manualHost = "localhost" }
            self.manualTLS = false
            if self.manualPort <= 0 || self.manualPort > 65535 { self.manualPort = 18789 }
        }
    }

    private func gatewayHasResolvableHost(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> Bool {
        let lanHost = gateway.lanHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lanHost.isEmpty { return true }
        let tailnetDns = gateway.tailnetDns?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !tailnetDns.isEmpty
    }

    private func connectManual() async {
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, self.manualPort > 0, self.manualPort <= 65535 else { return }
        self.connectingGatewayID = "manual"
        self.connectMessage = "Connecting to \(host)…"
        defer { self.connectingGatewayID = nil }
        await self.gatewayController.connectManual(host: host, port: self.manualPort, useTLS: self.manualTLS)
    }

    private func retryLastAttempt() async {
        self.connectingGatewayID = "retry"
        self.connectMessage = "Retrying…"
        defer { self.connectingGatewayID = nil }
        await self.gatewayController.reconnectLastAttempt()
    }
}

private struct OnboardingModeRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.body.weight(.semibold))
                    Text(self.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: self.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(self.selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
