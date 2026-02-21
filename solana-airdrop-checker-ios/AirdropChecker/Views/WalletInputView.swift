import SwiftUI

struct WalletInputView: View {
    @Binding var walletAddress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Address")
                .font(.headline)

            TextField("Enter Solana wallet", text: $walletAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Tip: Use a burner wallet for claim links and unknown token interactions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
