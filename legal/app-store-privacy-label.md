# App Store Privacy "Nutrition Label" — answers for Tadah

> Fill this into **App Store Connect → your app → App Privacy**. These answers
> match how Tadah works today: document text sent to OpenAI for processing;
> anonymous, non-identifying first-party usage stats; **an optional EMAIL +
> PASSWORD account that backs up your items to our backend and syncs them between
> devices**; and **Tadah Plus subscriptions billed by Apple via RevenueCat**.
> Re-check before each submission.
>
> **⚠️ Corrected 2026-09-07:** §2 now says LINKED, matching
> `Tadah/PrivacyInfo.xcprivacy`. See the warning in §2.
>
> **⚠️ Rewritten 2026-08-15 for email + password.** Sign in with Apple is gone
> (it authenticated the device's Apple ID, so a family member could never reach a
> shared account). Earlier revisions of this file argued with themselves — the
> header described Apple while a later note said it had been removed — so the
> Apple text is now deleted rather than annotated. §2.5 is the authoritative
> section.

## Key nuance (don't get this wrong)
Apple counts data as **"collected"** if it **leaves the device**, even if you don't
store it on a server. Tadah sends document **text** to OpenAI to generate results,
so you **do collect "User Content."** Answering "we don't collect any data" would
be **inaccurate** and can get the app rejected. Answer "Yes, we collect data" and
declare User Content as below.

---

## 1. "Do you or your third-party partners collect data from this app?"
**Yes.**

## 2. Data types to declare

**Recommended declaration** (accurate + deliberately over-inclusive). Because a scanned
document's recognized text is sent off-device to OpenAI and can contain almost anything,
declare each of these as **Collected · purpose: App Functionality · LINKED to
identity · NOT used for tracking**:

- **Other User Content** — the recognized text of scanned documents.
- **Contact Info** — documents often show names, addresses, phone numbers.
- **Health & Fitness** — e.g. medical bills or appointment notes.
- **Financial Info** — e.g. bank, tax, or billing statements.
- **Sensitive Info** — e.g. immigration or legal documents.

> ⚠️ **These say LINKED, corrected 2026-09-07.** This section used to say "NOT
> linked", and §2.5 below then said to declare a linked instance as well — so the
> file contradicted itself, and anyone filling in the form from the top answered
> "not linked" and stopped. **`Tadah/PrivacyInfo.xcprivacy` declares all five as
> `Linked = true`**, Apple cross-checks the label against the shipped manifest,
> and that mismatch is the release checklist's #1 ranked rejection risk. The
> manifest is right: once a user signs in, the saved item is stored under their
> account, which is Apple's definition of linked. App Store Connect takes one
> answer per data type, so the linked answer is the only honest one.

> Why declare so much: Apple judges collection by the data's *nature*, not the field you
> ask for. OCR text can include all of the above and it **leaves the device** (OpenAI may
> retain it ~30 days), so over-declaring is the safe, accurate choice. A privacy
> professional can narrow this later if appropriate.

### Also collected — pseudonymous usage statistics (first-party, OPT-IN)
Tadah can send usage events to our own backend (a Cloudflare database) to measure
whether the app helps. **Opt-in since 2026-08-17** — nothing is sent unless the user
switches on Profile → Privacy → Share usage data. Declare it anyway: the label
describes what the app *can* collect, not what a given user has enabled.

Called **pseudonymous**, not anonymous: every event carries a random identifier that is
stable for one installation, so events from one install can be seen as belonging
together even though we cannot tell who that is.

- **Usage Data → Product Interaction** — Collected · purpose **Analytics** + App
  Functionality · **NOT linked** to identity · **NOT used for tracking**. (Events like
  "item added" / "item completed," with a source and an on-time flag.)
- **Identifiers → Device ID** — Collected · purpose Analytics + App Functionality ·
  **LINKED** to identity · **NOT used for tracking**.

  ⚠️ **This was previously declared as User ID, and then as an unlinked Device ID.
  Both were wrong.** Apple defines an installation- or device-level identifier as
  **Device ID**; **User ID** means an identifier for the *person*.

  There are **two** device identifiers, and they differ on exactly this question:

  | | What it is | Linked? |
  |---|---|---|
  | `Install.id` | Rides with usage events | **No** — never joined to an account, and deliberately a different random value from the one below so that it can't be |
  | `Device.id` | Sent at sign-in, stored in the session row beside the account id (the free "one device at a time" rule has to count devices) | **Yes, by design** |

  Answer **linked** in App Store Connect. It is the conservative merge: Apple treats
  data associated through an account as linked, the form takes one answer per data type,
  and answering "not linked" because the analytics id qualifies would under-declare the
  session id. Under-declaring is what gets an app rejected; over-declaring costs only a
  less flattering label.

  **NOT tracking** either way — neither id leaves our own backend and neither is ever
  combined with data from other companies.

- **Identifiers → User ID** — also Collected, but for the ACCOUNT (see the account
  section): your Tadah user id is a genuine user identifier and it *is* linked to you.

