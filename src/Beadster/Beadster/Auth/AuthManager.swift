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

    // GitHub OAuth app for native/desktop clients
    private let githubClientId = "Ov23liavcvvoCTeFIshc"

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
        print("[auth] Checking authentication...")
        if let apiKey = keychainManager.getAPIKey() {
            print("[auth] Found API key in keychain")
            isAuthenticated = true
            // Set API token for APIClient
            APIClient.shared.apiToken = apiKey
            print("[auth] Set APIClient.apiToken")
            // TODO: Load user info from local DB or API
        } else {
            print("[auth] No API key found in keychain")
            isAuthenticated = false
            currentUser = nil
            APIClient.shared.apiToken = nil
        }
        print("[auth] isAuthenticated = \(isAuthenticated)")
    }

    // MARK: - Sign In

    /// Start GitHub OAuth flow
    func signIn() {
        isLoading = true
        error = nil

        // Build GitHub OAuth URL directly (not using Better Auth for native apps)
        let state = UUID().uuidString
        let redirectURI = "beadster://callback"

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: githubClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "read:user user:email"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            self.isLoading = false
            self.error = "Failed to build OAuth URL"
            return
        }

        // Create web authentication session
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "beadster"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleOAuthCallback(callbackURL: callbackURL, error: error, expectedState: state)
            }
        }

        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false

        if !authSession!.start() {
            self.isLoading = false
            self.error = "Failed to start authentication"
        }
    }

    /// Handle OAuth callback
    private func handleOAuthCallback(callbackURL: URL?, error: Error?, expectedState: String) {
        if let error = error {
            isLoading = false
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled - not an error
                return
            }
            self.error = "Authentication failed: \(error.localizedDescription)"
            return
        }

        guard let callbackURL = callbackURL else {
            isLoading = false
            self.error = "No callback URL received"
            return
        }

        print("[auth] OAuth callback received: \(callbackURL)")

        // Parse callback URL to get code and state
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            isLoading = false
            self.error = "Invalid callback parameters"
            return
        }

        // Verify state matches
        guard state == expectedState else {
            isLoading = false
            self.error = "Invalid state parameter"
            return
        }

        // Exchange code for API key via our backend
        Task {
            await exchangeCodeForAPIKey(code: code)
        }
    }

    /// Exchange OAuth code for API key via backend
    private func exchangeCodeForAPIKey(code: String) async {
        isLoading = true

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/auth/native/exchange")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["code": code, "client_id": githubClientId]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[auth] Invalid response type")
                throw AuthError.invalidResponse
            }

            print("[auth] Exchange response status: \(httpResponse.statusCode)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("[auth] Exchange response body: \(responseBody)")
            }

            guard httpResponse.statusCode == 200 else {
                print("[auth] Non-200 status code: \(httpResponse.statusCode)")
                throw AuthError.invalidResponse
            }

            let result = try JSONDecoder().decode(APIKeyResponse.self, from: data)

            // Save API key to Keychain
            try keychainManager.saveAPIKey(result.apiKey)

            // Update state
            isAuthenticated = true
            currentUser = result.user

            // Set API token for APIClient
            APIClient.shared.apiToken = result.apiKey

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
            APIClient.shared.apiToken = nil
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
