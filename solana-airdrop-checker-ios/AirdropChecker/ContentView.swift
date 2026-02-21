import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                WalletInputView(walletAddress: $viewModel.walletAddress)

                HStack(spacing: 10) {
                    Button("Connect") {
                        viewModel.connectWallet()
                    }
                    .buttonStyle(.bordered)

                    Button("Disconnect") {
                        viewModel.disconnectWallet()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Enable local alerts", isOn: $viewModel.notificationsEnabled)
                    .onChange(of: viewModel.notificationsEnabled) { _ in
                        viewModel.persistNotificationPreference()
                    }

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(viewModel.isLoading ? "Scanning Wallet..." : "Scan for Airdrops")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)

                if let checkedAt = viewModel.lastCheckedAt {
                    Text("Last scan: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AirdropListView(events: viewModel.events)
            }
            .padding()
            .navigationTitle("Airdrop Radar")
        }
        .task {
            await viewModel.onAppear()
        }
        .onOpenURL { url in
            viewModel.handleWalletURL(url)
        }
    }
}
