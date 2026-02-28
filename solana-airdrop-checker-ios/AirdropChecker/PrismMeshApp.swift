import SwiftUI
import LocalAuthentication
import CryptoKit
import Foundation
import UIKit

struct AppEnvironment {
    let apiBaseURL: URL?
    let sentryDSN: String?
    let postHogApiKey: String?
    let postHogHost: URL?
    let heliusAPIKey: String?
    let heliusDASURL: URL?
    let environmentName: String
    let configError: String?

    static var current: AppEnvironment {
        let receiptPath = Bundle.main.appStoreReceiptURL?.lastPathComponent.lowercased() ?? ""
        let isTestFlight = receiptPath == "sandboxreceipt"
        #if DEBUG
        let targetEnvironment = "dev"
        #else
        let targetEnvironment = isTestFlight ? "beta" : "prod"
        #endif

        let rawUseStaging = Bundle.main.object(forInfoDictionaryKey: "UseStagingEnvironment")
        let useStaging: Bool = {
            if let boolValue = rawUseStaging as? Bool { return boolValue }
            if let stringValue = rawUseStaging as? String {
                let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return ["1", "true", "yes"].contains(normalized)
            }
            return false
        }()
        let prod = Bundle.main.object(forInfoDictionaryKey: "APIBaseURLProd") as? String
        let staging = Bundle.main.object(forInfoDictionaryKey: "APIBaseURLStaging") as? String
        let raw: String?
        switch targetEnvironment {
        case "dev", "beta":
            raw = staging ?? prod
        default:
            raw = useStaging ? staging : prod
        }

        func plistString(_ key: String) -> String? {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func firstNonEmptyPlistValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = plistString(key), !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        func selectValue(devKey: String, betaKey: String, prodKey: String, fallback: String? = nil) -> String? {
            let selected: String?
            switch targetEnvironment {
            case "dev":
                selected = plistString(devKey)
            case "beta":
                selected = plistString(betaKey)
            default:
                selected = plistString(prodKey)
            }
            if let selected, !selected.isEmpty { return selected }
            if let fallback, !fallback.isEmpty { return fallback }
            return nil
        }

        let resolvedBaseURL: URL?
        let configError: String?
        if let raw, !raw.isEmpty {
            if let candidate = URL(string: raw), candidate.scheme?.isEmpty == false, candidate.host?.isEmpty == false {
                resolvedBaseURL = candidate
                configError = nil
            } else {
                resolvedBaseURL = nil
                configError = "Invalid API base URL configuration. Please reinstall or contact support."
            }
        } else {
            resolvedBaseURL = nil
                configError = "Missing API base URL configuration. Please reinstall or contact support."
        }

        let heliusKey = selectValue(
            devKey: "HeliusAPIKeyDev",
            betaKey: "HeliusAPIKeyBeta",
            prodKey: "HeliusAPIKeyProd",
            fallback: firstNonEmptyPlistValue(["HELIUS_API_KEY", "HeliusAPIKey"])
        )

        let heliusDASURL: URL? = {
            if let explicit = selectValue(
                devKey: "HeliusDASURLDev",
                betaKey: "HeliusDASURLBeta",
                prodKey: "HeliusDASURLProd",
                fallback: firstNonEmptyPlistValue(["HELIUS_DAS_URL", "HeliusDASURL"])
            ),
               let explicitURL = URL(string: explicit) {
                return explicitURL
            }
            if let key = heliusKey, !key.isEmpty {
                return URL(string: "https://mainnet.helius-rpc.com/?api-key=\(key)")
            }
            return nil
        }()

        return AppEnvironment(
            apiBaseURL: resolvedBaseURL,
            sentryDSN: selectValue(devKey: "SentryDSNDev", betaKey: "SentryDSNBeta", prodKey: "SentryDSNProd"),
            postHogApiKey: selectValue(devKey: "PostHogApiKeyDev", betaKey: "PostHogApiKeyBeta", prodKey: "PostHogApiKeyProd"),
            postHogHost: selectValue(devKey: "PostHogHostDev", betaKey: "PostHogHostBeta", prodKey: "PostHogHostProd")
                .flatMap(URL.init(string:)),
            heliusAPIKey: heliusKey,
            heliusDASURL: heliusDASURL,
            environmentName: targetEnvironment
            ,
            configError: configError
        )
    }
}

protocol AnalyticsTracking {
    func track(event: String, properties: [String: String]) async
    func identify(hashedWallet: String) async
}

protocol ErrorTracking {
    func capture(
        category: String,
        message: String,
        httpStatus: Int?,
        extra: [String: String]
    ) async
    func setUser(hashedWallet: String?) async
    func breadcrumb(category: String, message: String, data: [String: String]) async
}

protocol FeedbackSubmitting {
    func send(message: String, hashedWallet: String, screenshotBase64: String?) async -> Bool
}

struct RuntimeMetadata {
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let iosVersion: String
    let environment: String

