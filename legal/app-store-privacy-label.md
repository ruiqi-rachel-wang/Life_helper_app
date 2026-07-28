# App Store Privacy "Nutrition Label" — answers for Tadah

> Fill this into **App Store Connect → your app → App Privacy**. These answers
> match how Tadah works today (local-first; document text sent to OpenAI for
> processing; no accounts; plus anonymous, non-identifying first-party usage stats).
> Re-check before each submission — if you later add accounts or a third-party
> analytics SDK, you MUST update the label.

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

### NOT collected
- **Photos or Videos** — the photo is read on-device (OCR) and **stays on the device**;
  only the recognized *text* is sent out. So Photos are **Not Collected**.
- **Location, Diagnostics, Purchases, Browsing/Search History, Contacts** — none
  collected (no third-party analytics, no accounts, no ad IDs).

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
