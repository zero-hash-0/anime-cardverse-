import SwiftUI
import UIKit

struct AirdropListView: View {
    let events: [AirdropEvent]
    let emptyTitle: String
    let emptySubtitle: String
    let isFavorite: (String) -> Bool
    let onToggleFavorite: (String) -> Void
    let onHideToken: (String) -> Void

    @State private var selectedEvent: AirdropEvent?
    @State private var animateList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(RadarTheme.Palette.accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: RadarTheme.Palette.accent.opacity(0.5), radius: 6)
                    Text("Detected Activity")
                        .font(.headline)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                }
                Spacer()
                Text("\(events.count) items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RadarTheme.Palette.surface)
                    .clipShape(Capsule())
            }

            if events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.title2)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                    Text(emptyTitle)
                        .font(.headline)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                    Text(emptySubtitle)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(RadarTheme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(RadarTheme.Palette.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            selectedEvent = event
                        } label: {
                            AirdropEventRow(
                                event: event,
                                isFavorite: isFavorite(event.mint),
                                onToggleFavorite: { onToggleFavorite(event.mint) }
                            )
                                .opacity(animateList ? 1 : 0)
                                .offset(y: animateList ? 0 : 10)
                                .animation(.spring(response: 0.42, dampingFraction: 0.88).delay(Double(index) * 0.03), value: animateList)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(isFavorite(event.mint) ? "Remove from Watchlist" : "Add to Watchlist") {
                                onToggleFavorite(event.mint)
                            }

                            Button("Hide Token", role: .destructive) {
                                onHideToken(event.mint)
                            }

                            Button("Copy Mint") {
                                UIPasteboard.general.string = event.mint
                            }

                            if let explorerURL = explorerURL(for: event.mint) {
                                Link("Open in Solscan", destination: explorerURL)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            animateList = true
        }
        .onChange(of: events.count) { _ in
            animateList = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                animateList = true
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
                .presentationDetents([.fraction(0.52), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func explorerURL(for mint: String) -> URL? {
        URL(string: "https://solscan.io/token/\(mint)")
    }
}

private struct AirdropEventRow: View {
    let event: AirdropEvent
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TokenLogoView(url: event.metadata.logoURL)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.metadata.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if event.metadata.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(red: 0.08, green: 0.84, blue: 0.58))
                        }
                    }
                    Text(event.metadata.symbol)
                        .font(.caption2)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }

                Spacer()
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isFavorite ? RadarTheme.Palette.accent : RadarTheme.Palette.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(RadarTheme.Palette.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                RiskBadge(level: event.risk.level)
            }

            HStack {
                dataPill(title: "Delta", value: "+\(event.delta.description)")
                dataPill(title: "Date", value: event.detectedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if !event.metadata.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(event.metadata.tags.prefix(4), id: \.self) { tag in
                            Text(tag.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(RadarTheme.Palette.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(RadarTheme.Palette.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Text(event.mint)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(RadarTheme.Palette.textSecondary)
                .lineLimit(1)

            HStack(alignment: .center) {
                Text(event.risk.reasons.first ?? "No risk details")
                    .font(.caption2)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textSecondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(backgroundGradient)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: borderColor.opacity(0.18), radius: 10, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [RadarTheme.Palette.surfaceStrong.opacity(0.92), RadarTheme.Palette.surface.opacity(0.88)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        switch event.risk.level {
        case .low:
            return Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.35)
        case .medium:
            return Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.42)
        case .high:
            return Color(red: 1.0, green: 0.36, blue: 0.36).opacity(0.38)
        }
    }

    private func dataPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EventDetailView: View {
    let event: AirdropEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TokenLogoView(url: event.metadata.logoURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.metadata.name)
                            .font(.title3.weight(.bold))
                        Text(event.metadata.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RiskBadge(level: event.risk.level)
                }

                HStack(spacing: 10) {
                    detailStat(title: "Before", value: event.oldAmount.description)
                    detailStat(title: "After", value: event.newAmount.description)
                    detailStat(title: "Delta", value: "+\(event.delta.description)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Risk Score")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(event.risk.score)")
                            .font(.subheadline.weight(.bold))
                    }
                    ForEach(event.risk.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Token")
                        .font(.subheadline.weight(.semibold))
                    Text(event.mint)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !event.metadata.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(event.metadata.tags.prefix(8), id: \.self) { tag in
                                Text(tag.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.subheadline.weight(.semibold))
                    actionRowButton("Copy Mint", icon: "doc.on.doc") {
                        UIPasteboard.general.string = event.mint
                    }

                    if let url = URL(string: "https://solscan.io/token/\(event.mint)") {
                        actionLink("Open in Solscan", icon: "safari", url: url)
                    }

                    if let walletURL = URL(string: "https://solscan.io/account/\(event.wallet)") {
                        actionLink("Open Wallet in Solscan", icon: "wallet.pass", url: walletURL)
                    }

                    if let websiteURL = event.metadata.websiteURL {
                        actionLink("Open Token Website", icon: "globe", url: websiteURL)
                    }

                    if let coingeckoID = event.metadata.coingeckoID,
                       let geckoURL = URL(string: "https://www.coingecko.com/en/coins/\(coingeckoID)") {
                        actionLink("Open in CoinGecko", icon: "chart.line.uptrend.xyaxis", url: geckoURL)
                    }
                }
            }
            .padding(16)
        }
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func actionRowButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionLink(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct RiskBadge: View {
    let level: ClaimRiskLevel

    var body: some View {
        Text(level.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch level {
        case .low: return Color(red: 0.08, green: 0.84, blue: 0.58)
        case .medium: return Color(red: 0.14, green: 0.65, blue: 1.0)
        case .high: return Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }
}

private struct TokenLogoView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "bitcoinsign.circle")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 38, height: 38)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