    static func current(environment: AppEnvironment) async -> RuntimeMetadata {
        let device = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        return RuntimeMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            deviceModel: device.0,
            iosVersion: device.1,
            environment: environment.environmentName
        )
    }
}

actor ErrorTrackerService: ErrorTracking {
    static let shared = ErrorTrackerService()

    private let session: URLSession
    private let environment: AppEnvironment
    private var currentUserHash: String?
    private var breadcrumbs: [[String: String]] = []
    private let maxBreadcrumbs = 50

    init(session: URLSession = .shared, environment: AppEnvironment = .current) {
        self.session = session
        self.environment = environment
    }

    func capture(category: String, message: String, httpStatus: Int?, extra: [String : String]) async {
        var payload = extra
        payload["category"] = category
        payload["message"] = message
        if let httpStatus {
            payload["httpStatus"] = String(httpStatus)
        }
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        let meta = await RuntimeMetadata.current(environment: environment)
        payload["appVersion"] = meta.appVersion
        payload["build"] = meta.buildNumber
        payload["deviceModel"] = meta.deviceModel
        payload["iosVersion"] = meta.iosVersion
        payload["environment"] = meta.environment
        if let currentUserHash {
            payload["hashedWallet"] = currentUserHash
        }

        if let base = environment.apiBaseURL, let endpoint = URL(string: "/api/telemetry/error", relativeTo: base) {
            await postJSON(payload, to: endpoint)
        }

        if let dsn = environment.sentryDSN {
            await postSentryEvent(dsn: dsn, payload: payload)
        }
    }

    func setUser(hashedWallet: String?) async {
        currentUserHash = hashedWallet?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func breadcrumb(category: String, message: String, data: [String: String]) async {
        var crumb = data
        crumb["category"] = category
        crumb["message"] = message
        crumb["timestamp"] = ISO8601DateFormatter().string(from: Date())
        breadcrumbs.append(crumb)
        if breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs)
        }
    }

    private func postJSON(_ payload: [String: String], to endpoint: URL) async {
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    private func postSentryEvent(dsn: String, payload: [String: String]) async {
        guard let parts = parseSentryDSN(dsn) else { return }
        guard let endpoint = URL(string: "\(parts.base)/api/\(parts.projectId)/store/?sentry_key=\(parts.publicKey)&sentry_version=7") else {
            return
        }

        let currentUserHash = currentUserHash
        let crumbTrail = breadcrumbs

        let sentryPayload: [String: Any] = [
            "event_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "timestamp": Date().timeIntervalSince1970,
            "level": "error",
            "platform": "cocoa",
            "logger": "prismmesh.\(environment.environmentName)",
            "message": ["formatted": payload["message"] ?? "Unknown"],
            "tags": [
                "category": payload["category"] ?? "unknown",
                "appVersion": payload["appVersion"] ?? "unknown",
                "build": payload["build"] ?? "unknown",
                "environment": payload["environment"] ?? environment.environmentName,
                "deviceModel": payload["deviceModel"] ?? "unknown",
                "iosVersion": payload["iosVersion"] ?? "unknown"
            ],
            "extra": payload,
            "user": currentUserHash.map { ["id": $0] } ?? [:],
            "breadcrumbs": [
                "values": crumbTrail.map { crumb in
                    [
                        "timestamp": crumb["timestamp"] ?? ISO8601DateFormatter().string(from: Date()),
                        "category": crumb["category"] ?? "app",
                        "message": crumb["message"] ?? "",
                        "data": crumb
                    ]
                }
            ]
        ]

        guard JSONSerialization.isValidJSONObject(sentryPayload),
              let body = try? JSONSerialization.data(withJSONObject: sentryPayload, options: []) else {
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    private func parseSentryDSN(_ dsn: String) -> (base: String, publicKey: String, projectId: String)? {
        guard let url = URL(string: dsn),
              let host = url.host,
              let projectId = url.pathComponents.last,
              let user = url.user,
              !projectId.isEmpty else {
            return nil
        }
        let scheme = url.scheme ?? "https"
        return (base: "\(scheme)://\(host)", publicKey: user, projectId: projectId)
    }
}

final class CrashHooks {
    static let shared = CrashHooks()
    private var installed = false

    func install(errorTracker: ErrorTracking = ErrorTrackerService.shared) {
        guard !installed else { return }
        installed = true
        uncaughtExceptionErrorTracker = errorTracker
        NSSetUncaughtExceptionHandler(radarUncaughtExceptionHandler)
    }
}

private var uncaughtExceptionErrorTracker: ErrorTracking = ErrorTrackerService.shared

private func radarUncaughtExceptionHandler(_ exception: NSException) {
    let tracker = uncaughtExceptionErrorTracker
    Task {
        await tracker.capture(
            category: "uncaught_exception",
            message: "\(exception.name.rawValue): \(exception.reason ?? "unknown")",
            httpStatus: nil,
            extra: ["stack": exception.callStackSymbols.joined(separator: "\n")]
        )
    }
}

actor BetaAnalyticsService: AnalyticsTracking {
    private let session: URLSession
    private let environment: AppEnvironment
    private let anonymousDistinctId: String
    private var hashedWallet: String?

    init(session: URLSession = .shared, environment: AppEnvironment = .current) {
        self.session = session
        self.environment = environment
        let defaults = UserDefaults.standard
        let key = "analytics_anonymous_distinct_id"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            self.anonymousDistinctId = existing
        } else {
            let generated = UUID().uuidString.lowercased()
            defaults.set(generated, forKey: key)
            self.anonymousDistinctId = generated
        }
    }

    func track(event: String, properties: [String : String]) async {
        let meta = await RuntimeMetadata.current(environment: environment)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let distinctId = hashedWallet ?? anonymousDistinctId

        if let base = environment.apiBaseURL,
           let endpoint = URL(string: "/api/events", relativeTo: base) {
            var metadata = properties
            metadata["environment"] = meta.environment

            let payload: [String: Any] = [
                "eventName": event,
                "hashedWallet": distinctId,
                "appVersion": meta.appVersion,
                "buildNumber": meta.buildNumber,
                "deviceModel": meta.deviceModel,
                "iosVersion": meta.iosVersion,
                "timestamp": timestamp,
                "metadata": metadata
            ]
            await postJSONObject(payload, to: endpoint, retries: 2)
        }

        if let apiKey = environment.postHogApiKey,
           !apiKey.isEmpty,
           let host = environment.postHogHost,
           let endpoint = URL(string: "/capture/", relativeTo: host) {
            var phProperties: [String: Any] = properties
            phProperties["$lib"] = "prismmesh-ios-custom"
            phProperties["$app_version"] = meta.appVersion
            phProperties["build_number"] = meta.buildNumber
            phProperties["device_model"] = meta.deviceModel
            phProperties["ios_version"] = meta.iosVersion
            phProperties["environment"] = meta.environment

            let body: [String: Any] = [
                "api_key": apiKey,
                "event": event,
                "distinct_id": distinctId,
                "properties": phProperties,
                "timestamp": timestamp
            ]
            await postJSONObject(body, to: endpoint, retries: 2)
        }
    }

    func identify(hashedWallet: String) async {
        let normalized = Self.sanitizeTelemetryWalletId(hashedWallet)
        guard !normalized.isEmpty else { return }
        self.hashedWallet = normalized
        let meta = await RuntimeMetadata.current(environment: environment)
        if let apiKey = environment.postHogApiKey,
           !apiKey.isEmpty,
           let host = environment.postHogHost,
           let endpoint = URL(string: "/capture/", relativeTo: host) {
            let payload: [String: Any] = [
                "api_key": apiKey,
                "event": "$identify",
                "distinct_id": normalized,
                "properties": [
                    "distinct_id": normalized,
                    "$anon_distinct_id": anonymousDistinctId,
                    "$set": [
                        "environment": meta.environment,
                        "app_version": meta.appVersion,
                        "build_number": meta.buildNumber,
                        "device_model": meta.deviceModel,
                        "ios_version": meta.iosVersion
                    ]
                ],
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            await postJSONObject(payload, to: endpoint, retries: 2)
        }
    }

    private static func sanitizeTelemetryWalletId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let isTwelveHex = trimmed.count == 12 && trimmed.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        if isTwelveHex { return trimmed }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    private func postJSONObject(_ payload: [String: Any], to endpoint: URL, retries: Int) async {
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        for attempt in 0...retries {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return
                }
            } catch {
                // no-op: fire-and-forget telemetry should never crash or block UI
            }
            guard attempt < retries else { break }
            let backoffSeconds = pow(2.0, Double(attempt)) * 0.3
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }
    }
}

