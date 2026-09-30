import AtlasCore
import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthSessionStore
    let environment: BackendConfiguration
    let showAppearance: () -> Void
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if geometry.size.width >= 860 {
                        HStack(spacing: 0) {
                            hero
                                .frame(maxWidth: .infinity)
                            signInPanel
                                .frame(maxWidth: 530)
                        }
                        .frame(minHeight: geometry.size.height)
                    } else {
                        VStack(spacing: 0) {
                            hero
                                .frame(minHeight: 310)
                            signInPanel
                        }
                        .frame(minHeight: geometry.size.height)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.canvas)
    }

    private var hero: some View {
        ZStack {
            theme.heroGradient
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 420, height: 420)
                .offset(x: 180, y: -230)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .frame(width: 310, height: 310)
                .offset(x: -210, y: 270)

            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 13) {
                    AtlasLogo(size: 48, inverted: true)
                    Text("ATLAS")
                        .font(.headline.weight(.black))
                        .tracking(2.4)
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Make your ideas\neasy to return to.")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.78)
                    Text("Notes, plans, research, and the next action—organized around how you actually think.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineSpacing(4)
                        .frame(maxWidth: 500, alignment: .leading)
                }

                HStack(spacing: 22) {
                    feature("lock.shield", "Private by default")
                    feature("bolt", "Fast to navigate")
                    feature("wifi.slash", "Works offline")
                }

                Spacer(minLength: 12)
            }
            .padding(50)
            .frame(maxWidth: 680, maxHeight: 760, alignment: .leading)
        }
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var signInPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            VStack(alignment: .leading, spacing: 26) {
                if !environment.isProduction {
                    Text(environment.environmentName.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(theme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.tintSurface, in: Capsule())
                        .accessibilityLabel("Environment: \(environment.environmentName)")
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Welcome to Atlas")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text("Enter your workspace and pick up exactly where you left off.")
                        .font(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                }

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        auth.handleAppleAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(auth.isSigningIn || environment.baseURL == nil)
                    .opacity(environment.baseURL == nil ? 0.48 : 1)
                    .accessibilityLabel("Continue with Apple")

                    HStack(spacing: 12) {
                        Rectangle().fill(theme.divider).frame(height: 1)
                        Text("OR")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.textSecondary)
                        Rectangle().fill(theme.divider).frame(height: 1)
                    }

                    Button {
                        auth.continueOffline()
                    } label: {
                        Label("Continue on this device", systemImage: "laptopcomputer.and.iphone")
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(auth.isSigningIn)
                }

                if auth.isSigningIn {
                    ProgressView("Securely verifying…")
                        .frame(maxWidth: .infinity)
                }

                if let error = auth.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(theme.danger)
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(environment.baseURL == nil ? theme.warmAccent : theme.primary)
                            .frame(width: 8, height: 8)
                        Text(environment.baseURL == nil ? "Offline workspace ready" : "Secure backend connected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    if environment.baseURL == nil {
                        Text("Apple sign-in activates when the HTTPS backend is connected. Your offline notes remain on this device.")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineSpacing(2)
                    }
                }
            }
            .frame(maxWidth: 390)
            .atlasCard(padding: 28, radius: 26)
            .padding(36)
            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity)
        .background(theme.canvas)
        .overlay(alignment: .topTrailing) {
            Button(action: showAppearance) {
                Label("Personalize", systemImage: "paintpalette.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(theme.surface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(theme.warmAccent)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}
