import SwiftUI

struct WalletInputView: View {
    @Binding var walletAddress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Address")
                .font(.headline.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)

            TextField("Enter Solana wallet", text: $walletAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .background(RadarTheme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    RadarTheme.Palette.stroke,
                                    RadarTheme.Palette.accent.opacity(0.42),
                                    RadarTheme.Palette.stroke
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Tip: Use a burner wallet for claim links and unknown token interactions.")
                .font(.caption)
                .foregroundStyle(RadarTheme.Palette.textSecondary)
        }
    }
}
