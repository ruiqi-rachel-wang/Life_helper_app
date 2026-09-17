//  CallConfirmView.swift
//
//  The one screen between "yes, call for me" and a real phone ringing in a real
//  office. It is the human authorisation, so it is deliberately short: the
//  backend carries the rules, and this page only has to make the recipient and
//  the request unmistakable.
//
//  Four things are on it, and nothing else:
//    • WHO is being called — from the document, never invented.
//    • WHAT will be asked — editable, because the AI's suggestion is a draft.
//    • WHAT Tadah may agree to — the user's authorisation. Defaults to nothing,
//      which makes a plain question the safe default and a commitment a
//      deliberate act.
//    • WHETHER to share the account number — off by default. A billing call
//      genuinely needs it, but it is the user's data going to a third party, so
//      it is a visible choice rather than a silent inclusion.
//
//  Card, bank and Social Security numbers are refused by the Worker no matter
//  what is typed here or which box is ticked.
//

import SwiftUI

struct CallConfirmView: View {
    let offer: CallOffer
    let callsUsed: Int
    let callsLimit: Int
    /// Confirmed: the edited goal, the authorisation, and whether to include the
    /// document's reference number.
    var onCall: (_ phone: String, _ goal: String, _ mayAgreeTo: String, _ shareAccount: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var goal: String
    @State private var phone: String
    @State private var editingPhone = false
    @State private var permission: CallPermission = .nothing
    @State private var customPermission = ""
    @State private var shareAccount = false
    @State private var showHowItWorks = false
    @FocusState private var goalFocused: Bool
    @FocusState private var phoneFocused: Bool

    /// `phone` and `goal` reopen the page as the user last sent it, for "Try
    /// again" on the to-do. The offer still holds the document's own number, so
    /// "You changed this number" stays true.
    init(offer: CallOffer, phone: String? = nil, goal: String? = nil,
         callsUsed: Int = 0, callsLimit: Int = 5,
         onCall: @escaping (String, String, String, Bool) -> Void) {
        self.offer = offer
        self.callsUsed = callsUsed
        self.callsLimit = callsLimit
        self.onCall = onCall
        _goal = State(initialValue: goal ?? offer.goal)
        _phone = State(initialValue: phone ?? offer.phone)
    }

    private var authorisationText: String {
        permission == .custom
            ? customPermission.trimmingCharacters(in: .whitespacesAndNewlines)
            : permission.authorisation
    }

    /// What this DOCUMENT could sensibly authorise. A water bill has no
    /// appointment to book, and offering one trains people to pick without
    /// reading — the opposite of what an authorisation control is for.
    private var permissionChoices: [CallPermission] {
        offer.permissions.isEmpty ? [.nothing, .callback, .custom] : offer.permissions
    }

    /// Only structural validity is checked here — the Worker re-checks properly
    /// and is the authority. This exists so a typo is caught while the user is
    /// still looking at the field, rather than as a failure after "Call now".
    private var phoneIsDialable: Bool {
        CallOffer.isValidNANP(CallOffer.phoneDigits(phone))
    }

    // The Worker's limits, counted the way it counts (JavaScript string length,
    // which is UTF-16), on the question AS SENT: with whom it's to and, if
    // shared, the account number. Past these the Worker refuses, and a refusal
    // after "Call now" lands on the to-do instead of here where it can be fixed.
    private static let maxQuestion = 600
    private static let maxAgreement = 200
    private static let lengthProbeItem = UUID()   // any id; only the length is read

    private var questionLength: Int {
        CallCenter.request(offer: offer, phone: phone,
                           goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                           mayAgreeTo: "", shareAccount: shareAccount, name: "", language: "en",
                           itemID: Self.lengthProbeItem).goal
            .trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    }
    private var questionOver: Int { max(0, questionLength - Self.maxQuestion) }
    private var agreementTooLong: Bool { authorisationText.utf16.count > Self.maxAgreement }

    private var canCall: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phoneIsDialable
            && questionOver == 0 && !agreementTooLong
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recipientCard
                        askCard
                        permissionCard
                        if offer.accountNumber != nil { accountCard }
                        promiseBlock
                        callButton
                        Spacer(minLength: 24)
                    }
                    .padding(16)
                }
                // Two text fields (the number and what to ask) and no way out of
                // the keyboard: tapping the card, the page or the scroll view
                // left it up, covering the call button on a small phone. Same
                // modifier Detail uses, plus the drag dismissal, because the
                // natural gesture here is to scroll the page away.
                .scrollDismissesKeyboard(.interactively)
            }
            .dismissKeyboardOnTap()
            .navigationTitle(Text("Before Tadah calls"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showHowItWorks) { HowCallsWorkView() }
        }
        // iPad shows a sheet as a small centred form by default, and "Call now"
        // sat below its fold. The page size fits the whole confirm page.
        .pageSizedOnIPad()
    }

    // WHO — correctable, because the number is read off a photographed document
    // and OCR is not perfect. Getting this wrong means ringing a stranger, so the
    // user must be able to fix it before, not discover it after.
    private var recipientCard: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("TADAH WILL CALL").font(.eyebrow).foregroundStyle(Color.faint)
                    Spacer(minLength: 8)
                    Button(editingPhone ? "Done" : "Change") {
                        editingPhone.toggle()
                        if editingPhone { phoneFocused = true }
                    }
                    .font(.eyebrow).foregroundStyle(Color.accent).buttonStyle(.plain)
                }
                if let business = offer.business, !business.isEmpty {
                    Text(business).font(.cardTitle).foregroundStyle(Color.ink)
                }

                if editingPhone {
                    TextField("Phone number", text: $phone)
                        .font(.body14).foregroundStyle(Color.ink)
                        .keyboardType(.phonePad)
                        .focused($phoneFocused)
                        .padding(8)
                        .background(Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(phoneIsDialable ? Color.accent : Color.bad, lineWidth: 1))
                } else {
                    Text(phone).font(.body14).foregroundStyle(Color.faded).monospacedDigit()
                }

                if !phoneIsDialable {
                    Text("That isn't a US phone number Tadah can dial.")
                        .font(.subline).foregroundStyle(Color.bad).padding(.top, 2)
                } else if phone == offer.phone {
                    Text("This number came from your document.")
                        .font(.subline).foregroundStyle(Color.faint).padding(.top, 2)
                } else {
                    Text("You changed this number.")
                        .font(.subline).foregroundStyle(Color.faint).padding(.top, 2)
                }
            }
        }
    }

    // WHAT IT WILL ASK
    private var askCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                // The label carries the affordance. A bare TextEditor with no
                // border reads as printed text, and the first tester did not
                // realise the question could be changed at all.
                HStack(spacing: 6) {
                    Text("ASK").font(.eyebrow).foregroundStyle(Color.faint)
                    Spacer(minLength: 8)
                    Label {
                        Text("Tap to change").font(.eyebrow)
                    } icon: {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.accent)
                }
                TextEditor(text: $goal)
                    .font(.body14).foregroundStyle(Color.ink)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .focused($goalFocused)
                    .padding(8)
                    // A visible field, so it looks like something you can type in.
                    .background(Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(goalFocused ? Color.accent : Color.hair, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if goal.isEmpty {
                            Text("What should Tadah ask?")
                                .font(.body14).foregroundStyle(Color.hint)
                                .padding(.top, 16).padding(.leading, 13)
                                .allowsHitTesting(false)
                        }
                    }
                if questionOver > 0 {
                    Text("That's too long for one call. Shorten it by \(questionOver) characters.")
                        .font(.subline).foregroundStyle(Color.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The call is in English whatever language the app is in — that
                // gap is the whole point of the feature, so say it plainly
                // rather than letting someone wonder.
                Text("Tadah will make the call in English and tell you what they said, in your language.")
                    .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // WHAT IT MAY AGREE TO
    private var permissionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("MAY AGREE TO").font(.eyebrow).foregroundStyle(Color.faint)
                Picker("", selection: $permission) {
                    ForEach(permissionChoices) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).tint(Color.ink).labelsHidden()

                if permission == .custom {
                    TextField("For example: a delivery date", text: $customPermission, axis: .vertical)
                        .font(.body14).foregroundStyle(Color.ink)
                        .textFieldStyle(.roundedBorder)
                    if agreementTooLong {
                        Text("Keep this to 200 characters or fewer.")
                            .font(.subline).foregroundStyle(Color.bad)
                    }
                }
                Text(permission == .nothing
                     ? String(localized: "Tadah will only ask. It won't agree to anything for you.")
                     : String(localized: "Tadah may agree to this, and nothing else."))
                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // THE ONE OPTIONAL DISCLOSURE
    private var accountCard: some View {
        card {
            Toggle(isOn: $shareAccount) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.accountTail.map { String(localized: "Share my \(offer.accountLabel ?? "reference") number (···\($0))") }
                         ?? String(localized: "Share my reference number"))
                        .font(.body14).foregroundStyle(Color.ink)
                    Text("Often needed so they can find your account.")
                        .font(.subline).foregroundStyle(Color.faint)
                }
            }
            .tint(Color.ink)
        }
    }

    // The promises, in one short block rather than a wall.
    private var promiseBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Tadah says it's an AI, never gives out card, bank or Social Security numbers, and never agrees to a charge.")
                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Color.faint)
            }
            if callsLimit > 0 {
                // Not "Call N of M": the app can't know how many calls were already
                // used this month until the Worker answers, so that line always said
                // "Call 1" — wrong from the second call on.
                Text("Tadah Plus includes \(callsLimit) calls a month.")
                    .font(.subline).foregroundStyle(Color.faint)
            }
        }
        .padding(.horizontal, 2)
    }

    private var callButton: some View {
        VStack(spacing: 10) {
            Button {
                onCall(phone.trimmingCharacters(in: .whitespacesAndNewlines),
                       goal.trimmingCharacters(in: .whitespacesAndNewlines),
                       authorisationText, shareAccount)
                dismiss()
            } label: {
                Text("Call now")
                    .font(.cardTitle).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(canCall ? Color.accent : Color.hairD)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(!canCall)

            Button("How calls work") { showHowItWorks = true }
                .font(.subline).foregroundStyle(Color.faded)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

// The long version, kept off the confirm page so that page stays readable.
private struct HowCallsWorkView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        point("It says it's an AI", "Tadah opens every call by saying it is an AI assistant calling for you. There is no setting to turn that off.")
                        point("You are never on the line", "Tadah makes the call on its own and tells you what happened afterwards.")
                        point("It calls in English", "Whatever language you use Tadah in, the call is in English — and the answer comes back in your language.")
                        point("It won't give out your details", "Never a card, bank or Social Security number, or a date of birth — even if asked directly.")
                        point("It won't agree to a charge", "Tadah never accepts a fee or payment for you, and only commits you to what you allowed on the last screen.")
                        point("It keeps calls short", "Tadah ends the call after about four minutes, or sooner if it is put on hold.")
                        point("What's kept", "The answer stays on your to-do. A written copy of the call is deleted after 30 days, and no audio is ever recorded.")
                        Spacer(minLength: 24)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(Text("How calls work"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func point(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.cardTitle).foregroundStyle(Color.ink)
            Text(body).font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// A taller sheet on iPad (iOS 18+). iPhone sheets are unaffected.
    @ViewBuilder
    func pageSizedOnIPad() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