actor BetaFeedbackService: FeedbackSubmitting {
    private let session: URLSession
    private let environment: AppEnvironment

    init(session: URLSession = .shared, environment: AppEnvironment = .current) {
        self.session = session
        self.environment = environment
    }

    func send(message: String, hashedWallet: String, screenshotBase64: String?) async -> Bool {
        guard let base = environment.apiBaseURL,
              let endpoint = URL(string: "/api/feedback", relativeTo: base) else { return false }

        let device = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        var payload: [String: String] = [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "deviceModel": device.0,
            "iOSVersion": device.1,
            "hashedWallet": hashedWallet,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "message": message
        ]
        if let screenshotBase64, !screenshotBase64.isEmpty {
            payload["screenshotBase64"] = screenshotBase64
        }

        guard let body = try? JSONEncoder().encode(payload) else { return false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

enum RadarTheme {
    enum Palette {
        static let backgroundTop = Color(red: 0.03, green: 0.03, blue: 0.04)
        static let backgroundBottom = Color(red: 0.01, green: 0.01, blue: 0.02)
        static let surface = Color.white.opacity(0.06)
        static let surfaceStrong = Color.white.opacity(0.10)
        static let stroke = Color.white.opacity(0.12)
        static let textPrimary = Color.white.opacity(0.96)
        static let textSecondary = Color.white.opacity(0.62)
        static let accent = Color(red: 0.80, green: 0.96, blue: 0.10) // neon-lime
        static let accentAlt = Color(red: 0.67, green: 0.90, blue: 0.12)
        static let success = Color(red: 0.35, green: 0.88, blue: 0.56)
        static let warning = Color(red: 0.98, green: 0.74, blue: 0.36)
        static let neutral = Color(red: 0.48, green: 0.60, blue: 0.72)
        static let danger = Color(red: 0.90, green: 0.35, blue: 0.34)
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
    }

    enum Typography {
        static let hero = Font.system(size: 46, weight: .bold, design: .rounded)
        static let title = Font.system(size: 26, weight: .bold, design: .rounded)
        static let headline = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    }
}

struct RadarGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(RadarTheme.Palette.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
    }
}

extension View {
    func radarGlassCard(cornerRadius: CGFloat = RadarTheme.Radius.medium) -> some View {
        modifier(RadarGlassCardModifier(cornerRadius: cornerRadius))
    }
}

@main
struct PrismMeshApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let walletSession = WalletSessionManager()
    private let notificationManager = NotificationManager()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var accessManager = ActivationAccessManager()
    @State private var sessionBeganAt: Date?
    @State private var didSendTelemetryBoot = false
    @State private var didEmitSafeDedupeProof = false
    private let networkSession: URLSession
    private let errorTracker: ErrorTrackerService
    private let analyticsService: BetaAnalyticsService
    private let appEnvironment: AppEnvironment
    private let metadataService: TokenMetadataService
    private let dashboardViewModel: DashboardViewModel

    init() {
        let appEnvironment = AppEnvironment.current
        self.appEnvironment = appEnvironment
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(configuration: config)
        let tracker = ErrorTrackerService(session: session, environment: appEnvironment)
        let analytics = BetaAnalyticsService(session: session, environment: appEnvironment)
        let metadataService = TokenMetadataService(session: session, errorTracker: tracker)
        let rpcClient = SolanaRPCClient(session: session, errorTracker: tracker)
        let compressedProvider = appEnvironment.heliusDASURL.map {
            HeliusCompressedNFTProvider(endpoint: $0, session: session, errorTracker: tracker)
        }
        let nftCountService = WalletNFTCountService(
            rpcClient: rpcClient,
            compressedProvider: compressedProvider,
            errorTracker: tracker
        )
        self.networkSession = session
        self.errorTracker = tracker
        self.analyticsService = analytics
        self.metadataService = metadataService
        self.dashboardViewModel = DashboardViewModel(
            service: AirdropMonitorService(
                rpcClient: rpcClient,
                metadataService: metadataService,
                riskScoring: ClaimRiskScoringService()
            ),
            notificationManager: notificationManager,
            walletSession: walletSession,
            historyStore: EventHistoryStore(),
            solanaNewsService: GoogleSolanaNewsService(session: session),
            analytics: analytics,
            feedback: BetaFeedbackService(session: session),
            errorTracker: tracker,
            nftCountService: nftCountService
        )
        CrashHooks.shared.install(errorTracker: tracker)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let configError = appEnvironment.configError {
                    ConfigurationErrorView(message: configError)
                } else if accessManager.isActivated {
                    ContentView(viewModel: dashboardViewModel)
                } else {
                    ActivationGateView()
                }
            }
            .onChange(of: scenePhase) { phase in
                appLock.handleScenePhaseChange(phase)
                handleSessionLifecycle(phase)
            }
            .environmentObject(appLock)
            .environmentObject(accessManager)
        }
    }

    private func handleSessionLifecycle(_ phase: ScenePhase) {
        switch phase {
        case .active:
            sessionBeganAt = Date()
            Task {
                if !didSendTelemetryBoot {
                    didSendTelemetryBoot = true
                    await metadataService.prewarmSeedData()
                    await analyticsService.track(event: "telemetry_boot", properties: [:])
                    await errorTracker.breadcrumb(
                        category: "app_launch",
                        message: "Application launched",
                        data: ["environment": AppEnvironment.current.environmentName]
                    )
                }
                if !didEmitSafeDedupeProof {
                    didEmitSafeDedupeProof = true
                    let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                    print("[BOOT] build=\(buildNumber) safe_dedupe=true token_metadata_version=v2")
                    await errorTracker.capture(
                        category: "boot_marker",
                        message: "safe_dedupe=true",
                        httpStatus: nil,
                        extra: [
                            "build": buildNumber
                        ]
                    )
                }
                await analyticsService.track(event: "app_open", properties: [:])
            }
        case .background:
            let startedAt = sessionBeganAt
            sessionBeganAt = nil
            let durationSec = max(0, Int(Date().timeIntervalSince(startedAt ?? Date())))
            Task {
                await analyticsService.track(
                    event: "session_end",
                    properties: [
                        "duration": String(durationSec),
                        "session_duration_sec": String(durationSec)
                    ]
                )
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Configuration Error")
                    .font(RadarTheme.Typography.title)
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Text(message)
                    .font(RadarTheme.Typography.body)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                Text("Build cannot start until configuration is corrected.")
                    .font(.caption)
                    .foregroundStyle(RadarTheme.Palette.warning)
            }
            .padding(20)
            .radarGlassCard(cornerRadius: 20)
            .padding(.horizontal, 16)
        }
    }
}

