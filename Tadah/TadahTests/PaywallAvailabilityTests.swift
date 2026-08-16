//  PaywallAvailabilityTests.swift
//
//  Pins WHICH RevenueCat failures mean "nothing on sale yet" and which mean
//  "try again".
//
//  This existed as a real bug: before the products are in App Store Connect and
//  in a Current Offering, RevenueCat throws `.configurationError` rather than
//  returning an empty list, and the paywall sent every thrown error to the retry
//  screen. A Simulator run showed "We couldn't load Tadah Plus — please check
//  your connection", which was wrong (the network was fine) and unactionable
//  (Retry could never succeed). Rachel saw that screen, not a developer.
//
//  The asymmetry below is deliberate: an unrecognised error stays RETRYABLE. A
//  wrong "coming soon" would quietly hide a genuine outage from us; a wrong
//  "check your connection" is merely annoying.
//

import Testing
import Foundation
import RevenueCat
@testable import Tadah

@Suite("Paywall availability")
struct PaywallAvailabilityTests {

    @Test("Configuration error reads as 'not on sale yet', not a network failure")
    func configurationErrorIsNotForSaleYet() {
        #expect(PaywallView.isStoreNotSetUp(ErrorCode.configurationError))
    }

    @Test("A product that can't be purchased also reads as 'not on sale yet'")
    func unavailableProductIsNotForSaleYet() {
        #expect(PaywallView.isStoreNotSetUp(ErrorCode.productNotAvailableForPurchaseError))
    }

    @Test("Genuine connectivity failures stay retryable")
    func networkErrorsStayRetryable() {
        #expect(!PaywallView.isStoreNotSetUp(ErrorCode.networkError))
        #expect(!PaywallView.isStoreNotSetUp(ErrorCode.offlineConnectionError))
        #expect(!PaywallView.isStoreNotSetUp(ErrorCode.unknownBackendError))
    }

    @Test("An error that isn't RevenueCat's stays retryable")
    func foreignErrorsStayRetryable() {
        let urlError = URLError(.notConnectedToInternet)
        #expect(!PaywallView.isStoreNotSetUp(urlError))
    }
}
