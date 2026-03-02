import Foundation
import UIKit

enum BuildChannel {
    static var isTestFlight: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
}

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
        func plistString(_ key: String) -> String? {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let baseRaw = plistString("APIBaseURLProd") ?? plistString("APIBaseURLStaging")
        let baseURL = baseRaw.flatMap(URL.init(string:))
        let heliusAPIKey = plistString("HELIUS_API_KEY") ?? plistString("HeliusAPIKey")
        let heliusDASURL = (plistString("HELIUS_DAS_URL") ?? plistString("HeliusDASURL")).flatMap(URL.init(string:))

        #if DEBUG
        let environmentName = "dev"
        #else
        let environmentName = "prod"
        #endif

        return AppEnvironment(
            apiBaseURL: baseURL,
            sentryDSN: plistString("SentryDSNProd"),
            postHogApiKey: plistString("PostHogApiKeyProd"),
            postHogHost: plistString("PostHogHostProd").flatMap(URL.init(string:)),
            heliusAPIKey: heliusAPIKey,
            heliusDASURL: heliusDASURL,
            environmentName: environmentName,
            configError: baseURL == nil ? "Missing API base URL configuration." : nil
        )
    }
}

protocol AnalyticsTracking {
    func identify(hashedWallet: String) async
    func track(event: String, properties: [String: String]) async
}

struct BetaAnalyticsService: AnalyticsTracking {
    func identify(hashedWallet: String) async {}
    func track(event: String, properties: [String: String]) async {}
}

protocol ErrorTracking {
    func setUser(hashedWallet: String?) async
    func capture(_ error: Error, context: [String: String]) async
    func capture(category: String, message: String, httpStatus: Int?, extra: [String: String]) async
    func breadcrumb(category: String, message: String, data: [String: String]) async
}

actor ErrorTrackerService: ErrorTracking {
    static let shared = ErrorTrackerService()
    private var currentUser: String?
    private init() {}

    func setUser(hashedWallet: String?) async {
        currentUser = hashedWallet
    }

    func capture(_ error: Error, context: [String: String]) async {}

    func capture(category: String, message: String, httpStatus: Int?, extra: [String: String]) async {}

    func breadcrumb(category: String, message: String, data: [String: String]) async {}
}

protocol FeedbackSubmitting {
    func send(message: String, hashedWallet: String, screenshotBase64: String?) async -> Bool
}

struct BetaFeedbackService: FeedbackSubmitting {
    func send(message: String, hashedWallet: String, screenshotBase64: String?) async -> Bool { true }
}

enum Haptic {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