Both are **first-party only**: no third-party analytics SDK, no advertising, no data
brokers, no cross-app tracking. The user can turn this off in **Profile → Privacy**.

### 2.5 Accounts, sync, and subscriptions — **linked to identity**

Signing in is optional, but when a user DOES sign in, their items are stored on our
backend under an account identified by their **email address**. For those users the
data is **Linked to You**, and the label must say so. Declare:

- **Contact Info → Email Address** — Collected · purpose **App Functionality** ·
  **LINKED to identity** · not used for tracking. (Identifies the account and
  receives password-reset codes. Stored on our backend, and sent to Resend to
  deliver those codes.)
- **Identifiers → User ID** — Collected · purpose **App Functionality** · **LINKED to
  identity** · not used for tracking. (Our own account id. Sent to RevenueCat to
  attach the subscription.)

> **Passwords are NOT collected.** The phone derives an unreadable verifier and the
> raw password never leaves the device, so there is nothing to declare for it under
> Contact Info or Sensitive Info.
- **Other User Content** — already declared LINKED in §2 above, for this reason:
  the item's title, amount, due date, notes, checklist steps, and any reference numbers
  the user saves are stored on our backend under that User ID. Same for the
  **Contact Info / Financial Info / Health / Sensitive Info** categories above, since an
  item's content can contain any of them.
- **Purchases** — Collected · purpose App Functionality · **LINKED** to identity · not
  used for tracking. (Tadah Plus subscription status, via Apple's App Store and
  RevenueCat.)

> How to express this in App Store Connect: answer **linked** for each of these
> types. The form takes one answer per data type, the shipped privacy manifest
> says linked, and the two must agree. Do not try to split a type into a linked
> and an unlinked instance — that is what made this file contradict itself.
>
**Family profiles (added 2026-08-08).** Tadah Plus lets a user add profiles for family
members. Each profile stores **a name they type and a colour** — nothing else, no contact
details — but that name is **another person's name**, and it is sent to our backend.
Declare it under the **Contact Info → Name** row above (Collected · App Functionality ·
**Linked** · not used for tracking); the to-dos filed under a profile are already covered
by the User Content rows.

> Worth being precise with Apple here: these are labels inside one account, not user
> accounts. The named person gets no login, is never contacted by us, and we hold no
> way to reach them. That's the difference between this and a contact-sharing feature.

### NOT collected
- **Photos or Videos** — the photo is read on-device (OCR) and **is not uploaded**,
  including for signed-in accounts (photos are excluded from sync). So Photos are
  **Not Collected**.
- **Location, Diagnostics, Browsing/Search History, Contacts** — none collected (no
  third-party analytics, no ad IDs).

### 2.6 Calls (Tadah Plus) — added 2026-09-15

When someone asks Tadah to phone a business, these leave the device: the **phone
number** printed on their document (or the one they corrected it to), the
**question they approved**, the **name on their profile** (which is read aloud on
the call), and — only if they switch it on — that document's **reference number**.
A written **transcript** comes back and is kept 30 days.

What to change in App Store Connect:

- **Contact Info → Phone Number** — declare it now: **Collected · App Functionality
  · LINKED to identity · NOT used for tracking**. It is usually a business's
  number, but it is read off the user's document and sent to a third party, so
  declare it rather than argue about whose number it is.
  `Tadah/PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypePhoneNumber`
  to match.
- **Other User Content** — already declared; it now also covers the call's
  question, its written result, and the transcript.
- **Name** — already declared; the profile name is spoken on the call.
- Nothing else changes: no new purposes, and still **no tracking**.

The call is placed by **CALL-E (AIRUDDER Pte Ltd, Singapore)**, so this data is
processed outside the US. Apple's label doesn't ask where; the privacy policy says
so, under "When you ask Tadah to make a phone call".

---

## 3. Tracking
**"Does this app track users?"** → **No.** (No cross-app/cross-site tracking, no
ad identifiers, no data shared with data brokers.)

## 4. Privacy Policy URL (required field)
Use the live, free, public Cloudflare Pages URL:
`https://tadah-legal.pages.dev/privacy`
(Verify it loads in a **private/incognito** browser window — i.e. anonymously — before
you submit. Terms: `https://tadah-legal.pages.dev/terms`.)

> Use the EXTENSIONLESS form, matching the release checklist. Checked 2026-09-02:
> `/privacy` and `/terms` return 200, while `/privacy.html` and `/terms.html`
> return a 308 redirect. Both reach the page, but there is no reason to hand
> Apple a URL that redirects.

---

## When you change the app, revisit this:
- **Already added (2026-06-23): our own anonymous usage stats** → declared **Usage
  Data** (Product Interaction) + **Identifiers** (User ID), Analytics purpose, Not
  linked / No tracking. If you add a **third-party** analytics SDK later, re-confirm its
  data types and whether it does any tracking.
- **Add accounts / sign-in** → declare **Contact Info** and **Identifiers**, and
  many items may become **Linked to the user**.
- **Add cloud sync** → revisit retention and linkage answers.
