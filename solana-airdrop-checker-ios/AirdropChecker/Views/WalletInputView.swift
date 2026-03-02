import SwiftUI
import UIKit

struct WalletInputView: View {
    @Binding var walletAddress: String
    @FocusState.Binding var isFocused: Bool
    var walletConnectStatus: String? = nil
    var walletErrorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Address")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ThemeTokens.Text.primary)

            HStack(spacing: 8) {
                TextField("Enter Solana wallet", text: $walletAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .focused($isFocused)
                    .padding(12)
                    .foregroundStyle(ThemeTokens.Text.primary)
                    .background(ThemeTokens.Card.top)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ThemeTokens.Card.border,
                                        ThemeTokens.Accent.intelligenceBlue.opacity(0.38),
                                        ThemeTokens.Card.border
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
                .foregroundStyle(ThemeTokens.Text.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ThemeTokens.Card.innerSurface)
                .overlay(Capsule().stroke(ThemeTokens.Card.border, lineWidth: 1))
                .clipShape(Capsule())
            }

            Text("Tip: Use a burner wallet for claim links and unknown token interactions.")
                .font(.caption)
                .foregroundStyle(ThemeTokens.Text.secondary)

            if let walletErrorMessage, !walletErrorMessage.isEmpty {
                Text(walletErrorMessage)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ThemeTokens.Accent.critical)
            } else if let walletConnectStatus, !walletConnectStatus.isEmpty {
                Text(walletConnectStatus)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }
}
