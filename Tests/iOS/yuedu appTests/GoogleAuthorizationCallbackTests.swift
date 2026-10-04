import AppAuth
import Foundation
import GoogleSignIn
import Testing

/// Exercises the real AppAuth session used by GoogleSignIn, without opening a browser
/// or exchanging credentials. App Store Cj19Q59kC3ozuJpn20g58F crashed on a late redirect.
@Suite("Google authorization callback lifecycle", .serialized)
@MainActor
struct GoogleAuthorizationCallbackTests {
    @Test("a successful authorization is completed once, even if its redirect arrives twice")
    func duplicateRedirectAfterSuccess() throws {
        let flow = try makeFlow()
        let url = try redirect(for: flow.request)
        try flow.session.resumeExternalUserAgentFlow(url)
        #expect(flow.result.callCount == 1)
        #expect(flow.result.response?.authorizationCode == "test-code")
        #expect(flow.result.error == nil)

        #expect {
            try flow.session.resumeExternalUserAgentFlow(url)
        } throws: { error in
            isGeneralError(error, code: .invalidAuthorizationFlow)
        }
        #expect(flow.result.callCount == 1)
    }

    @Test("a late redirect after cancellation is rejected and a fresh session still works")
    func redirectAfterCancellation() throws {
        let cancelled = try makeFlow()
        cancelled.session.cancel()
        #expect(cancelled.result.callCount == 1)
        #expect(cancelled.result.response == nil)
        #expect(cancelled.result.error?.domain == OIDGeneralErrorDomain)
        #expect(cancelled.result.error?.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue)
        let url = try redirect(for: cancelled.request)
        #expect {
            try cancelled.session.resumeExternalUserAgentFlow(url)
        } throws: { error in
            isGeneralError(error, code: .invalidAuthorizationFlow)
        }
        #expect(cancelled.result.callCount == 1)

        let fresh = try makeFlow()
        try fresh.session.resumeExternalUserAgentFlow(redirect(for: fresh.request))
        #expect(fresh.result.response?.authorizationCode == "test-code")
        #expect(fresh.result.error == nil)
    }

    @Test("an unrelated URL leaves the pending authorization available for its real redirect")
    func unrelatedURLDoesNotConsumeSession() throws {
        let flow = try makeFlow()
        let unrelated = try #require(URL(string: "yuedu-test:/unrelated?code=test-code"))
        #expect {
            try flow.session.resumeExternalUserAgentFlow(unrelated)
        } throws: { error in
            isGeneralError(error, code: .urlMismatch)
        }
        #expect(flow.result.callCount == 0)
        try flow.session.resumeExternalUserAgentFlow(redirect(for: flow.request))
        #expect(flow.result.callCount == 1)
        #expect(flow.result.response?.authorizationCode == "test-code")
    }

    @Test("a mismatched OAuth state remains an authorization failure")
    func stateMismatchFailsAuthorization() throws {
        let flow = try makeFlow()
        try flow.session.resumeExternalUserAgentFlow(redirect(for: flow.request, state: "wrong-state"))
        #expect(flow.result.callCount == 1)
        #expect(flow.result.response == nil)
        #expect(flow.result.error?.domain == OIDOAuthAuthorizationErrorDomain)
        #expect(flow.result.error?.code == OIDErrorCodeOAuthAuthorization.clientError.rawValue)
    }

    @Test("Google's app URL entry point rejects an orphaned callback without an exception")
    func googleRejectsOrphanedCallback() throws {
        let url = try #require(URL(string: "yuedu-test:/oauth2callback?code=test-code&state=orphaned"))
        #expect(!GIDSignIn.sharedInstance.handle(url))
        #expect(!GIDSignIn.sharedInstance.handle(url))
    }

    private func isGeneralError(_ error: any Error, code: OIDErrorCode) -> Bool {
        let error = error as NSError
        return error.domain == OIDGeneralErrorDomain && error.code == code.rawValue
    }

    private func makeFlow() throws -> (request: OIDAuthorizationRequest, session: any OIDExternalUserAgentSession, result: Result) {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: try #require(URL(string: "https://example.invalid/authorize")),
            tokenEndpoint: try #require(URL(string: "https://example.invalid/token"))
        )
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: "test-client",
            scopes: [OIDScopeOpenID],
            redirectURL: try #require(URL(string: "yuedu-test:/oauth2callback")),
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        let result = Result()
        let session = OIDAuthorizationService.present(request, externalUserAgent: ImmediateExternalUserAgent()) { response, error in
            result.callCount += 1
            result.response = response
            result.error = error as NSError?
        }
        return (request, session, result)
    }

    private func redirect(for request: OIDAuthorizationRequest, state: String? = nil) throws -> URL {
        let redirectURL = try #require(request.redirectURL)
        var components = try #require(URLComponents(url: redirectURL, resolvingAgainstBaseURL: false))
        components.queryItems = [
            URLQueryItem(name: "code", value: "test-code"),
            URLQueryItem(name: "state", value: state ?? request.state)
        ]
        return try #require(components.url)
    }

    private final class Result {
        var callCount = 0
        var response: OIDAuthorizationResponse?
        var error: NSError?
    }
}

private nonisolated final class ImmediateExternalUserAgent: NSObject, OIDExternalUserAgent {
    func present(_ request: any OIDExternalUserAgentRequest, session: any OIDExternalUserAgentSession) -> Bool { true }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        completion()
    }
}
