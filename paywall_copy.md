# Tadah Plus paywall — copy to paste into RevenueCat

> Written 2026-08-08, checked line by line against the code. Edit this in
> RevenueCat → Paywalls; it takes effect without an app release.
>
> **The rule:** every bullet here is something the app does **today**. The
> published paywall previously promised family spaces, shared tasks and alerts
> when none of the three existed — Apple's review checks that an in-app purchase
> delivers what it advertises (guideline 3.1.2), and it's the kind of thing that
> produces refunds and one-star reviews.

---

## What changed since the current published version

| Current bullet | Status | Action |
|---|---|---|
| More scans | ✅ true (60/day + 300/30d vs 10 + 20) | keep |
| Spaces for each family member | ✅ **now true** — profiles shipped | keep, reworded |
| Shared tasks and alerts | ⚠️ **half true** — shared across devices yes; instant "Mom added a task" alerts are NOT built (deferred, see `later_ideas.md`) | **rewrite — drop "alerts"** |
| Unlimited tracking | ❌ false — Plus is 100 to-dos **per person** | **rewrite — say the number** |

---

## Headline

**More room, and room for your family**

## Subhead

Free covers one person on one device, with a limited number of scans. Tadah Plus
opens it up to the people you look after.

## Bullets

**Everyone gets their own list**
Add up to 8 people — a parent, a partner — so their letters and bills stay in
their own list instead of mixed into yours.

**More scans and guides**
60 a day and 300 a month, instead of 10 a day and 20 a month.

**More to-dos, for each person**
Up to 100 at a time per person, instead of 20.

**All your devices, in sync**
Use Tadah on up to 8 devices and everything stays up to date. A free account
works on one device at a time.

---

## 中文

**标题：** 更多空间，也为家人准备

**副标题：** 免费版仅限一人一台设备，扫描次数也有限。Tadah Plus 让你也能照顾家人。

- **每个人都有自己的清单** — 最多添加 8 人（父母、伴侣），他们的信件和账单会单独归类，不会和你的混在一起。
- **更多扫描与指南** — 每天 60 次、每月 300 次（免费版为每天 10 次、每月 20 次）。
- **每人更多待办事项** — 每人最多 100 条（免费版为 20 条）。
- **多设备同步** — 最多 8 台设备，内容始终保持同步。免费账户一次只能在一台设备上使用。

## Español

**Título:** Más espacio, y espacio para tu familia

**Subtítulo:** El plan gratuito cubre a una persona en un dispositivo, con escaneos
limitados. Tadah Plus lo abre a las personas que cuidas.

- **Cada persona con su propia lista** — añade hasta 8 personas (un padre, tu pareja)
  para que sus cartas y facturas no se mezclen con las tuyas.
- **Más escaneos y guías** — 60 al día y 300 al mes, en lugar de 10 y 20.
- **Más tareas, para cada persona** — hasta 100 a la vez por persona, en lugar de 20.
- **Todos tus dispositivos, sincronizados** — usa Tadah en hasta 8 dispositivos. Una
  cuenta gratuita se usa en un dispositivo a la vez.

---

## Add back later

When instant push notifications ship (`later_ideas.md` §1), add:

**Know when something changes**
Get a notification the moment someone in your family adds or finishes a to-do.

Until then the app only catches up when it's opened, so this bullet would be
overselling it. Note that **family deadline reminders already work** — once a
to-do syncs, every device schedules its own reminders for it — that's just not a
push-notification feature, so it belongs in the "in sync" bullet rather than its
own.

## Also check in the dashboard

- Prices shown on the paywall come from the Offering, so confirm they match what
  you set in App Store Connect (the template's $9.99 / $79.99 are placeholders
  until real products are attached).
- Add localizations for **en / zh-Hans / es** — `PaywallView` passes the user's
  picked language, and a missing one silently falls back to English.