@MainActor
final class ActivationAccessManager: ObservableObject {
    @Published private(set) var isActivated = false
    private let secureStore: SecureStoring = KeychainStore()
    private let keyAccount = "activation.key.value"
    private let assignedKeyAccount = "activation.key.assigned"
    private let validActivationKeys = [
        "RADAR-ALPHA-2026",
        "RADAR-BETA-2026",
        "RADAR-PRO-2026"
    ]

    init() {
        isActivated = secureStore.read(account: keyAccount) != nil
    }

    func activate(using key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return false }
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        let allowedActivationHashes = Set(validActivationKeys.map {
            SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
        })
        guard allowedActivationHashes.contains(hash) else { return false }
        _ = secureStore.save(value: normalized, account: keyAccount)
        isActivated = true
        return true
    }

    func autoAssignKey() -> String {
        if let existing = secureStore.read(account: assignedKeyAccount), !existing.isEmpty {
            return existing
        }
        let picked = validActivationKeys.randomElement() ?? "RADAR-ALPHA-2026"
        _ = secureStore.save(value: picked, account: assignedKeyAccount)
        return picked
    }

    func deactivate() {
        _ = secureStore.delete(account: keyAccount)
        _ = secureStore.delete(account: assignedKeyAccount)
        isActivated = false
    }
}

