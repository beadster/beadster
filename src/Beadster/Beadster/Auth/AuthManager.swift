import Foundation
import AuthenticationServices

/// Manages GitHub OAuth authentication for beadster
@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: String?

    private let keychainManager = KeychainManager.shared
    private let baseURL = "https://beadster.ai"

    private var authSession: ASWebAuthenticationSession?

    // URLSession with cookie storage for OAuth
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    override private init() {
        super.init()
        checkAuthentication()
    }

    // MARK: - Authentication State

    /// Check if user is authenticated (has valid API key)
    func checkAuthentication() {
        if let apiKey = keychainManager.getAPIKey() {
            isAuthenticated = true
            // TODO: Load user info from local DB or API
        } else {
            isAuthenticated = false
            currentUser = nil
        }
    }

    // MARK: - Sign In

    /// Start GitHub OAuth flow
    func signIn() {
        isLoading = true
        error = nil

        // Initiate OAuth by POSTing to the sign-in endpoint
        Task {
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/api/auth/sign-in/social")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Use web callback URL - server will redirect to beadster:// after handling OAuth
                let body = ["provider": "github", "callbackURL": "\(baseURL)/"]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw AuthError.invalidResponse
                }

                let result = try JSONDecoder().decode(OAuthURLResponse.self, from: data)

                // Now open the OAuth URL in a web authentication session
                await startAuthSession(url: result.url)

            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.error = "Failed to start OAuth: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Start the web authentication session with the OAuth URL
    private func startAuthSession(url: String) async {
        guard let authURL = URL(string: url) else {
            await MainActor.run {
                self.isLoading = false
                self.error = "Invalid OAuth URL"
            }
            return
        }

        await MainActor.run {
            // Create web authentication session
            // This will intercept any redirect to https://beadster.ai after OAuth
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "https"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    await self?.handleOAuthCallback(callbackURL: callbackURL, error: error)
                }
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false

            if !authSession!.start() {
                self.isLoading = false
                self.error = "Failed to start authentication"
            }
        }
    }

    /// Handle OAuth callback
    private func handleOAuthCallback(callbackURL: URL?, error: Error?) {
        isLoading = false

        if let error = error {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled - not an error
                return
            }
            self.error = "Authentication failed: \(error.localizedDescription)"
            return
        }

        guard let callbackURL = callbackURL else {
            self.error = "No callback URL received"
            return
        }

        print("[auth] OAuth callback received: \(callbackURL)")

        // After successful OAuth, session cookies are set
        // Now get the API key using the session
        Task {
            await fetchAPIKey()
        }
    }

    /// Fetch API key from server after successful OAuth
    private func fetchAPIKey() async {
        isLoading = true

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/auth/api-key")!)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw AuthError.invalidResponse
            }

            let result = try JSONDecoder().decode(APIKeyResponse.self, from: data)

            // Save API key to Keychain
            try keychainManager.saveAPIKey(result.apiKey)

            // Update state
            isAuthenticated = true
            currentUser = result.user

            print("[auth] Successfully authenticated as \(result.user.githubLogin ?? "unknown")")

        } catch {
            self.error = "Failed to get API key: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Sign Out

    /// Sign out and delete API key
    func signOut() {
        do {
            try keychainManager.deleteAPIKey()
            isAuthenticated = false
            currentUser = nil
            print("[auth] Signed out successfully")
        } catch {
            self.error = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    // MARK: - API Key Access

    /// Get current API key for making authenticated requests
    func getAPIKey() -> String? {
        return keychainManager.getAPIKey()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Models

struct User: Codable {
    let id: String
    let githubLogin: String?
    let githubName: String?
    let githubEmail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case githubLogin = "github_login"
        case githubName = "github_name"
        case githubEmail = "github_email"
    }
}

struct APIKeyResponse: Codable {
    let apiKey: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case user
    }
}

struct OAuthURLResponse: Codable {
    let url: String
    let state: String?
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidResponse
    case apiKeyNotFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiKeyNotFound:
            return "API key not found"
        }
    }
}
