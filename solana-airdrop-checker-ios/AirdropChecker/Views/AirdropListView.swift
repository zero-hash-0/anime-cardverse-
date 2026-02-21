import SwiftUI
import UIKit

struct AirdropListView: View {
    let events: [AirdropEvent]

    @State private var selectedEvent: AirdropEvent?

    var body: some View {
        if events.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Airdrop Events")
                    .font(.headline)
                Text("Run another scan after wallet activity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(events) { event in
                Button {
                    selectedEvent = event
                } label: {
                    AirdropEventRow(event: event)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy Mint") {
                        UIPasteboard.general.string = event.mint
                    }

                    if let explorerURL = explorerURL(for: event.mint) {
                        Link("Open in Solscan", destination: explorerURL)
                    }
                }
            }
            .listStyle(.plain)
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event)
            }
        }
    }

    private func explorerURL(for mint: String) -> URL? {
        URL(string: "https://solscan.io/token/\(mint)")
    }
}

private struct AirdropEventRow: View {
    let event: AirdropEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TokenLogoView(url: event.metadata.logoURL)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.metadata.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(event.metadata.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                RiskBadge(level: event.risk.level)
            }

            Text(event.mint)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("+\(event.delta.description) tokens")
                .font(.title3.weight(.semibold))

            Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct EventDetailView: View {
    let event: AirdropEvent

    var body: some View {
        NavigationStack {
            List {
                Section("Token") {
                    Text(event.metadata.name)
                    Text(event.metadata.symbol)
                    Text(event.mint)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section("Balance Change") {
                    Text("Before: \(event.oldAmount.description)")
                    Text("After: \(event.newAmount.description)")
                    Text("Delta: +\(event.delta.description)")
                }

                Section("Risk") {
                    HStack {
                        Text("Level")
                        Spacer()
                        RiskBadge(level: event.risk.level)
                    }
                    Text("Score: \(event.risk.score)")
                    ForEach(event.risk.reasons, id: \.self) { reason in
                        Text(reason)
                    }
                }

                Section("Actions") {
                    Button("Copy Mint") {
                        UIPasteboard.general.string = event.mint
                    }

                    if let url = URL(string: "https://solscan.io/token/\(event.mint)") {
                        Link("Open in Solscan", destination: url)
                    }
                }
            }
            .navigationTitle("Airdrop Detail")
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
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
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
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
