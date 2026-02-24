import SwiftUI
import LocalAuthentication
import CryptoKit

enum RadarTheme {
    enum Palette {
        static let backgroundTop = Color(red: 0.04, green: 0.06, blue: 0.12)
        static let backgroundBottom = Color(red: 0.01, green: 0.02, blue: 0.05)
        static let surface = Color.white.opacity(0.08)
        static let surfaceStrong = Color.white.opacity(0.12)
        static let stroke = Color.white.opacity(0.16)
        static let textPrimary = Color.white.opacity(0.96)
        static let textSecondary = Color.white.opacity(0.66)
        static let accent = Color(red: 0.37, green: 0.52, blue: 1.0)
        static let accentAlt = Color(red: 0.66, green: 0.33, blue: 1.0)
        static let success = Color(red: 0.20, green: 0.86, blue: 0.64)
        static let warning = Color(red: 0.98, green: 0.72, blue: 0.40)
        static let danger = Color(red: 1.0, green: 0.40, blue: 0.45)
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
    }

    enum Typography {
        static let hero = Font.system(size: 40, weight: .black, design: .rounded)
        static let title = Font.system(size: 26, weight: .bold, design: .rounded)
        static let headline = Font.system(size: 18, weight: .bold, design: .rounded)
        static let body = Font.system(size: 15, weight: .regular, design: .rounded)
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
struct AirdropCheckerApp: App {
    private let walletSession = WalletSessionManager()
    private let notificationManager = NotificationManager()
    @StateObject private var appLock = AppLockManager()
    @StateObject private var accessManager = ActivationAccessManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if accessManager.isActivated {
                    ContentView(
                        viewModel: DashboardViewModel(
                            service: AirdropMonitorService(
                                rpcClient: SolanaRPCClient(),
                                metadataService: TokenMetadataService(),
                                riskScoring: ClaimRiskScoringService()
                            ),
                            notificationManager: notificationManager,
                            walletSession: walletSession,
                            historyStore: EventHistoryStore()
                        )
                    )
                } else {
                    ActivationGateView()
                }
            }
            .environmentObject(appLock)
            .environmentObject(accessManager)
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

            VStack(alignment: .leading, spacing: 18) {
                Text("Radar Access")
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
                                .foregroundStyle(active ? RadarTheme.Palette.textPrimary : RadarTheme.Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(active ? RadarTheme.Palette.accent.opacity(0.22) : RadarTheme.Palette.surface)
                                .overlay(
                                    Capsule().stroke(active ? RadarTheme.Palette.accent.opacity(0.55) : RadarTheme.Palette.stroke, lineWidth: 1)
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
                        .foregroundStyle(.red.opacity(0.9))
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
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [RadarTheme.Palette.accent, RadarTheme.Palette.accentAlt],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(20)
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
