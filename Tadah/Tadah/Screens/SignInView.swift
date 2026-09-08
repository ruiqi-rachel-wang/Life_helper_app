//  SignInView.swift
//
//  Create an account / sign in (Part 3b). EMAIL + PASSWORD, not Sign in with
//  Apple.
//
//  WHY THE CHANGE (2026-08-15): Sign in with Apple authenticates the Apple ID on
//  the DEVICE. On a family member's own iPhone it can therefore only ever create
//  THEIR account — there is no way for them to reach the account holder's. That
//  made "one account, several people, several devices" unbuildable, which is the
//  entire point of the family feature. A shared email and password can be handed
//  to someone; an Apple ID cannot.
//
//  The password never leaves the phone: PasswordCrypto derives a PBKDF2 key and
//  only that is sent. See PasswordCrypto for why the expensive work is here and
//  not on the Worker.
//
//  ONE HONEST DIFFERENCE FROM THE OLD SCREEN. With Apple, authorization could
//  succeed locally while the backend half failed, leaving someone "signed in"
//  with no account behind it — the dead end both code reviews flagged. Email
//  auth has no local half: either the Worker created/returned an account or
//  nothing happened at all. So that failure mode is gone by construction rather
//  than by handling.
//

import SwiftUI
import SwiftData

struct SignInView: View {
    private enum Phase: Equatable {
        case idle
        case working              // deriving the key, then talking to the Worker
        case done                 // account exists and the first sync finished
        case failed(String)       // nothing happened; the message says why
        // There is deliberately NO "signed in, but not backed up yet" phase.
        //
        // One existed, and nothing ever selected it — `.signedInLocally` dismisses,
        // for the reason spelled out in `authenticate()`. A warning on the first
        // attempt would fire for an ordinary network blip that fixes itself on the
        // next foreground, and teaching someone to distrust the app over that is
        // worse than saying nothing. A failure that DOESN'T fix itself is surfaced
        // where it stays visible instead of on a sheet that's already closing:
        // Profile's stuck-backup row (SyncCoordinator.backupIsStuck).
    }

    @Environment(AccountStore.self) private var account
    @Environment(PlusStore.self) private var plus
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isCreating = true      // create-account is the common first visit
    @State private var showReset = false
    @State private var phase: Phase = .idle
    @FocusState private var focused: Field?

