import Foundation
import Security

public struct ProtectControllerConfiguration: Sendable {
    public let controllerURL: URL
    public let username: String
    public let password: String
    public let allowInsecureTLS: Bool

    public init(
        controllerURL: URL,
        username: String,
        password: String,
        allowInsecureTLS: Bool = false
    ) {
        self.controllerURL = controllerURL
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ProtectControllerConfiguration {
        guard let rawURL = environment["PROTECT_CONTROLLER_URL"], !rawURL.isEmpty else {
            throw ProtectControllerConfigurationError.missingEnvironmentVariable("PROTECT_CONTROLLER_URL")
        }

        guard let username = environment["PROTECT_USERNAME"], !username.isEmpty else {
            throw ProtectControllerConfigurationError.missingEnvironmentVariable("PROTECT_USERNAME")
        }

        guard let password = environment["PROTECT_PASSWORD"], !password.isEmpty else {
            throw ProtectControllerConfigurationError.missingEnvironmentVariable("PROTECT_PASSWORD")
        }

        let allowInsecureTLS = Self.parseBooleanEnvironmentValue(environment["PROTECT_ALLOW_INSECURE_TLS"])

        guard let controllerURL = URL(string: rawURL) else {
            throw ProtectControllerConfigurationError.invalidControllerURL(rawURL)
        }

        return ProtectControllerConfiguration(
            controllerURL: controllerURL,
            username: username,
            password: password,
            allowInsecureTLS: allowInsecureTLS
        )
    }

    private static func parseBooleanEnvironmentValue(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        switch normalized {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    var loginURL: URL {
        let normalizedPath = controllerURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("proxy/protect/api") {
            return controllerURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("api/auth/login")
        }

        return controllerURL.appendingPathComponent("api/auth/login")
    }

    var privateAPIBaseURL: URL {
        let normalizedPath = controllerURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("proxy/protect/api") {
            return controllerURL
        }

        return controllerURL.appendingPathComponent("proxy/protect/api")
    }
}

public enum ProtectControllerConfigurationError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case invalidControllerURL(String)

    public var description: String {
        switch self {
        case let .missingEnvironmentVariable(name):
            return "missing environment variable \(name)"
        case let .invalidControllerURL(value):
            return "invalid PROTECT_CONTROLLER_URL '\(value)'"
        }
    }
}

public enum ProtectControllerClientError: Error, CustomStringConvertible {
    case unexpectedResponseStatus(Int, String)
    case invalidResponse
    case missingAuthenticationCookie

    public var description: String {
        switch self {
        case let .unexpectedResponseStatus(status, url):
            return "Protect controller returned HTTP \(status) for \(url)"
        case .invalidResponse:
            return "Protect controller returned a non-HTTP response"
        case .missingAuthenticationCookie:
            return "Protect login succeeded but did not return an authentication cookie"
        }
    }
}

public struct ProtectCameraRecord: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String?
    public let name: String?

    public init(id: String, displayName: String? = nil, name: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.name = name
    }

    public var resolvedName: String? {
        displayName ?? name
    }
}

public protocol ProtectHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionProtectHTTPTransport: ProtectHTTPTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public init(allowInsecureTLS: Bool = false) {
        if allowInsecureTLS {
            let configuration = URLSessionConfiguration.ephemeral
            let delegate = AllowInsecureTLSURLSessionDelegate()
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = .shared
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProtectControllerClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public actor ProtectControllerClient {
    private let configuration: ProtectControllerConfiguration
    private let transport: ProtectHTTPTransport
    private let decoder: JSONDecoder
    private var cookieHeader: String?
    private var csrfToken: String?

    public init(
        configuration: ProtectControllerConfiguration,
        transport: (any ProtectHTTPTransport)? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.transport = transport ?? URLSessionProtectHTTPTransport(allowInsecureTLS: configuration.allowInsecureTLS)
        self.decoder = decoder
    }

    public func login() async throws {
        var request = URLRequest(url: configuration.loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "username": configuration.username,
                "password": configuration.password,
                "rememberMe": false,
            ],
            options: []
        )

        let (_, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProtectControllerClientError.unexpectedResponseStatus(response.statusCode, configuration.loginURL.absoluteString)
        }

        updateAuthentication(from: response, requestURL: configuration.loginURL)

        guard cookieHeader != nil else {
            throw ProtectControllerClientError.missingAuthenticationCookie
        }
    }

    public func fetchRecentEvents(window: QueryWindow) async throws -> [ProtectEventPayload] {
        try await authenticatedRequest(
            path: "events",
            queryItems: [
                URLQueryItem(name: "start", value: Self.unixMillisecondsString(for: window.start)),
                URLQueryItem(name: "end", value: Self.unixMillisecondsString(for: window.end)),
                URLQueryItem(name: "sorting", value: "desc"),
            ]
        )
    }

    public func fetchCameras() async throws -> [ProtectCameraRecord] {
        try await authenticatedRequest(path: "cameras")
    }

    private func authenticatedRequest<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        if cookieHeader == nil {
            try await login()
        }

        var components = URLComponents(url: configuration.privateAPIBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw ProtectControllerClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        }

        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProtectControllerClientError.unexpectedResponseStatus(response.statusCode, url.absoluteString)
        }

        updateAuthentication(from: response, requestURL: url)
        return try decoder.decode(T.self, from: data)
    }

    private func updateAuthentication(from response: HTTPURLResponse, requestURL: URL) {
        if let token = response.headerValue(named: "x-csrf-token"), !token.isEmpty {
            csrfToken = token
        }

        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else {
                return
            }
            partialResult[key] = value
        }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: requestURL)
        if !cookies.isEmpty {
            cookieHeader = cookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
    }

    private static func unixMillisecondsString(for date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }
}

private final class AllowInsecureTLSURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private extension HTTPURLResponse {
    func headerValue(named name: String) -> String? {
        allHeaderFields.first { key, _ in
            guard let key = key as? String else {
                return false
            }
            return key.caseInsensitiveCompare(name) == .orderedSame
        }?.value as? String
    }
}
