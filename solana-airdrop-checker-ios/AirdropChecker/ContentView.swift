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

                HStack(spacing: 10) {
                    Toggle("Local alerts", isOn: $viewModel.notificationsEnabled)
                        .onChange(of: viewModel.notificationsEnabled) { _ in
                            viewModel.persistNotificationPreference()
                        }

                    Toggle("Auto scan", isOn: $viewModel.autoScanEnabled)
                        .onChange(of: viewModel.autoScanEnabled) { _ in
                            viewModel.persistAutoScanPreference()
                        }
                }

                Picker("Feed", selection: $viewModel.selectedFilter) {
                    ForEach(EventFeedFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Search by token or mint", text: $viewModel.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

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

                HStack {
                    if let checkedAt = viewModel.lastCheckedAt {
                        Text("Last scan: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.selectedFilter != .latest {
                        Text("High risk: \(viewModel.highRiskCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AirdropListView(events: viewModel.displayedEvents)

                if viewModel.selectedFilter == .history || viewModel.selectedFilter == .highRisk {
                    Button("Clear History") {
                        viewModel.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding()
            .navigationTitle("Airdrop Radar")
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onOpenURL { url in
            viewModel.handleWalletURL(url)
        }
    }
}
