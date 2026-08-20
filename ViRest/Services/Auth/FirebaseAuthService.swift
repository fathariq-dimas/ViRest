import Foundation
import Combine
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class FirebaseAuthService: AuthProviding, ObservableObject {
    private enum Keys {
        static let savedAuthUser = "virest.saved_auth_user"
        static let hasActiveSession = "virest.has_active_auth_session"
    }

    @Published private(set) var authState: AppAuthState = .signedOut

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    // Keep a strong reference to the Apple Sign-In delegate while a request is in-flight.
    private var appleSignInDelegate: AppleSignInDelegate?
    private var currentNonce: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func restoreSession() async {
#if canImport(FirebaseAuth)
        guard let firebaseUser = Auth.auth().currentUser else {
            authState = .signedOut
            return
        }

        authState = .signedIn(makeAuthUser(from: firebaseUser))
        return
#else
        guard userDefaults.bool(forKey: Keys.hasActiveSession) else {
            userDefaults.removeObject(forKey: Keys.savedAuthUser)
            authState = .signedOut
            return
        }

        guard let data = userDefaults.data(forKey: Keys.savedAuthUser),
              let user = try? decoder.decode(AuthUser.self, from: data) else {
            userDefaults.removeObject(forKey: Keys.hasActiveSession)
            userDefaults.removeObject(forKey: Keys.savedAuthUser)
            authState = .signedOut
            return
        }

        authState = .signedIn(user)
#endif
    }

    func signInWithApple() async throws -> AuthUser {
        #if canImport(FirebaseAuth)
        return try await signInWithAppleUsingFirebase()
        #else
        // Placeholder implementation. Replace with Firebase + Sign in with Apple SDK flow.
        let user = AuthUser(
            id: UUID().uuidString,
            email: "apple.user@virest.app",
            displayName: "Apple User",
            provider: .apple
        )

        try persistFallbackUser(user)
        authState = .signedIn(user)
        return user
        #endif
    }

    func signInWithGoogle() async throws -> AuthUser {
        #if canImport(FirebaseAuth)
        return try await signInWithGoogleUsingFirebase()
        #else
        // Placeholder implementation. Replace with Firebase + Google Sign-In SDK flow.
        let user = AuthUser(
            id: UUID().uuidString,
            email: "google.user@virest.app",
            displayName: "Google User",
            provider: .google
        )

        try persistFallbackUser(user)
        authState = .signedIn(user)
        return user
        #endif
    }
    func signOut() throws {
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
        } catch {
            throw AppError.auth("Failed to sign out: \(error.localizedDescription)")
        }
        #endif
        userDefaults.removeObject(forKey: Keys.savedAuthUser)
        userDefaults.removeObject(forKey: Keys.hasActiveSession)
        authState = .signedOut
    }

    #if canImport(FirebaseAuth)
    private func signInWithAppleUsingFirebase() async throws -> AuthUser {
        let nonce = randomNonceString()
        currentNonce = nonce
        let hashed = sha256(nonce)

        // Request Apple ID credential with nonce
        let credential = try await requestAppleIDCredential(nonce: hashed)
        guard let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw AppError.auth("Unable to fetch identity token from Apple.")
        }

        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: tokenString, rawNonce: nonce, fullName: credential.fullName)

        let authResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().signIn(with: firebaseCredential) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.auth("Unknown error during Apple sign-in."))
                }
            }
        }

        let fUser = authResult.user
        let user = AuthUser(
            id: fUser.uid,
            email: fUser.email,
            displayName: fUser.displayName ?? credential.fullName?.formatted() ?? "Apple User",
            provider: .apple
        )
        authState = .signedIn(user)
        return user
    }

    private func signInWithGoogleUsingFirebase() async throws -> AuthUser {
        #if canImport(GoogleSignIn)
        guard let presentingVC = topViewController() else {
            throw AppError.auth("Unable to find a presenting view controller for Google Sign-In.")
        }

        let gidResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
        guard let idToken = gidResult.user.idToken?.tokenString else {
            throw AppError.auth("Missing Google ID token.")
        }
        let accessToken = gidResult.user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

        let authResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().signIn(with: credential) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.auth("Unknown error during Google sign-in."))
                }
            }
        }

        let fUser = authResult.user
        let user = AuthUser(
            id: fUser.uid,
            email: fUser.email,
            displayName: fUser.displayName ?? gidResult.user.profile?.name ?? "Google User",
            provider: .google
        )
        authState = .signedIn(user)
        return user
        #else
        throw AppError.auth("Google Sign-In SDK not found. Add GoogleSignIn via Swift Package Manager.")
        #endif
    }
    #endif

    // MARK: - Helpers

    private func requestAppleIDCredential(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            let delegate = AppleSignInDelegate { [weak self] result in
                self?.appleSignInDelegate = nil
                switch result {
                case .success(let credential):
                    continuation.resume(returning: credential)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            self.appleSignInDelegate = delegate // retain during request

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.performRequests()
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

#if canImport(FirebaseAuth)
    private func makeAuthUser(from user: FirebaseAuth.User) -> AuthUser {
        let provider: AuthProvider = user.providerData.first?.providerID == "apple.com" ? .apple : .google
        return AuthUser(
            id: user.uid,
            email: user.email,
            displayName: user.displayName ?? "",
            provider: provider
        )
    }
#else
    private func persistFallbackUser(_ user: AuthUser) throws {
        do {
            let data = try encoder.encode(user)
            userDefaults.set(data, forKey: Keys.savedAuthUser)
            userDefaults.set(true, forKey: Keys.hasActiveSession)
        } catch {
            throw AppError.auth("Failed to persist auth user: \(error.localizedDescription)")
        }
    }
#endif
}
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            completion(.success(credential))
        } else {
            completion(.failure(AppError.auth("Apple authorization did not return expected credential.")))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
    }
}
