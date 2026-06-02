import Foundation
import Testing
@testable import OmniFocusAutomation

@Test
func bridgeClientConfigurationDefaults() {
    let configuration = BridgeClientConfiguration.fromEnvironment([:])

    #expect(configuration.responseTimeout == 45.0)
    #expect(configuration.responsePollInterval == 0.05)
    #expect(configuration.dispatchTransport == .urlScheme)
    #expect(configuration.dispatchTimeout == 20.0)
}

@Test
func bridgeClientConfigurationUsesEnvironmentOverrides() {
    let configuration = BridgeClientConfiguration.fromEnvironment([
        "FOCUS_RELAY_BRIDGE_RESPONSE_TIMEOUT_SECONDS": "30",
        "FOCUS_RELAY_BRIDGE_RESPONSE_POLL_MS": "25",
        "FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT": "jxa",
        "FOCUS_RELAY_BRIDGE_DISPATCH_TIMEOUT_SECONDS": "18"
    ])

    #expect(configuration.responseTimeout == 30.0)
    #expect(configuration.responsePollInterval == 0.025)
    #expect(configuration.dispatchTransport == .jxaEvaluate)
    #expect(configuration.dispatchTimeout == 18.0)
}

@Test
func bridgeClientConfigurationIgnoresInvalidEnvironmentOverrides() {
    let configuration = BridgeClientConfiguration.fromEnvironment([
        "FOCUS_RELAY_BRIDGE_RESPONSE_TIMEOUT_SECONDS": "0",
        "FOCUS_RELAY_BRIDGE_RESPONSE_POLL_MS": "-1",
        "FOCUS_RELAY_BRIDGE_DISPATCH_TIMEOUT_SECONDS": "0"
    ])

    #expect(configuration.responseTimeout == 45.0)
    #expect(configuration.responsePollInterval == 0.05)
    #expect(configuration.dispatchTransport == .urlScheme)
    #expect(configuration.dispatchTimeout == 20.0)
}

@Test
func strandedRedispatchDelayIsBounded() {
    #expect(strandedRedispatchDelay(timeout: 45.0) == 2.0)
    #expect(abs(strandedRedispatchDelay(timeout: 12.0) - 1.2) < 0.000_001)
    #expect(strandedRedispatchDelay(timeout: 3.0) == 0.5)
}

@Test
func lateStrandedRecoveryGraceIsBounded() {
    #expect(lateStrandedRecoveryGrace(timeout: 45.0) == 9.0)
    #expect(abs(lateStrandedRecoveryGrace(timeout: 12.0) - 3.0) < 0.000_001)
    #expect(lateStrandedRecoveryGrace(timeout: 120.0) == 10.0)
}

@Test
func bridgeDispatchTransportDefaultsToURL() {
    #expect(BridgeDispatchTransport.fromEnvironment([:]) == .urlScheme)
    #expect(BridgeDispatchTransport.fromEnvironment(["FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT": "url"]) == .urlScheme)
}

@Test
func bridgeDispatchTransportSupportsJXA() {
    #expect(BridgeDispatchTransport.fromEnvironment(["FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT": "jxa"]) == .jxaEvaluate)
    #expect(BridgeDispatchTransport.fromEnvironment(["FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT": "JXA"]) == .jxaEvaluate)
}

@Test
func buildBridgeDispatchScriptUsesStableDispatchRequestFile() {
    let script = buildBridgeDispatchScript(basePath: "/tmp/focusrelay")

    #expect(script.contains("/dispatch/request.json"))
    #expect(!script.contains("var requestId = argument;"))
    #expect(script.contains("handleRequest(requestId, basePath)"))
}

@Test
func lateStrandedRecoveryOnlyAppliesToURLTransportWithoutLock() {
    #expect(shouldAttemptLateStrandedRecovery(
        transport: .urlScheme,
        requestExists: true,
        responseExists: false,
        lockExists: false
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        transport: .urlScheme,
        requestExists: true,
        responseExists: false,
        lockExists: true
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        transport: .jxaEvaluate,
        requestExists: true,
        responseExists: false,
        lockExists: false
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        transport: .urlScheme,
        requestExists: false,
        responseExists: false,
        lockExists: false
    ))
}
