# Release 1.1 (build 7) — what's left

Updated 2026-09-16. **Done:** build 7 uploaded; Worker and legal pages deployed;
a real call tested end to end; the demo account `support.tadah@gmail.com` is
verified and has Plus. Everything below is still to do, in order.

---

## 1. App Store Connect — submit 1.1

1. **Add the version.** App Store Connect → Tadah → the **+** next to *iOS App* → **1.1**.
2. **Build.** Select **build 7** (it appears once Apple finishes processing). If it asks about encryption, answer as for 1.0: uses encryption **Yes**, exempt **Yes**.
3. **What's New in This Version** — paste:

   ```
   Tadah can now make the phone call for you.

   When a to-do needs a call — asking why a bill went up, or whether a fee can be removed — Tadah offers to make it. You confirm one short page: who is being called, what will be asked, and what Tadah may agree to. Then Tadah calls, in English, and writes back what was said, what was agreed, and what to do next.

   • The call is in English; the answer comes back in your language
   • Tadah says it is an AI on every call
   • It never gives out card, bank or Social Security numbers, and never agrees to a charge
   • It only calls the number printed on your document, and only after you confirm
   • You are never on the line, and you can close the app while it calls

   Also in this update: you can now verify your email address from the account screen.

   Tadah Calls is part of Tadah Plus and needs a verified email address.
   ```

4. **Subtitle — currently empty on the live page** (the slot shows "Productivity"). Set it under App Information → **Subtitle**, then set the matching **Keywords** on the version page. Pick one row:

   | Subtitle | Keywords |
   |---|---|
   | `Scan mail, know what to do` (26/30) | `bill,letter,document,translate,deadline,reminder,immigrant,checklist,tax,notice,esl,explain,call` (96/100) |
   | `Letters explained. Calls made.` (30/30) | `bill,document,translate,deadline,reminder,immigrant,checklist,tax,notice,esl,forms,scan,mail,phone` (98/100) |

   Apple already searches the name, subtitle and keywords together, so a word in two of them is wasted. The first row swaps `forms` for `call`. The second drops `letter` and `explain` (now in the subtitle) and adds back `scan`, `mail` and `phone`.

5. **Promotional Text** (optional; editable any time without review):

   ```
   New: Tadah can make the phone call for you. It calls in English and tells you what was said and agreed, in your language.
   ```

6. **Screenshots.** Replace the raw 1.0 captures with the polished set at `~/Desktop/Tadah App Store screenshots/` (6.9-inch and 6.5-inch folders; the README there gives the order).
7. **App Privacy** (app level, not the version page) → Edit → add **Contact Info → Phone Number**: Collected · App Functionality · **Linked** to identity · **not** used for tracking → **Publish**. Why: `legal/app-store-privacy-label.md` §2.6.
8. **App Review Information.**
   - Sign-in required: **Yes** — `support.tadah@gmail.com` and its password.
   - Notes — paste after the existing ones:

   ```
   NEW IN 1.1: TADAH CALLS. It places one real phone call to a business, on the user's behalf, through a third-party calling provider (CALL-E, AIRUDDER Pte Ltd). It requires Tadah Plus and a verified email address, and never dials without an explicit confirmation screen showing the business, the number, and the question.

   To test it with the demo account (already Plus and verified):
   1. Sign in at Profile.
   2. Add > Scan, and scan any bill or letter that prints a customer-service number. ("Upload a photo" also works.)
   3. On the Review screen, the card under the action steps reads "Tadah can make this call". Tap "Yes, call for me".
   4. On "Before Tadah calls", tap Change and enter a number you control, so the call reaches you rather than a business. Tap Call now.
   5. Answer it. The agent states it is an AI assistant calling on the account holder's behalf. The card then shows what was said and what was agreed.

   Safety: card, bank and Social Security numbers are refused before a call is placed; emergency, premium-rate and service numbers cannot be dialled; one call at a time, five a month per account; nothing retries automatically. What was said is kept as text for 30 days; no audio is recorded.

   Email verification is at Profile > name > EMAIL > Verify (a six-digit code by email).
   ```

9. **Version Release:** choose **Automatically release this version**, so 1.1 is live before hackathon judging starts (Sep 29, 10 pm New York).
10. **Add for Review → Submit for Review.**

---

## 2. While it's in review

- **Plus on the demo account must outlast judging.** RevenueCat → Customers → `548da859-eaa6-490a-9374-7d1d0e3625b2` → check the "Tadah Pro" grant ends **after Oct 13**; extend it if not.
- **CALL-E balance.** Leave room for Apple's reviewer and the judges: the demo account can place up to 5 calls in September and 5 more in October (about $1.56 each, roughly $16).
- **If Apple rejects,** reply in App Review with the notes above. The usual sticking point for a feature like this is a reviewer who can't place a call, which the demo account covers.

---

## 3. After approval (before Sep 29)

- Confirm the store shows 1.1:
  `curl -s "https://itunes.apple.com/lookup?bundleId=com.ruiqiwang.cuevi&country=us" | grep -o '"version":"[^"]*"'`
- Install from the App Store (not TestFlight), sign in as the demo account, place one call to your own phone, then **sign out**.

## 4. After judging ends (Oct 13)

- RevenueCat: remove the "Tadah Pro" grant from the demo account.
- Change the demo account's password.

---

## Later — not needed for 1.1

- **Paid call packs** for Plus users past 5 a month. Needs consumable products in App Store Connect and RevenueCat, a credit ledger in the Worker, and a purchase screen. Break-even is about $1.85–$2.25 a call after Apple's cut.
- **Harden the Worker's CALL-E requests** with `redirect: "error"`, as CALL-E's maintainer did in the hackathon PR (commit 59bf68e).
