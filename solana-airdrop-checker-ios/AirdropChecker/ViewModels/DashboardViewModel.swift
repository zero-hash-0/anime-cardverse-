import Foundation

enum WalletConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(String)
    case error(String)
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var walletAddress = ""
    @Published var latestEvents: [AirdropEvent] = []
    @Published var historyEvents: [AirdropEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCheckedAt: Date?
    @Published var notificationsEnabled = true
    @Published var notifyHighRiskOnly = false
    @Published var autoScanEnabled = false
    @Published var selectedFilter: EventFeedFilter = .latest
    @Published var searchQuery = ""
    @Published private(set) var solanaHeadlines: [SolanaHeadline] = []
    @Published private(set) var activeHeadlineIndex = 0
    @Published private(set) var popularTopics: [String] = []
    @Published var newsStatusMessage: String?
    @Published private(set) var favoriteMints: Set<String> = []
    @Published private(set) var hiddenMints: Set<String> = []
    @Published private(set) var connectionState: WalletConnectionState = .disconnected
    @Published private(set) var statusMessage: String?

    private let service: AirdropMonitorService
    private let notificationManager: NotificationManager
    private let walletSession: WalletSessionManager
    private let historyStore: EventHistoryStoring
    private let solanaNewsService: SolanaNewsProviding
    private let defaults: UserDefaults

    private let notificationsEnabledKey = "notifications_enabled"
    private let notifyHighRiskOnlyKey = "notify_high_risk_only"
    private let autoScanEnabledKey = "auto_scan_enabled"
    private let favoriteMintsKey = "favorite_mints"
    private let hiddenMintsKey = "hidden_mints"
    private var autoScanTask: Task<Void, Never>?
    private var newsRefreshTask: Task<Void, Never>?
    private var newsRotationTask: Task<Void, Never>?

    init(
        service: AirdropMonitorService,
        notificationManager: NotificationManager,
        walletSession: WalletSessionManager,
        historyStore: EventHistoryStoring,
        solanaNewsService: SolanaNewsProviding = GoogleSolanaNewsService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.notificationManager = notificationManager
        self.walletSession = walletSession
        self.historyStore = historyStore
        self.solanaNewsService = solanaNewsService
        self.defaults = defaults

        self.notificationsEnabled = defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true
        self.notifyHighRiskOnly = defaults.object(forKey: notifyHighRiskOnlyKey) as? Bool ?? false
        self.autoScanEnabled = defaults.object(forKey: autoScanEnabledKey) as? Bool ?? false
        let favoriteMints = defaults.array(forKey: favoriteMintsKey) as? [String] ?? []
        self.favoriteMints = Set(favoriteMints)
        let hiddenMints = defaults.array(forKey: hiddenMintsKey) as? [String] ?? []
        self.hiddenMints = Set(hiddenMints)
        self.historyEvents = historyStore.load()

        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
        }
    }

    deinit {
        autoScanTask?.cancel()
        newsRefreshTask?.cancel()
        newsRotationTask?.cancel()
    }

    func onAppear() async {
        await notificationManager.refreshAuthorizationStatus()

        if let connected = walletSession.connectedWallet, walletAddress.isEmpty {
            walletAddress = connected
            connectionState = .connected(connected)
        }

        historyEvents = historyStore.load()
        if latestEvents.isEmpty && historyEvents.isEmpty {
            loadDemoData()
        }
        await refreshSolanaNews()
        startNewsTickerIfNeeded()
        startNewsRefreshLoopIfNeeded()
        startAutoScanIfNeeded()
    }

    func onDisappear() {
        autoScanTask?.cancel()
        autoScanTask = nil
        newsRefreshTask?.cancel()
        newsRefreshTask = nil
        newsRotationTask?.cancel()
        newsRotationTask = nil
    }

    func persistNotificationPreference() {
        defaults.set(notificationsEnabled, forKey: notificationsEnabledKey)
    }

    func persistHighRiskAlertPreference() {
        defaults.set(notifyHighRiskOnly, forKey: notifyHighRiskOnlyKey)
    }

    func persistAutoScanPreference() {
        defaults.set(autoScanEnabled, forKey: autoScanEnabledKey)
        startAutoScanIfNeeded()
    }

    func connectWallet() {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            connectionState = .error("Enter a valid Solana wallet address.")
            statusMessage = "Invalid wallet format."
            return
        }

        connectionState = .connecting
        walletSession.connect(manualAddress: trimmed)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
            statusMessage = "Wallet connected."
        } else {
            connectionState = .error("Unable to set wallet.")
            statusMessage = "Connection failed."
        }
    }

    func disconnectWallet() {
        walletSession.disconnect()
        walletAddress = ""
        latestEvents = []
        historyEvents = []
        historyStore.clear()
        selectedFilter = .latest
        lastCheckedAt = nil
        errorMessage = nil
        connectionState = .disconnected
        statusMessage = "Wallet disconnected."
    }

    func clearHistory() {
        historyStore.clear()
        historyEvents = []
    }

    func handleWalletURL(_ url: URL) {
        walletSession.handleDeeplink(url)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
            statusMessage = "Wallet loaded from link."
        }
    }

    func refresh() async {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            errorMessage = "Enter a valid Solana wallet address."
            connectionState = .error("Enter a valid Solana wallet address.")
            statusMessage = "Wallet required before scan."
            return
        }

        walletAddress = trimmed
        connectWallet()
        guard case .connected = connectionState else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = "Scanning wallet..."

        do {
            let newEvents = try await service.checkForAirdrops(wallet: trimmed)
            latestEvents = newEvents
            historyStore.save(newEvents: newEvents)
            historyEvents = historyStore.load()
            lastCheckedAt = Date()
            connectionState = .connected(trimmed)
            statusMessage = newEvents.isEmpty ? "No airdrops detected." : "Scan complete: \(newEvents.count) events."

            if notificationsEnabled {
                let eventsForAlert = notifyHighRiskOnly
                    ? newEvents.filter { $0.risk.level == .high }
                    : newEvents
                await notificationManager.notifyNewAirdrops(eventsForAlert)
            }

        } catch {
            errorMessage = error.localizedDescription
            connectionState = .error(error.localizedDescription)
            statusMessage = "Scan failed."
        }

        isLoading = false
    }

    var displayedEvents: [AirdropEvent] {
        let source: [AirdropEvent]
        switch selectedFilter {
        case .latest:
            source = latestEvents
        case .history:
            source = historyEvents
        case .highRisk:
            source = historyEvents.filter { $0.risk.level == .high }
        case .watchlist:
            source = historyEvents.filter { favoriteMints.contains($0.mint) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleSource = source.filter { !hiddenMints.contains($0.mint) }
            .sorted(by: eventSort)
        guard !query.isEmpty else { return visibleSource }

        return visibleSource.filter {
            $0.metadata.name.lowercased().contains(query) ||
            $0.metadata.symbol.lowercased().contains(query) ||
            $0.mint.lowercased().contains(query)
        }
    }

    var highRiskCount: Int {
        historyEvents.filter { $0.risk.level == .high }.count
    }

    var totalDetectedCount: Int {
        historyEvents.count
    }

    var watchlistCount: Int {
        historyEvents.filter { favoriteMints.contains($0.mint) && !hiddenMints.contains($0.mint) }.count
    }

    var mediumRiskCount: Int {
        historyEvents.filter { $0.risk.level == .medium }.count
    }

    var lowRiskCount: Int {
        historyEvents.filter { $0.risk.level == .low }.count
    }

    var latestDetectedAmount: Decimal {
        latestEvents.reduce(0) { $0 + $1.delta }
    }

    var totalDetectedAmount: Decimal {
        historyEvents.reduce(0) { $0 + $1.delta }
    }

    var currentHeadline: SolanaHeadline? {
        guard !solanaHeadlines.isEmpty else { return nil }
        let index = min(activeHeadlineIndex, solanaHeadlines.count - 1)
        return solanaHeadlines[index]
    }

    var hasValidWalletAddress: Bool {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return AddressValidator.isLikelySolanaAddress(trimmed)
    }

    var hiddenTokenCount: Int {
        hiddenMints.count
    }

    var securityScore: Int {
        var score = 34
        if hasValidWalletAddress { score += 20 }
        if notificationsEnabled { score += 14 }
        if notifyHighRiskOnly { score += 10 }
        if autoScanEnabled { score += 10 }
        if hiddenTokenCount > 0 { score += 8 }
        return min(score, 100)
    }

    func loadDemoData() {
        let now = Date()
        let demo: [AirdropEvent] = [
            AirdropEvent(
                wallet: walletAddress.isEmpty ? "DemoWallet1111111111111111111111111111111111" : walletAddress,
                mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
                oldAmount: 0,
                newAmount: 24.5,
                metadata: TokenMetadata(
                    mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
                    symbol: "JUP",
                    name: "Jupiter",
                    logoURL: nil
                ),
                risk: ClaimRiskAssessment(level: .low, score: 10, reasons: ["Known token metadata and healthy transfer size."]),
                detectedAt: now
            ),
            AirdropEvent(
                wallet: walletAddress.isEmpty ? "DemoWallet1111111111111111111111111111111111" : walletAddress,
                mint: "Fre3ClaimB0nus111111111111111111111111111111",
                oldAmount: 0,
                newAmount: 0.0001,
                metadata: TokenMetadata(
                    mint: "Fre3ClaimB0nus111111111111111111111111111111",
                    symbol: "FREECLAIM",
                    name: "Free Claim Bonus",
                    logoURL: nil
                ),
                risk: ClaimRiskAssessment(
                    level: .high,
                    score: 88,
                    reasons: [
                        "Token name/symbol contains common scam keywords.",
                        "Tiny balance increase; dust airdrops can be phishing bait."
                    ]
                ),
                detectedAt: now.addingTimeInterval(-320)
            )
        ]

        latestEvents = demo
        historyStore.save(newEvents: demo)
        historyEvents = historyStore.load()
        selectedFilter = .latest
        lastCheckedAt = now
        errorMessage = nil
        if let connected = walletSession.connectedWallet {
            connectionState = .connected(connected)
        } else if AddressValidator.isLikelySolanaAddress(walletAddress) {
            connectionState = .connected(walletAddress)
        }
        statusMessage = "Demo results loaded."
    }

    func refreshSolanaNews() async {
        do {
            let headlines = try await solanaNewsService.fetchLatest()
            solanaHeadlines = headlines
            popularTopics = extractPopularTopics(from: headlines)
            if activeHeadlineIndex >= headlines.count {
                activeHeadlineIndex = 0
            }
            newsStatusMessage = headlines.isEmpty ? "No live Solana headlines right now." : nil
            startNewsTickerIfNeeded()
        } catch {
            newsStatusMessage = "Could not load live Solana headlines."
        }
    }

    func isFavorite(mint: String) -> Bool {
        favoriteMints.contains(mint)
    }

    func toggleFavorite(mint: String) {
        if favoriteMints.contains(mint) {
            favoriteMints.remove(mint)
        } else {
            favoriteMints.insert(mint)
        }
        persistFavorites()
    }

    func hideMint(_ mint: String) {
        hiddenMints.insert(mint)
        persistHiddenMints()
    }

    func unhideAllMints() {
        hiddenMints = Set<String>()
        persistHiddenMints()
    }

    private func persistFavorites() {
        defaults.set(Array(favoriteMints).sorted(), forKey: favoriteMintsKey)
    }

    private func persistHiddenMints() {
        defaults.set(Array(hiddenMints).sorted(), forKey: hiddenMintsKey)
    }

    private func eventSort(lhs: AirdropEvent, rhs: AirdropEvent) -> Bool {
        let leftFavorite = favoriteMints.contains(lhs.mint)
        let rightFavorite = favoriteMints.contains(rhs.mint)
        if leftFavorite != rightFavorite {
            return leftFavorite && !rightFavorite
        }
        return lhs.detectedAt > rhs.detectedAt
    }

    private func startAutoScanIfNeeded() {
        autoScanTask?.cancel()
        autoScanTask = nil

        guard autoScanEnabled else { return }

        autoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 600_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                if !self.walletAddress.isEmpty {
                    await self.refresh()
                }
            }
        }
    }

    private func startNewsRefreshLoopIfNeeded() {
        newsRefreshTask?.cancel()
        newsRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 900_000_000_000)
                } catch {
                    break
                }
                guard let self else { break }
                await self.refreshSolanaNews()
            }
        }
    }

    private func startNewsTickerIfNeeded() {
        newsRotationTask?.cancel()
        newsRotationTask = nil

        guard solanaHeadlines.count > 1 else { return }

        newsRotationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                guard !self.solanaHeadlines.isEmpty else { continue }
                self.activeHeadlineIndex = (self.activeHeadlineIndex + 1) % self.solanaHeadlines.count
            }
        }
    }

    private func extractPopularTopics(from headlines: [SolanaHeadline]) -> [String] {
        let blocked = Set([
            "solana", "crypto", "cryptocurrency", "price", "token", "tokens", "coin", "coins",
            "market", "markets", "today", "news", "latest", "surges", "rally", "update",
            "after", "with", "from", "into", "amid", "this", "that", "over", "under",
            "hits", "will", "could", "about", "your", "you", "are", "the", "and", "for"
        ])

        var counts: [String: Int] = [:]
        for headline in headlines {
            let words = headline.title.lowercased()
                .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
            for word in words where word.count >= 4 && !blocked.contains(word) {
                counts[word, default: 0] += 1
            }
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(7)
            .map { $0.key.capitalized }
    }
}

