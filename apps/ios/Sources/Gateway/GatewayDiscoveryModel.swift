import OpenClawKit
import Foundation
import Network
import Observation

@MainActor
@Observable
final class GatewayDiscoveryModel {
    struct ResolvedTXT: Equatable {
        var txt: [String: String]
        var hostName: String?
        var port: Int?
    }

    struct DebugLogEntry: Identifiable, Equatable {
        var id = UUID()
        var ts: Date
        var message: String
    }

    struct DiscoveredGateway: Identifiable, Equatable {
        var id: String { self.stableID }
        var name: String
        var endpoint: NWEndpoint
        var stableID: String
        var debugID: String
        var lanHost: String?
        var tailnetDns: String?
        var gatewayPort: Int?
        var canvasPort: Int?
        var tlsEnabled: Bool
        var tlsFingerprintSha256: String?
        var cliPath: String?
    }

    var gateways: [DiscoveredGateway] = []
    var statusText: String = "Idle"
    private(set) var debugLog: [DebugLogEntry] = []

    private var browsers: [String: NWBrowser] = [:]
    private var resultsByDomain: [String: Set<NWBrowser.Result>] = [:]
    private var gatewaysByDomain: [String: [DiscoveredGateway]] = [:]
    private var statesByDomain: [String: NWBrowser.State] = [:]
    private var resolvedByID: [String: ResolvedTXT] = [:]
    private var pendingResolvers: [String: GatewayTXTResolver] = [:]
    private var debugLoggingEnabled = false
    private var lastStableIDs = Set<String>()

    func setDebugLoggingEnabled(_ enabled: Bool) {
        let wasEnabled = self.debugLoggingEnabled
        self.debugLoggingEnabled = enabled
        if !enabled {
            self.debugLog = []
        } else if !wasEnabled {
            self.appendDebugLog("debug logging enabled")
            self.appendDebugLog("snapshot: status=\(self.statusText) gateways=\(self.gateways.count)")
        }
    }

