import SwiftUI
import UIKit

struct WalletInputView: View {
    @Binding var walletAddress: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Address")
                .font(.headline.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)

            HStack(spacing: 8) {
                TextField("Enter Solana wallet", text: $walletAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .focused($isFocused)
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

                Button("Paste") {
                    guard let value = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !value.isEmpty else { return }
                    walletAddress = value
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RadarTheme.Palette.surfaceStrong)
                .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                .clipShape(Capsule())
            }

            Text("Tip: Use a burner wallet for claim links and unknown token interactions.")
                .font(.caption)
                .foregroundStyle(RadarTheme.Palette.textSecondary)
        }
    }
}
