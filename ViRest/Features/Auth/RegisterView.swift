import SwiftUI

struct RegisterView: View {
    @ObservedObject private var viewModel: AuthViewModel
    private let onBack: () -> Void
    private let onBackToLogin: () -> Void

    init(viewModel: AuthViewModel, onBack: @escaping () -> Void, onBackToLogin: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onBackToLogin = onBackToLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                ZStack {
                    Text("Virest")
                        .font(.headline.bold())
                        .foregroundStyle(Color.slateGray)

                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 24).bold())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("Your Recommendation Sport is Ready")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.vibrantGreen)

                Text("Sign up below to save your profile and get your recommendation")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 32) {
                authButton("Sign up with Google", image: "googleLogo") {
                    viewModel.signInWithGoogle()
                }

                HStack(spacing: 16) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 2)
                    Text("OR")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.9))
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 2)
                }

                Button {
                    self.onBackToLogin()
                } label: {
                    Text("Login with existing account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 20)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 20)
            }

            if viewModel.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Authenticating...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.richBlack)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func authButton(
        _ title: String,
        icon: String? = nil,
        image: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.vibrantGreen)

                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                if let image {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .disabled(viewModel.isLoading)
    }
}

@MainActor
private struct RegisterPreviewHost: View {
    private let viewModel = PreviewSupport.makeAuthViewModel()

    var body: some View {
        NavigationStack {
            RegisterView(viewModel: viewModel, onBack: {}, onBackToLogin: {})
        }
    }
}

#Preview("Register") {
    RegisterPreviewHost()
}
