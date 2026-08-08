# App Store Privacy "Nutrition Label" — answers for Tadah

> Fill this into **App Store Connect → your app → App Privacy**. These answers
> match how Tadah works today: document text sent to OpenAI for processing;
> anonymous, non-identifying first-party usage stats; **an optional Sign in with
> Apple account that backs up your items to our backend and syncs them between
> devices**; and **Tadah Plus subscriptions billed by Apple via RevenueCat**.
> Re-check before each submission.
>
> **⚠️ Updated 2026-08-07 for accounts + sync + subscriptions.** The previous
> version said "no accounts" and declared everything as *not linked to identity*.
> That is no longer true for signed-in users — see §2.5. Submitting the old label
> would misdeclare the app.

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
declare each of these as **Collected · purpose: App Functionality · NOT linked to
identity · NOT used for tracking**:

- **Other User Content** — the recognized text of scanned documents.
- **Contact Info** — documents often show names, addresses, phone numbers.
- **Health & Fitness** — e.g. medical bills or appointment notes.
- **Financial Info** — e.g. bank, tax, or billing statements.
- **Sensitive Info** — e.g. immigration or legal documents.

> Why declare so much: Apple judges collection by the data's *nature*, not the field you
> ask for. OCR text can include all of the above and it **leaves the device** (OpenAI may
> retain it ~30 days), so over-declaring is the safe, accurate choice. A privacy
> professional can narrow this later if appropriate.

### Also collected — anonymous usage statistics (first-party)
Tadah sends anonymous, non-identifying usage events to our own backend (a Cloudflare
database) to measure whether the app helps. Declare:

- **Usage Data → Product Interaction** — Collected · purpose **Analytics** + App
  Functionality · **NOT linked** to identity · **NOT used for tracking**. (Events like
  "item added" / "item completed," with a source and an on-time flag.)
- **Identifiers → User ID** — Collected · purpose Analytics + App Functionality · **NOT
  linked** to identity · **NOT used for tracking**. (A random per-install UUID generated
  on the device — not your Apple ID, account, or the advertising identifier, and never
  linked to who you are.)

Both are **first-party only**: no third-party analytics SDK, no advertising, no data
brokers, no cross-app tracking. The user can turn this off in **Profile → Privacy**.

### 2.5 Accounts, sync, and subscriptions — **linked to identity**

Signing in is optional, but when a user DOES sign in, their items are stored on our
backend under a Tadah-specific Apple user identifier. For those users the data is
**Linked to You**, and the label must say so. Declare:

- **Identifiers → User ID** — Collected · purpose **App Functionality** · **LINKED to
  identity** · not used for tracking. (The Sign in with Apple `sub` — a Tadah-specific
  identifier. Sent to our backend to store the account's items, and to RevenueCat to
  attach the subscription.)
- **Other User Content** — also declare a **LINKED** instance for signed-in backup:
  the item's title, amount, due date, notes, checklist steps, and any reference numbers
  the user saves are stored on our backend under that User ID. Same for the
  **Contact Info / Financial Info / Health / Sensitive Info** categories above, since an
  item's content can contain any of them.
- **Purchases** — Collected · purpose App Functionality · **LINKED** to identity · not
  used for tracking. (Tadah Plus subscription status, via Apple's App Store and
  RevenueCat.)

> How to express this in App Store Connect: a data type can be declared twice — once
> **not linked** (the anonymous, signed-out paths) and once **linked** (the signed-in
> account). If the form makes that awkward, declare the **linked** version — it is the
> stronger, safer statement.
>
> Name and email from Sign in with Apple are stored **on the device only** and are never
> sent to our backend, so they are not declared as collected. If that ever changes,
> declare **Contact Info → Name / Email Address**, linked.

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

## 3. Tracking
**"Does this app track users?"** → **No.** (No cross-app/cross-site tracking, no
ad identifiers, no data shared with data brokers.)

## 4. Privacy Policy URL (required field)
Use the live, free, public Cloudflare Pages URL:
`https://cuevi-legal.pages.dev/privacy.html`
(Verify it loads in a **private/incognito** browser window — i.e. anonymously — before
you submit. Terms: `https://cuevi-legal.pages.dev/terms.html`.)

---

## When you change the app, revisit this:
- **Already added (2026-06-23): our own anonymous usage stats** → declared **Usage
  Data** (Product Interaction) + **Identifiers** (User ID), Analytics purpose, Not
  linked / No tracking. If you add a **third-party** analytics SDK later, re-confirm its
  data types and whether it does any tracking.
- **Add accounts / sign-in** → declare **Contact Info** and **Identifiers**, and
  many items may become **Linked to the user**.
- **Add cloud sync** → revisit retention and linkage answers.
