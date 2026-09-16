# Release 1.1 (build 7) — Tadah Calls

Written 2026-09-15. 1.0 (build 6) has been live since 2026-09-10, so this ships
as **1.1**, build **7**.

## Before the build goes anywhere

Two deploys have to happen first, and only you can run them (the assistant is
blocked from production writes):

```bash
# 1. The Worker: email verification routes + the language on the call result
cd "/Users/rachelwang/Project!/notie_life_helper_app/Tadah/cloudflare-worker"
export PATH="/usr/local/opt/node@22/bin:$PATH"
npx wrangler deploy

# 2. The legal pages: the privacy policy and terms now describe calls.
#    Run from cloudflare-worker (where wrangler is installed). The live site is
#    the tadah-legal project, NOT cuevi-legal.
npx wrangler pages deploy ../../docs --project-name tadah-legal --branch main
```

Check afterwards: <https://tadah-legal.pages.dev/privacy> contains "When you ask
Tadah to make a phone call".

## What's new (App Store)

```
Tadah can now make the phone call for you.

When a to-do needs a call — asking why a bill went up, or whether a fee can be removed — Tadah offers to make it. You confirm one short page: who is being called, what will be asked, and what Tadah may agree to. Then Tadah calls, in English, and writes back what was said, what was agreed, and what to do next.

• The call is in English; the answer comes back in your language
• Tadah says it is an AI on every call
• It never gives out card, bank or Social Security numbers, and never agrees to a charge
• It only calls the number printed on your document, and only after you confirm
• You are never on the line, and you can close the app while it calls

Also in this update: you can now verify your email address from the account screen.

Tadah Calls needs Tadah Plus and a verified email address.
```

## App Review notes (add to the existing notes)

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

## App Privacy label

One change in App Store Connect: declare **Contact Info → Phone Number**
(Collected · App Functionality · Linked · not tracking). Details and why are in
`legal/app-store-privacy-label.md` §2.6. `PrivacyInfo.xcprivacy` already matches.

## Screenshots

1.1 is a new version, so screenshots can finally be replaced: the polished set is
at `~/Desktop/Tadah App Store screenshots/` with its own README for the order.

## After it is approved

- The demo account `support.tadah@gmail.com` needs Plus in RevenueCat (grant the
  "Tadah Pro" entitlement for 2-3 months) and its email verified — which it can
  now do itself, in the app, from the account screen.
- Top up CALL-E credits: a real call has cost about $1.56, and the cap is 5 per
  account per month.