struct SolanaHeadline: Identifiable, Equatable {
    let title: String
    let source: String
    let publishedAt: Date?
    let url: URL

    var id: String { url.absoluteString }
}

protocol SolanaNewsProviding {
    func fetchLatest() async throws -> [SolanaHeadline]
}

enum SolanaNewsError: LocalizedError {
    case invalidResponse
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid news response."
        case .parseFailed:
            return "Could not parse news feed."
        }
    }
}

final class GoogleSolanaNewsService: SolanaNewsProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatest() async throws -> [SolanaHeadline] {
        guard let url = URL(string: "https://news.google.com/rss/search?q=solana&hl=en-US&gl=US&ceid=US:en") else {
            throw SolanaNewsError.invalidResponse
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaNewsError.invalidResponse
        }

        let parser = SolanaRSSParser()
        let items = parser.parse(data: data)
        let filtered = items.filter { item in
            let haystack = "\(item.title) \(item.source)".lowercased()
            return haystack.contains("solana")
        }
        return Array(filtered.prefix(25))
    }
}

private final class SolanaRSSParser: NSObject, XMLParserDelegate {
    private struct Entry {
        var title = ""
        var link = ""
        var source = ""
        var pubDate = ""
    }

    private var entries: [Entry] = []
    private var currentEntry: Entry?
    private var currentElement = ""
    private var currentText = ""

