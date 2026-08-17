//  AIConsentSheet.swift
//
//  The just-in-time ask before a document's text is ever sent to OpenAI.
//
//  Shown on the FIRST tap of "Scan a document" — the moment the user is holding
//  the letter and the question is concrete — rather than during onboarding, where
//  it would be one more screen to dismiss before anything had happened.
//
//  WRITTEN TO BE UNDERSTOOD, NOT TO BE DEFENSIBLE. Rachel's users include people
//  reading this in a second language, about a document that matters. So it says
//  the specific thing that leaves the phone (the words on the page), the specific
//  thing that does not (the photo), and the specific risk (whatever is printed on
//  it — a diagnosis, a case number). No "third-party processors", no "may
//  include personal data".
//
//  Both buttons are plain and equally reachable. There is no dark pattern here:
//  "Not now" is a real choice that leaves a working app behind it.
//

import SwiftUI

struct AIConsentSheet: View {
    let onDecision: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BEFORE YOUR FIRST SCAN")
                                .font(.eyebrow).tracking(1.2).foregroundStyle(Color.faded)
                            Text("Scanning sends the words to AI")
                                .font(.serifTitle).tracking(-0.5).foregroundStyle(Color.ink)
                        }

                        Text("To explain a document and turn it into steps, Tadah sends the words it reads to OpenAI, an AI company we use. We need your OK first.")
                            .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 12) {
                            point("doc.text.magnifyingglass",
                                  "Your phone reads the document, then sends that text — not the photo. Your photos never leave your phone.")
                            // The honest, uncomfortable sentence. It is the whole
                            // reason this screen exists, so it is not softened.
                            point("exclamationmark.triangle.fill",
                                  "The text is whatever is printed on the page — that can include your name, a medical condition, a case or account number, or money details.")
                            point("clock.arrow.circlepath",
                                  "OpenAI does not use it to train their AI, and may keep it up to about 30 days to check for misuse. We keep no copy on our server.")
                            // Says ACCOUNT, not "name". The line above has just
                            // warned that the page's text can contain your name —
                            // "we don't send your name" flatly contradicted it.
                            // What we withhold is the Tadah account behind the
                            // request, not whatever is printed on the paper.
                            // "OpenAI can't tell whose document it is" was not
                            // true, and it sat two lines under a warning that the
                            // page can carry a name and a case number. We withhold
                            // the ACCOUNT; we cannot withhold what is printed on
                            // the paper, and claiming otherwise is the kind of
                            // reassurance that makes the rest untrustworthy.
                            point("person.crop.circle.badge.xmark",
                                  "We don't attach your Tadah account or sign-in email. OpenAI still receives any identifying details printed on the document.")
                            // The app's other AI path, disclosed HERE rather than
                            // discovered later: one permission covers both.
                            point("mappin.and.ellipse",
                                  "This same permission covers one more thing: in the moving and renting guides, a ZIP code you type is sent with your answers to name your local utility companies. Every other guide is built on your phone.")
                        }

                        // Says the app still works. Someone who declines should not
                        // be left wondering what they have just broken.
                        Text("Prefer not to? Tap “Not now.” You can still add to-dos yourself, use the guides, and set reminders — and you can change this any time in Profile → Privacy.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 10) {
                            Button { decide(true) } label: {
                                Text("OK, send scans to AI")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.paper)
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                            }
                            .buttonStyle(.plain)

                            Button { decide(false) } label: {
                                Text("Not now")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.hairD, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15)).foregroundStyle(Color.accent)
                .frame(width: 22)
            Text(text)
                .font(.subline).foregroundStyle(Color.ink).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func decide(_ granted: Bool) {
        AIConsent.record(granted: granted)
        onDecision(granted)
        dismiss()
    }
}