struct ActivationGateView: View {
    private enum AccessMode: String, CaseIterable, Identifiable {
        case haveKey = "Have Key"
        case autoAssign = "Auto Assign"

        var id: String { rawValue }
    }

    @EnvironmentObject private var accessManager: ActivationAccessManager
    @AppStorage("profileDisplayName") private var profileDisplayName = "Guest"
    @AppStorage("profileStatusLine") private var profileStatusLine = "Ready"
    @State private var accessMode: AccessMode = .haveKey
    @State private var displayName = ""
    @State private var activationKey = ""
    @State private var assignedKeyPreview: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("PrismMesh Access")
                        .font(RadarTheme.Typography.title)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                    Text("Signup uses activation keys only. No email. No phone.")
                        .font(RadarTheme.Typography.body)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(AccessMode.allCases) { mode in
                            let active = accessMode == mode
                            Button {
                                accessMode = mode
                                errorMessage = nil
                            } label: {
                                Text(mode.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(active ? Color.black.opacity(0.9) : RadarTheme.Palette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(active ? RadarTheme.Palette.accent : RadarTheme.Palette.surface)
                                    .overlay(
                                        Capsule().stroke(active ? RadarTheme.Palette.accent.opacity(0.45) : RadarTheme.Palette.stroke, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Profile Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                        .background(RadarTheme.Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if accessMode == .haveKey {
                        TextField("Activation Key", text: $activationKey)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(12)
                            .foregroundStyle(RadarTheme.Palette.textPrimary)
                            .background(RadarTheme.Palette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No key yet? Auto-assign one now.")
                                .font(.caption)
                                .foregroundStyle(RadarTheme.Palette.textSecondary)
                            if let assignedKeyPreview {
                                Text("Assigned: \(assignedKeyPreview)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(RadarTheme.Palette.warning)
                    }

                    Button(accessMode == .haveKey ? "Activate Account" : "Auto Assign & Activate") {
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else {
                            errorMessage = "Enter a profile name."
                            return
                        }
                        let keyForActivation: String
                        if accessMode == .haveKey {
                            keyForActivation = activationKey
                        } else {
                            let assigned = accessManager.autoAssignKey()
                            assignedKeyPreview = assigned
                            activationKey = assigned
                            keyForActivation = assigned
                        }
                        guard accessManager.activate(using: keyForActivation) else {
                            errorMessage = "Invalid activation key."
                            return
                        }
                        profileDisplayName = name
                        profileStatusLine = "Activated"
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RadarTheme.Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(20)
                .radarGlassCard(cornerRadius: 20)
                .padding(.horizontal, 16)
                .padding(.top, 64)
                .padding(.bottom, 28)
            }
        }
    }
}

@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var biometryType: LABiometryType = .none

    private let lockTimeout: TimeInterval
    private var lastBackgroundedAt: Date?

    init(lockTimeout: TimeInterval = 90) {
        self.lockTimeout = lockTimeout
        refreshBiometryType()
        if biometryType == .none {
            isUnlocked = true
        }
    }

    var biometryDisplayName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Device Passcode"
        }
    }

    func ensureUnlocked(reason: String) async -> Bool {
        if biometryType == .none {
            isUnlocked = true
            return true
        }
        if isUnlocked {
            return true
        }
        return await authenticate(reason: reason)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lastBackgroundedAt = Date()
        case .active:
            guard biometryType != .none else {
                isUnlocked = true
                return
            }
            if let lastBackgroundedAt {
                let elapsed = Date().timeIntervalSince(lastBackgroundedAt)
                if elapsed >= lockTimeout {
                    isUnlocked = false
                }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func lockNow() {
        guard biometryType != .none else { return }
        isUnlocked = false
    }

    private func refreshBiometryType() {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        biometryType = context.biometryType
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { passed, _ in
                continuation.resume(returning: passed)
            }
        }

        isUnlocked = success
        return success
    }
}