    private enum Field: Hashable { case email, password }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Enough to submit. The server validates properly; this only stops obviously
    // pointless round trips and the 600k-iteration derivation behind them.
    private var canSubmit: Bool {
        phase != .working
            && trimmedEmail.contains("@")
            && password.count >= PasswordCrypto.minimumPasswordLength
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    closeBar
                    Spacer(minLength: 12)
                    heading
                    Spacer(minLength: 24)
                    fields
                    submitButton
                    statusBanner
                    forgotPassword
                    Spacer(minLength: 20)
                    modeSwitch
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            .dismissKeyboardOnTap()
        }
        .sheet(isPresented: $showReset) {
            PasswordResetView(initialEmail: trimmedEmail)
        }
    }

    // MARK: pieces

    // Title only. This screen used to carry three separate blocks of explanation —
    // a subtitle, a password note, and a footer — which is more reading than a
    // sign-up form has any right to ask for. Why an account is worth having is
    // already said on the Profile tab, where someone decides to tap through.
    private var heading: some View {
        Text(isCreating ? "Create an account" : "Sign in")
            .font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
            .padding(.horizontal, 6)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Email", text: $email, prompt: Text("you@example.com"))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .fieldBox()

            // `.newPassword` on create and `.password` on sign-in is what lets the
            // keychain offer to save it, and later to fill it. Getting this wrong
            // is why some apps never prompt to save a password.
            SecureField("Password", text: $password, prompt: Text("Password"))
                .textContentType(isCreating ? .newPassword : .password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }
                .fieldBox()

            // The rule, and nothing else. Someone typing a password doesn't need
            // advice about passphrases mid-form.
            if isCreating {
                Text("At least \(PasswordCrypto.minimumPasswordLength) characters")
                    .font(.subline).foregroundStyle(Color.faded)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var submitButton: some View {
        Button { submit() } label: {
            HStack(spacing: 8) {
                if phase == .working { ProgressView().controlSize(.small).tint(Color.paper) }
                Text(isCreating ? "Create account" : "Sign in")
                    .font(.body14.weight(.semibold))
            }
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canSubmit ? Color.ink : Color.faded)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 16)
    }

    // Only on the sign-in side: offering "forgot password" while someone is
    // CREATING one is nonsense.
    @ViewBuilder
    private var forgotPassword: some View {
        if !isCreating {
            Button("Forgot password?") { showReset = true }
                .font(.subline.weight(.semibold)).foregroundStyle(Color.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 6) {
            Text(isCreating ? "Already have an account?" : "New to Tadah?")
                .font(.subline).foregroundStyle(Color.faded)
            Button(isCreating ? "Sign in" : "Create one") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCreating.toggle()
                    phase = .idle          // a stale error from the other mode is confusing
                }
            }
            .font(.subline.weight(.semibold)).foregroundStyle(Color.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // Says which half actually happened, rather than dismissing identically
    // whether or not anything was saved.
    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .idle, .working:
            EmptyView()
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ok)
                Text("Signed in. Your to-dos are backed up.")
                    .font(.subline).foregroundStyle(Color.faded)
            }
            .padding(.top, 12)
        case .failed(let reason):
            Text(reason)
                .font(.subline).foregroundStyle(Color.bad).lineSpacing(2)
                .padding(.top, 12)
        }
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 28))
                    .foregroundStyle(Color.faint)
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.top, 8)
    }

    // MARK: submit

    private func submit() {
        focused = nil
        phase = .working
        Task { await authenticate() }
    }

    private func authenticate() async {
        let address = trimmedEmail.lowercased()
        do {
            let session = isCreating
                ? try await AuthService.register(email: address, password: password, deviceID: Device.id)
                : try await AuthService.logIn(email: address, password: password, deviceID: Device.id)

            // RevenueCat is identified with OUR account id now, not an Apple `sub`
            // — the Worker asks RevenueCat about this same id when it checks the
            // tier, so the two must agree or a paying user gets free-tier limits.
            // PlusStore also carries a subscription bought BEFORE this account
            // existed across to it: buying never needs an account (guideline
            // 5.1.1), so "paid first, signed up later" is a normal order now.
            await plus.identify(as: session.userID)

            // `.email` provider — the enum already had the case waiting.
            account.signIn(Account(userID: session.userID, provider: .email,
                                   name: "", email: address))

            // Reconciliation decides what happens to the to-dos already on this
            // device. Its RESULT decides what we claim: a session is not a backup,
            // so "backed up" waits for a completed round trip.
            switch await sync.afterSignIn(session: session, context: context, account: account) {
            case .backedUp:
                phase = .done
                dismiss()
            case .awaitingReconciliation:
                dismiss()            // RootTabView's prompt takes over
            case .failed:
                phase = .failed(String(localized: "We couldn't finish setting up your account on this phone. Please try again."))
            case .signedInLocally:
                // Signed in, first sync didn't complete — and that is NOT worth a
                // warning HERE. It retries on its own (launch, foreground, next
                // edit) and nothing is lost meanwhile. The banner existed when a
                // profile-cap 409 could block sync indefinitely, which made the
                // delay permanent; with that fixed (see worker.js — storage is no
                // longer tier-gated) this is a transient network hiccup, and
                // telling someone "it doesn't work" about something that fixes
                // itself just teaches them to distrust the app.
                //
                // What this must NOT become is silence about a failure that never
                // resolves — a rejected request or unparseable response fails the
                // same way forever. That case is caught downstream, once it has
                // proved itself permanent: Profile shows a stuck-backup row after
                // three consecutive failures (SyncCoordinator.backupIsStuck).
                dismiss()
            }
        } catch AuthService.AuthError.notConfigured {
            // No Worker configured (simulator dev builds). Nothing to sign into.
            phase = .failed(String(localized: "Accounts aren't available in this build."))
        } catch {
            phase = .failed(message(for: error))
        }
    }

    // The server answers wrong-password and no-such-account IDENTICALLY, on
    // purpose — telling them apart would let anyone test which addresses are
    // registered. So this message covers both, and must not speculate.
    private func message(for error: Error) -> String {
        guard case AuthService.AuthError.server(let code) = error else {
            return String(localized: "We couldn't reach Tadah. Check your connection and try again.")
        }
        switch code {
        case 401: return String(localized: "That email and password don't match an account.")
        case 409 where isCreating: return String(localized: "There's already an account with that email. Try signing in instead.")
        case 409: return String(localized: "This account is already signed in on the maximum number of devices.")
        case 400: return String(localized: "Please check the email and password and try again.")
        case 429: return String(localized: "Too many attempts. Please wait a moment and try again.")
        default:  return String(localized: "Something went wrong. Please try again.")
        }
    }
}

// The bordered box shared by both fields, so they line up exactly.
private extension View {
    func fieldBox() -> some View {
        self
            .font(.body14).foregroundStyle(Color.ink)
            .padding(14)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
    }
}
