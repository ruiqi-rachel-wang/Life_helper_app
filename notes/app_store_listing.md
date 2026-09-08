# App Store listing — paste-ready copy

> Written 2026-08-24 for version 1.0. Character limits are Apple's and are
> checked in the counts below. Nothing here promises a specific usage number —
> the App Store description is a commitment to the customer, and the limits live
> in code (see `how_tadah_is_built.md` → Limits).

---

## Name (30 max)

```
Tadah: Paperwork, Handled
```
*(25 — already set in App Store Connect.)*

## Subtitle (30 max)

```
Scan mail, know what to do
```
*(26.)* Alternatives if you want a different angle:
- `Understand any letter or bill` (29)
- `Turn paperwork into to-dos` (26)

## Promotional text (170 max — editable without a review)

```
Scan a letter, bill, or notice and Tadah explains what it is, why you got it, and what to do — in English, Spanish, or Chinese, with reminders so nothing is missed.
```
*(164.)* This field can be changed any time without submitting an update, so use
it for seasonal notes later ("Tax season: scan your notices…").

## Description (4000 max)

```
Official mail is written for the people who send it, not for the people who get it.

Tadah reads a letter, bill, or notice and tells you three things: what it is, why you got it, and what to do next — in plain words, in English, Spanish, or Simplified Chinese.

SCAN ANYTHING THAT ARRIVES
Point your camera at a bill, a ticket, a school form, an insurance letter, a medical notice, a court or immigration document. Tadah pulls out the amount, the deadline, and the account or reference number you will actually need, and writes a short explanation of what triggered it.

A CHECKLIST, NOT A WALL OF TEXT
Every document becomes a short list of actions in order. Tap any step to see how and where to do it — the exact page to pay on, what to bring, and what to say on the phone.

DEADLINES THAT REMIND YOU
Due dates become reminders. Tadah handles the awkward cases: a deadline written as "within 90 days", a year the document never printed, an appointment in another timezone.

GUIDES FOR THE THINGS NOBODY EXPLAINS
Step-by-step help for moving, renting, a new job, a car, health coverage, and more — written for people navigating a system for the first time, with links to official .gov pages rather than someone's blog.

FOR YOUR WHOLE HOUSEHOLD
Keep a separate space for each person — a parent's medical letters, a child's school forms — and see all of it in one list, marked by who it belongs to.

BUILT TO BE PRIVATE
Your documents stay on your phone. When you scan, only the recognized text is sent for explanation — never the photo, and never your name or account. Usage statistics are opt-in: Tadah asks once, and sends nothing unless you say yes.

TADAH PLUS
An optional subscription that raises the scan and to-do limits, gives each person their own space, and keeps everything in sync across your devices. The core of Tadah is free and stays free — no account required to scan, explain, or set a reminder.

Tadah organizes and explains documents. It is not legal, tax, medical, or immigration advice.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://tadah-legal.pages.dev/privacy
```

⚠️ **The last two lines are REQUIRED, not decoration.** Build 5 was rejected on
2026-09-03 under **3.1.2 Business: Payments - Subscriptions**:

> The submission offers auto-renewable subscriptions but does not include a
> functional link to the Terms of Use (EULA) in the app metadata that appears on
> the app's App Store product page.

Apple's message names exactly two compliant routes:
  • standard Apple EULA  → link it in the DESCRIPTION  ← what we do
  • a CUSTOM EULA        → upload the text in App Store Connect (App Information
                           → License Agreement). Merely linking your own terms
                           from the description is NOT one of the two routes.

Use APPLE'S url, not tadah-legal.pages.dev/terms. Two reasons: it is the link
Apple's own rejection message points at, and our Terms of Service mentions
"subscription" zero times — §10 defers to Apple's EULA anyway, so Apple's is the
document that actually covers renewal, cancellation and refunds.

The app's own paywall still links to tadah-legal.pages.dev/terms. That is fine and
separate: this is about the App Store product page. Do not remove these lines.
*(~1,950 — well inside the limit, and the last line matters: it is the same
disclaimer the app shows, and reviewers look for it on an app in these categories.)*

## Keywords (100 max, comma-separated, no spaces after commas)