    func parse(data: Data) -> [SolanaHeadline] {
        entries = []
        currentEntry = nil
        currentElement = ""
        currentText = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"

        return entries.compactMap { entry in
            guard let url = URL(string: entry.link), !entry.title.isEmpty else {
                return nil
            }
            let inferredSource = inferSource(title: entry.title, explicit: entry.source)
            return SolanaHeadline(
                title: sanitizeTitle(entry.title),
                source: inferredSource,
                publishedAt: dateFormatter.date(from: entry.pubDate),
                url: url
            )
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "item" {
            currentEntry = Entry()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var currentEntry else { return }

        switch elementName {
        case "title":
            currentEntry.title = text
        case "link":
            currentEntry.link = text
        case "source":
            currentEntry.source = text
        case "pubDate":
            currentEntry.pubDate = text
        case "item":
            entries.append(currentEntry)
            self.currentEntry = nil
            return
        default:
            break
        }
        self.currentEntry = currentEntry
    }

    private func inferSource(title: String, explicit: String) -> String {
        if !explicit.isEmpty {
            return explicit
        }
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1, let last = parts.last, !last.isEmpty {
            return last
        }
        return "Source"
    }

    private func sanitizeTitle(_ title: String) -> String {
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1 {
            return parts.dropLast().joined(separator: " - ")
        }
        return title
    }
}
