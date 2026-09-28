import Foundation
import StoreKit
import Testing
import UIKit
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct TestFlightAccessTests {
    @Test func productionAndLocalDevelopmentDoNotRequireMembership() async {
        for local in [false, true] {
            let gate = TestFlightAccessController(localDevelopment: local, environment: { .production }, uid: { nil }, verify: {
                Issue.record("App Store/local builds must not query beta access")
                return false
            })
            await gate.refresh()
            #expect(gate.state == .unrestricted)
            gate.invalidate()
            #expect(gate.state.allowsUse)
        }
    }

    @Test func sandboxRequiresLoginAndProductionMembership() async {
        var uid: String?
        var active = true
        var calls = 0
        let gate = TestFlightAccessController(localDevelopment: false, environment: { .sandbox }, uid: { uid }, verify: {
            calls += 1
            return active
        })
        #expect(!gate.state.allowsUse)
        await gate.refresh()
        #expect(gate.state == .signInRequired)
        #expect(calls == 0)
        uid = "buyer"
        await gate.refresh()
        #expect(gate.state == .allowed)
        #expect(calls == 1)
        gate.invalidate()
        #expect(!gate.state.allowsUse)
        active = false
        await gate.refresh()
        #expect(gate.state == .ineligible)
        #expect(calls == 2)
    }

    @Test func offlineCannotReuseEarlierSuccess() async {
        var offline = false
        let gate = TestFlightAccessController(localDevelopment: false, environment: { .sandbox }, uid: { "buyer" }, verify: {
            if offline { throw URLError(.notConnectedToInternet) }
            return true
        })
        await gate.refresh()
        #expect(gate.state.allowsUse)
        offline = true
        await gate.refresh()
        #expect(gate.state == .unavailable)
        #expect(!gate.state.allowsUse)
    }

    @Test func unverifiedEnvironmentCannotUseCachedSandboxOrProductionStatus() async {
        let gate = TestFlightAccessController(localDevelopment: false, environment: {
            throw URLError(.notConnectedToInternet)
        }, uid: { "buyer" }, verify: { true })
        await gate.refresh()
        #expect(gate.state == .unavailable)
    }

    @Test func lateSuccessCannotUnlockAfterBackgroundingOrAccountSwitch() async {
        for switchesAccount in [false, true] {
            var uid = "buyer"
            let pending = PendingVerification()
            let gate = TestFlightAccessController(localDevelopment: false, environment: { .sandbox }, uid: { uid }, verify: {
                await pending.verify()
            })
            let task = Task { await gate.refresh() }
            await pending.waitUntilStarted()
            if switchesAccount { uid = "other" }
            gate.invalidate()
            pending.finish(true)
            await task.value
            #expect(!gate.state.allowsUse)
        }
    }

    @Test func cancelledRequestCannotGrantAccess() async {
        let pending = PendingVerification()
        let gate = TestFlightAccessController(localDevelopment: false, environment: { .sandbox }, uid: { "buyer" }, verify: {
            await pending.verify()
        })
        let task = Task { await gate.refresh() }
        await pending.waitUntilStarted()
        task.cancel()
        pending.finish(true)
        await task.value
        #expect(!gate.state.allowsUse)
    }

    @Test func gateCoversPresentedContentWithoutDestroyingReaderNavigation() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let reader = UIViewController()
        let navigation = UINavigationController(rootViewController: reader)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        let presented = UIViewController()
        reader.present(presented, animated: false)
        let gate = TestFlightGateWindow.Coordinator()
        defer {
            gate.dismiss()
            window.isHidden = true
            previousKey?.makeKeyAndVisible()
        }

        gate.state = .checking
        gate.update(window: window)
        let currentKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let gateWindow = try #require(currentKeyWindow)
        #expect(gateWindow !== window)
        #expect(gateWindow.windowLevel == .alert)
        #expect(gateWindow.bounds.size == scene.coordinateSpace.bounds.size)
        #expect(!window.isUserInteractionEnabled)
        #expect(window.accessibilityElementsHidden)
        #expect(window.rootViewController === navigation)
        #expect(reader.presentedViewController === presented)

        gate.state = .allowed
        gate.update(window: window)
        #expect(window.isKeyWindow)
        #expect(window.isUserInteractionEnabled)
        #expect(!window.accessibilityElementsHidden)
        #expect(navigation.topViewController === reader)
        #expect(reader.presentedViewController === presented)
    }
}

@MainActor
private final class PendingVerification {
    private var result: CheckedContinuation<Bool, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func verify() async -> Bool {
        await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ allowed: Bool) {
        result?.resume(returning: allowed)
        result = nil
    }
}