```
bill,letter,document,translate,deadline,reminder,immigrant,checklist,tax,notice,esl,forms,explain
```
*(97.)* ⚠️ `mail` and `scan` were removed on 2026-09-02: both already appear
in the SUBTITLE ("Scan mail, know what to do"), which Apple indexes, so they were
10 wasted characters by this file's own rule. `explain` replaces them — it is the
app's core verb and appears in neither the name nor the subtitle.

Rules worth knowing: do NOT repeat words already in the name or
subtitle (Apple indexes those anyway — "tadah", "paperwork", "handled" would be
wasted), do not use competitor names, singular covers plural.

## Localized listings — the biggest findability gap

Tadah ships **English, Spanish and Simplified Chinese** (`en.lproj`, `es.lproj`,
`zh-Hans.lproj` are all in the bundle), so App Store Connect will offer a separate
listing for each. Right now only English is written, which means a Spanish or
Chinese speaker searching in their own language — exactly who this app is for —
will not find it, and if they do, they read an English store page for an app that
speaks their language.

Each locale gets its own **name, subtitle, keywords, description and screenshots**,
and the keyword field is indexed PER LOCALE. This is more valuable than any wording
change on the English page: it is the difference between being findable and not.

- 简体中文 (zh-Hans) and Español (es): add both under App Store Connect →
  the version → the language selector at the top of the page.
- Do NOT machine-translate the keywords. Search terms are not translations —
  someone looking for help with a government letter in Chinese does not type the
  translation of "notice". The description can be translated faithfully; the
  keywords need to be written fresh in each language.
- The app's own strings are already professionally translated in
  `Localizable.xcstrings` — reuse that voice so the store page and the app agree.

Not a launch blocker: you can ship English-only and add locales later without a
new build, since listing metadata is edited independently of the binary.

## Support URL

```
https://tadah-legal.pages.dev/
```
The site root is already titled "Tadah — Support & Legal" and carries the
support address plus privacy-request instructions. Nothing to build.

## Marketing URL (optional)

Leave blank. Only fill it if there is a real product page — the support page is
not one, and a thin page is worse than none.

## Privacy Policy URL

```
https://tadah-legal.pages.dev/privacy
```

---

## The questionnaires — the answers for this app

### Age rating
Answer **None** to every content question (no violence, sexual content, profanity,
gambling, drugs, horror, contests). Tadah has no user-generated content shown to
other users and no web browser. Expect **4+**.

⚠️ There is a question about **unrestricted web access** — answer **No**. Tadah
opens official links in Safari, which is not an in-app browser.

### Export compliance
- Does your app use encryption? → **Yes** (HTTPS counts)
- Does it qualify for exemption? → **Yes**
- The exemption: only standard encryption via HTTPS/TLS provided by the operating
  system, no proprietary or custom cryptography.

This is the ordinary answer for an app that just calls an API over HTTPS. It
saves you from filing a CCATS/ERN.

### Content rights
"Does your app contain, show, or access third-party content?" → **No**.
The guides are written by you, and linking out to a .gov page is not showing
third-party content inside the app.

### Category
- Primary: **Productivity**
- Secondary: **Utilities**

Productivity is the honest fit and a less brutal chart than Utilities. Consider
**Reference** as the secondary instead if you want the guides to be the hook.

---

## App Review Information

- **Sign-in required?** → **Yes**, and supply a demo account. Core scanning works
  without one, but sync, family profiles, and account deletion cannot be reached
  otherwise, and "we could not test it" is a rejection.
- **Notes** — paste:

```
Tadah explains letters, bills, and official notices and turns them into to-dos with reminders.

MOST FEATURES NEED NO ACCOUNT. To test the core app: open the Add tab, tap Scan, and point the camera at any bill or letter (or use "Upload a photo" with a screenshot). Tadah returns an explanation and a checklist.

The demo account above is needed only for: cross-device sync, family profiles, and account deletion (Profile > name > Delete account).

TADAH PLUS is an optional auto-renewing subscription reached at Profile > UPGRADE. Free accounts get 20 to-dos and 20 AI scans/guides a day, up to 50 per rolling 30 days, on one device at a time. Plus raises these to 100 to-dos per profile and 60 a day / 300 per 30 days, and allows multiple devices.

Tadah organizes and explains documents. It does not give legal, tax, medical, or immigration advice, and the app states this.
```
