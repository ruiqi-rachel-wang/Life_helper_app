# App Store Privacy "Nutrition Label" — answers for Cuevi

> Fill this into **App Store Connect → your app → App Privacy**. These answers
> match how Cuevi works today (local-first, document text sent to OpenAI for
> processing, no accounts, no analytics). Re-check before each submission — if you
> later add analytics (e.g. TelemetryDeck) or accounts, you MUST update the label.

## Key nuance (don't get this wrong)
Apple counts data as **"collected"** if it **leaves the device**, even if you don't
store it on a server. Cuevi sends document **text** to OpenAI to generate results,
so you **do collect "User Content."** Answering "we don't collect any data" would
be **inaccurate** and can get the app rejected. Answer "Yes, we collect data" and
declare User Content as below.

---

## 1. "Do you or your third-party partners collect data from this app?"
**Yes.**

## 2. Data types to declare

### User Content
- **Photos or Videos** — *Collected.*
  - Linked to the user's identity? **No** (there is no account/identifier).
  - Used for tracking? **No.**
  - Purpose: **App Functionality.**
- **Other User Content** (the recognized text of the documents) — *Collected.*
  - Linked to identity? **No.**
  - Used for tracking? **No.**
  - Purpose: **App Functionality.**

> Note: the photo is stored on-device; what is transmitted to OpenAI is the
> recognized **text**, which OpenAI may retain ~30 days. Declaring Photos + Other
> User Content under App Functionality is the baseline.

> ⚠️ **Needs a closer look before you submit.** A scanned document's text can contain
> **Financial Info** (bank/tax statements), **Health & Fitness** (medical bills/notes),
> **Contact Info** (names, addresses), and other **Sensitive Info** (e.g. immigration),
> and that text is sent **off-device** to OpenAI. Apple asks you to declare data your
> app *collects* by the data's nature, not just the field you ask for — so "Other User
> Content" alone may understate it. Before submitting, decide (ideally with Apple's
> data-type definitions or a professional) whether to ALSO declare **Financial Info**,
> **Health & Fitness**, **Contact Info**, and/or **Sensitive Info** — each as
> *App Functionality, Not linked, No tracking*. Being over-inclusive here is safer than
> under-declaring.

### Everything else → **Not collected** (BUT see the warning above re: scanned content)
Unless/until you add them, answer **No / Not Collected** for:
- Contact Info (name, email, phone, address) — *unless the scan warning above applies*
- Health & Fitness — *unless the scan warning above applies*
- Financial Info (you do not link banks or process payments) — *but scans can contain it; see above*
- Location
- Identifiers (no user ID, device ID, or advertising ID)
- Usage Data (no analytics yet)
- Diagnostics (no crash/analytics SDK yet)
- Purchases, Browsing History, Search History, Sensitive Info, Contacts

## 3. Tracking
**"Does this app track users?"** → **No.** (No cross-app/cross-site tracking, no
ad identifiers, no data shared with data brokers.)

## 4. Privacy Policy URL (required field)
Enter your hosted Privacy Policy URL (see `legal/README.md` for hosting). Until you
enable a nicer page, the GitHub-hosted Markdown URL is acceptable:
`https://github.com/ruiqi-rachel-wang/Life_helper_app/blob/main/legal/privacy-policy.md`

---

## When you change the app, revisit this:
- **Add TelemetryDeck / any analytics** → declare **Diagnostics** and/or **Usage
  Data** (Analytics purpose), still "Not linked" / "No tracking" if it stays PII-free.
- **Add accounts / sign-in** → declare **Contact Info** and **Identifiers**, and
  many items may become **Linked to the user**.
- **Add cloud sync** → revisit retention and linkage answers.
