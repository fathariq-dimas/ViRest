import SwiftUI

struct LoginView: View {
    @ObservedObject private var viewModel: AuthViewModel
    private let onStart: () -> Void

    init(viewModel: AuthViewModel, onStart: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onStart = onStart
    }

    var body: some View {
        VStack(alignment: .center, spacing: 28) {
            Spacer()
            
            Image("virest")
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
            
            Spacer()
            
            VStack(spacing: 32) {
                Button {
                    viewModel.signInWithGoogle()
                } label: {
                    HStack(spacing: 10) {
                        Text("Login with Google")
                            .font(.headline)
                            .foregroundStyle(Color.vibrantGreen)

                        Image("googleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isLoading)
                
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
                
                Button(action: onStart) {
                    Text("Start")
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }.padding(.horizontal, 20)           

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
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.richBlack)
        .toolbar(.hidden, for: .navigationBar)
    }
}

@MainActor
private struct LoginPreviewHost: View {
    private let viewModel = PreviewSupport.makeAuthViewModel()

    var body: some View {
        NavigationStack {
            LoginView(viewModel: viewModel, onStart: { })
        }
    }
}

#Preview("Login") {
    LoginPreviewHost()
}
