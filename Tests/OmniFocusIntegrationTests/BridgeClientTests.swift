import Foundation
import Testing
@testable import OmniFocusAutomation

@Test
func bridgeClientConfigurationDefaults() {
    let configuration = BridgeClientConfiguration.fromEnvironment([:])

    #expect(configuration.responseTimeout == 45.0)
    #expect(configuration.responsePollInterval == 0.05)
}

@Test
func bridgeClientConfigurationUsesEnvironmentOverrides() {
    let configuration = BridgeClientConfiguration.fromEnvironment([
        "FOCUS_RELAY_BRIDGE_RESPONSE_TIMEOUT_SECONDS": "30",
        "FOCUS_RELAY_BRIDGE_RESPONSE_POLL_MS": "25"
    ])

    #expect(configuration.responseTimeout == 30.0)
    #expect(configuration.responsePollInterval == 0.025)
}

@Test
func bridgeClientConfigurationIgnoresInvalidEnvironmentOverrides() {
    let configuration = BridgeClientConfiguration.fromEnvironment([
        "FOCUS_RELAY_BRIDGE_RESPONSE_TIMEOUT_SECONDS": "0",
        "FOCUS_RELAY_BRIDGE_RESPONSE_POLL_MS": "-1"
    ])

    #expect(configuration.responseTimeout == 45.0)
    #expect(configuration.responsePollInterval == 0.05)
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
func lateStrandedRecoveryOnlyAppliesWithoutResponseOrLock() {
    #expect(shouldAttemptLateStrandedRecovery(
        requestExists: true,
        responseExists: false,
        lockExists: false
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        requestExists: true,
        responseExists: false,
        lockExists: true
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        requestExists: true,
        responseExists: true,
        lockExists: false
    ))

    #expect(!shouldAttemptLateStrandedRecovery(
        requestExists: false,
        responseExists: false,
        lockExists: false
    ))
}

@Test
func bridgePickupStateNamesTimeoutCause() {
    #expect(bridgePickupState(
        requestExists: true,
        responseExists: false,
        lockExists: false
    ) == "stranded_not_picked_up")

    #expect(bridgePickupState(
        requestExists: true,
        responseExists: false,
        lockExists: true
    ) == "bridge_processing")

    #expect(bridgePickupState(
        requestExists: true,
        responseExists: true,
        lockExists: false
    ) == "response_written")

    #expect(bridgePickupState(
        requestExists: false,
        responseExists: false,
        lockExists: false
    ) == "request_missing")
}
