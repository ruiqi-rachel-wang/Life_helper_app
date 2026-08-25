# Tadah Plus — every field App Store Connect + RevenueCat will ask for

> Written 2026-08-07. Paste-ready values for all three languages (all verified
> against Apple's character limits). Product IDs are **permanent** — they can
> never be changed or reused, even after deletion.

---

## A. App Store Connect → Subscriptions

### A1. Subscription Group
Already created: **Tadah Plus** (group id 22294269).

**Group Localization** — one per language. This is the name users see in
Settings ▸ Subscriptions when managing it.

| Language | Subscription Group Display Name |
|---|---|
| English (U.S.) | `Tadah Plus` |
| Chinese (Simplified) | `Tadah Plus` |
| Spanish (Mexico) | `Tadah Plus` |

*(Keeping the brand name untranslated is deliberate — it's the product's name.)*

### A2. The two products

| | Monthly | Yearly |
|---|---|---|
| Reference Name *(internal)* | `Tadah Plus Monthly` | `Tadah Plus Yearly` |
| Product ID *(permanent)* | `com.ruiqiwang.cuevi.plus.monthly` | `com.ruiqiwang.cuevi.plus.yearly` |
| Duration | 1 month | 1 year |

### A3. Localization — per product, per language

**Display Name** ≤35 chars · **Description** ≤55 chars. Both are shown to users.

**MONTHLY**

| Language | Display Name | Description |
|---|---|---|
| English (U.S.) | `Tadah Plus (Monthly)` | `More scans, more to-dos, and all your devices.` |
| Chinese (Simplified) | `Tadah Plus 按月订阅` | `更多扫描与待办，并可在多台设备上同步。` |
| Spanish (Mexico) | `Tadah Plus (Mensual)` | `Más escaneos, más tareas y todos tus dispositivos.` |

**YEARLY**

| Language | Display Name | Description |
|---|---|---|
| English (U.S.) | `Tadah Plus (Yearly)` | `A year of Tadah Plus. Cancel anytime.` |
| Chinese (Simplified) | `Tadah Plus 按年订阅` | `按年订阅更划算，可随时取消。` |
| Spanish (Mexico) | `Tadah Plus (Anual)` | `Un año de Tadah Plus. Cancela cuando quieras.` |

> ⚠️ Don't promise a specific number in the description (e.g. "60 scans a day").
> The limits live in code and can change; Apple treats the description as a
> commitment to the customer.

### A4. Subscription Prices

**DECIDED 2026-08-13: $6.99 monthly / $59.99 yearly**, set by Rachel in App Store
Connect. `Tadah.storekit` mirrors these so the Simulator paywall shows the real
numbers — if the App Store Connect price ever changes, change that file too or
the local preview quietly lies.

Yearly works out at ~28% off — about 3.4 months free against the monthly rate,
a deeper discount than the ~2-months-free anchor the options below assumed.

<details><summary>Options originally offered (kept for history)</summary>

| | Monthly | Yearly | Note |
|---|---|---|---|
| Lower-friction | $2.99 | $24.99 | Easier first yes for an ESL/immigrant audience |
| Standard | $3.99 | $34.99 | Matches what you priced JobDrop Pro at |

</details>

Set the **US price**; App Store Connect auto-fills every other territory (you can
override). Availability: leave **all territories** on unless you have a reason.

### A5. Introductory Offer (optional but recommended)
Subscription ▸ **Introductory Offers** ▸ create → **Free Trial, 1 week** (or 3
days) for New Subscribers. This is the single biggest conversion lever, and
RevenueCat's paywall templates surface it automatically.

### A6. Review Information (required before "Add for Review")
- **Screenshot** — a 1284×2778 (or any iPhone size) capture of the **paywall as
  it appears in the app**. You must run build 4, open Profile ▸ UPGRADE, and
  screenshot it. Apple rejects placeholder images here.
- **Review Notes** — paste:
  > Tadah Plus is an optional subscription. Free accounts can save up to 20
  > to-dos and run 20 AI scans/guides a day, up to 50 per rolling 30 days, on one
  > device at a time. Tadah Plus raises these to 100 to-dos per profile and 60 a
  > day / 300 per 30 days, and allows multiple devices. No account or purchase is
  > required to use the app's core features. To test: open the Profile tab and
  > tap UPGRADE.

### A7. Family Sharing — leave OFF for now
⚠️ **Once enabled it cannot be turned off.** Tadah's own "family" feature (adding
a parent's profile inside the app) is *not* Apple Family Sharing, and turning
Apple's on means one purchase covers up to 6 Apple IDs — which would undercut
per-account pricing. Revisit deliberately later.

---

## B. RevenueCat

1. **Product catalog ▸ Products** → import/add both product IDs above (select the
   Tadah app). RevenueCat pulls them from App Store Connect once they exist.
2. **Entitlements** → open **`Tadah Pro`** → attach **both** products.
   ⚠️ The identifier must stay exactly `Tadah Pro` — that literal is hardcoded in
   `Model/PlusStore.swift` and in `cloudflare-worker/worker.js`
   (`PLUS_ENTITLEMENT`). If it drifts, `isPlus` is always false and Plus users get
   the free one-device limit.
3. **Offerings** → create one (e.g. `default`) → add both products as **Packages**
   (Monthly / Annual) → mark the offering **Current**. The app shows nothing
   without a Current offering.
4. **Paywalls** → attach a paywall to that offering and add localizations for
   **en / zh-Hans / es** — `PaywallView` passes the user's picked language, so
   missing localizations fall back to English.
5. **API keys** → copy the **public Apple key** (`appl_…`) and replace the
   `test_…` key in `App/TadahApp.swift`.
   *(Also needed server-side, already done: `REVENUECAT_SECRET` — the v1 secret key.)*

---

## C. Then, in this order

1. Products reach **"Ready to Submit"** in App Store Connect (needs price +
   localization + review screenshot).
2. Swap the app to the `appl_…` key, rebuild.
3. Test a purchase with a **Sandbox** Apple ID
   (Settings ▸ Developer ▸ Sandbox Account on the device — never your real ID).
4. Confirm in the app: after purchase, Profile shows **Tadah Plus**, the task cap
   goes to 100, and a second device can stay signed in.
5. Deploy the Worker so the server agrees:
   `cd Tadah/cloudflare-worker && npx wrangler deploy`
6. Archive and upload build 4.

> Subscriptions are reviewed **with your app build**, not separately — they go
> out with build 4's submission. They stay in "Waiting for Review" until then.