    func start() {
        if !self.browsers.isEmpty { return }
        self.appendDebugLog("start()")

        for domain in Self.discoveryDomains() {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjour(type: OpenClawBonjour.gatewayServiceType, domain: domain),
                using: params)

            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.statesByDomain[domain] = state
                    self.updateStatusText()
                    self.appendDebugLog("state[\(domain)]: \(Self.prettyState(state))")
                }
            }

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.resultsByDomain[domain] = results
                    self.updateGateways(for: domain)
                    self.recomputeGateways()
                }
            }

            self.browsers[domain] = browser
            browser.start(queue: DispatchQueue(label: "bot.molt.ios.gateway-discovery.\(domain)"))
        }
    }

    func stop() {
        self.appendDebugLog("stop()")
        for browser in self.browsers.values {
            browser.cancel()
        }
        self.browsers = [:]
        self.resultsByDomain = [:]
        self.gatewaysByDomain = [:]
        self.statesByDomain = [:]
        self.resolvedByID = [:]
        self.pendingResolvers.values.forEach { $0.cancel() }
        self.pendingResolvers = [:]
        self.gateways = []
        self.statusText = "Stopped"
    }

    private func updateGateways(for domain: String) {
        guard let results = self.resultsByDomain[domain] else {
            self.gatewaysByDomain[domain] = []
            return
        }

        self.gatewaysByDomain[domain] = results.compactMap { result -> DiscoveredGateway? in
            guard case let .service(name, type, resultDomain, _) = result.endpoint else { return nil }

            let stableID = GatewayEndpointID.stableID(result.endpoint)
            let resolved = self.resolvedByID[stableID]
            let txt = Self.txtDictionary(from: result).merging(
                resolved?.txt ?? [:],
                uniquingKeysWith: { _, new in new })

            let decodedName = BonjourEscapes.decode(name)
            let advertisedName = txt["displayName"]
            let prettyAdvertised = advertisedName
                .map(Self.prettifyInstanceName)
                .flatMap { $0.isEmpty ? nil : $0 }
            let prettyName = prettyAdvertised ?? Self.prettifyInstanceName(decodedName)

            var lanHost = Self.txtValue(txt, key: "lanHost")
            if lanHost == nil {
                lanHost = Self.trimmed(resolved?.hostName)
            }
            let tailnetDns = Self.txtValue(txt, key: "tailnetDns")
            let gatewayPort = Self.txtIntValue(txt, key: "gatewayPort") ?? resolved?.port

            if Self.trimmed(lanHost) == nil && Self.trimmed(tailnetDns) == nil {
                self.ensureTXTResolution(
                    stableID: stableID,
                    serviceName: name,
                    type: type,
                    domain: resultDomain)
            }

            return DiscoveredGateway(
                name: prettyName,
                endpoint: result.endpoint,
                stableID: stableID,
                debugID: GatewayEndpointID.prettyDescription(result.endpoint),
                lanHost: Self.trimmed(lanHost),
                tailnetDns: tailnetDns,
                gatewayPort: gatewayPort,
                canvasPort: Self.txtIntValue(txt, key: "canvasPort"),
                tlsEnabled: Self.txtBoolValue(txt, key: "gatewayTls"),
                tlsFingerprintSha256: Self.txtValue(txt, key: "gatewayTlsSha256"),
                cliPath: Self.txtValue(txt, key: "cliPath"))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateGatewaysForAllDomains() {
        for domain in self.resultsByDomain.keys {
            self.updateGateways(for: domain)
        }
    }

    private func ensureTXTResolution(
        stableID: String,
        serviceName: String,
        type: String,
        domain: String)
    {
        guard self.resolvedByID[stableID] == nil else { return }
        guard self.pendingResolvers[stableID] == nil else { return }

        let resolver = GatewayTXTResolver(name: serviceName, type: type, domain: domain) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.pendingResolvers[stableID] = nil
                switch result {
                case let .success(resolved):
                    self.resolvedByID[stableID] = resolved
                    self.updateGatewaysForAllDomains()
                    self.recomputeGateways()
                case .failure:
                    break
                }
            }
        }

        self.pendingResolvers[stableID] = resolver
        resolver.start()
    }

    private func recomputeGateways() {
        let next = self.gatewaysByDomain.values
            .flatMap(\.self)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let nextIDs = Set(next.map(\.stableID))
        let added = nextIDs.subtracting(self.lastStableIDs)
        let removed = self.lastStableIDs.subtracting(nextIDs)
        if !added.isEmpty || !removed.isEmpty {
            self.appendDebugLog("results: total=\(next.count) added=\(added.count) removed=\(removed.count)")
        }
        self.lastStableIDs = nextIDs
        self.gateways = next
        self.updateStatusText()
    }

    private func updateStatusText() {
        let states = Array(self.statesByDomain.values)
        if states.isEmpty {
            self.statusText = self.browsers.isEmpty ? "Idle" : "Setup"
            return
        }

        if let failed = states.first(where: { state in
            if case .failed = state { return true }
            return false
        }) {
            if case let .failed(err) = failed {
                self.statusText = "Failed: \(err)"
                return
            }
        }

        if let waiting = states.first(where: { state in
            if case .waiting = state { return true }
            return false
        }) {
            if case let .waiting(err) = waiting {
                self.statusText = "Waiting: \(err)"
                return
            }
        }

        if states.contains(where: { if case .ready = $0 { true } else { false } }) {
            let count = self.gateways.count
            if count == 1 {
                self.statusText = "Ready: 1 gateway"
            } else if count > 1 {
                self.statusText = "Ready: \(count) gateways"
            } else {
                self.statusText = "Ready"
            }
            return
        }

        if states.contains(where: { if case .setup = $0 { true } else { false } }) {
            self.statusText = "Setup"
            return
        }

        self.statusText = "Searching…"
    }

    private static func prettyState(_ state: NWBrowser.State) -> String {
        switch state {
        case .setup:
            "setup"
        case .ready:
            "ready"
        case let .failed(err):
            "failed (\(err))"
        case .cancelled:
            "cancelled"
        case let .waiting(err):
            "waiting (\(err))"
        @unknown default:
            "unknown"
        }
    }

    private func appendDebugLog(_ message: String) {
        guard self.debugLoggingEnabled else { return }
        self.debugLog.append(DebugLogEntry(ts: Date(), message: message))
        if self.debugLog.count > 200 {
            self.debugLog.removeFirst(self.debugLog.count - 200)
        }
    }

    private static func trimmed(_ raw: String?) -> String? {
        var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".") {
            value = String(value.dropLast())
        }
        return value.isEmpty ? nil : value
    }

    private static func prettifyInstanceName(_ decodedName: String) -> String {
        let normalized = decodedName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let stripped = normalized.replacingOccurrences(of: " (OpenClaw)", with: "")
            .replacingOccurrences(of: #"\s+\(\d+\)$"#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func discoveryDomains(defaults: UserDefaults = .standard) -> [String] {
        var domains = OpenClawBonjour.gatewayServiceDomains
        let raw = defaults.string(forKey: "gateway.discovery.domain")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return domains }
        let normalized = OpenClawBonjour.normalizeServiceDomain(raw)
        if normalized != OpenClawBonjour.gatewayServiceDomain, !domains.contains(normalized) {
            domains.append(normalized)
        }
        return domains
    }

    private static func txtValue(_ dict: [String: String], key: String) -> String? {
        let raw = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private static func txtIntValue(_ dict: [String: String], key: String) -> Int? {
        guard let raw = self.txtValue(dict, key: key) else { return nil }
        return Int(raw)
    }

    private static func txtBoolValue(_ dict: [String: String], key: String) -> Bool {
        guard let raw = self.txtValue(dict, key: key)?.lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    private static func txtDictionary(from result: NWBrowser.Result) -> [String: String] {
        var merged: [String: String] = [:]

        if case let .bonjour(txt) = result.metadata {
            merged.merge(txt.dictionary, uniquingKeysWith: { _, new in new })
        }

        if let endpointTxt = result.endpoint.txtRecord?.dictionary {
            merged.merge(endpointTxt, uniquingKeysWith: { _, new in new })
        }

        return merged
    }
}

final class GatewayTXTResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private let completion: (Result<GatewayDiscoveryModel.ResolvedTXT, Error>) -> Void
    private var didFinish = false

    init(
        name: String,
        type: String,
        domain: String,
        completion: @escaping (Result<GatewayDiscoveryModel.ResolvedTXT, Error>) -> Void)
    {
        self.service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        self.service.delegate = self
    }

    func start(timeout: TimeInterval = 2.0) {
        self.service.schedule(in: .main, forMode: .common)
        self.service.resolve(withTimeout: timeout)
    }

    func cancel() {
        self.finish(result: .failure(GatewayTXTResolverError.cancelled))
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let txt = Self.decodeTXT(sender.txtRecordData())
        let hostName = sender.hostName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = sender.port > 0 ? sender.port : nil
        self.finish(result: .success(GatewayDiscoveryModel.ResolvedTXT(txt: txt, hostName: hostName, port: port)))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        self.finish(result: .failure(GatewayTXTResolverError.resolveFailed(errorDict)))
    }

    private func finish(result: Result<GatewayDiscoveryModel.ResolvedTXT, Error>) {
        guard !self.didFinish else { return }
        self.didFinish = true
        self.service.stop()
        self.service.remove(from: .main, forMode: .common)
        self.completion(result)
    }

    private static func decodeTXT(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        let dict = NetService.dictionary(fromTXTRecord: data)
        var out: [String: String] = [:]
        out.reserveCapacity(dict.count)
        for (key, value) in dict {
            if let str = String(data: value, encoding: .utf8) {
                out[key] = str
            }
        }
        return out
    }
}

enum GatewayTXTResolverError: Error {
    case cancelled
    case resolveFailed([String: NSNumber])
}
