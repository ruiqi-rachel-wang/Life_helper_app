# Tadah Plus paywall — copy to paste into RevenueCat

> Written in the voice of the paywall Rachel already had — warm, benefit-first.
> Edit in RevenueCat → Paywalls; takes effect with no app release.
> Then **Publish changes** (top right) — a draft isn't live.

## Two rules baked into this copy

**No explicit numbers.** Don't write "60 scans a day" or "100 to-dos". Apple treats
an in-app purchase's description as a promise, so a published figure locks the
limits in — tuning them later would make the paywall false. Say "much more than
the free plan"; the real numbers live in `ScanQuota.swift` / `TaskLimit.swift` and
are shown in the app when someone actually reaches a limit. The one number kept is
*"a free account works on one device at a time"* — that's a rule people need up
front, not a quota, and hiding it causes the "why was I signed out?" email.

**Nothing that isn't built.** The published version promised *shared tasks and
alerts* and *unlimited tracking*; neither existed. There is no push notification,
and Plus is capped. Apple checks that an IAP delivers what it advertises
(guideline 3.1.2), and it's also how you get refunds and one-star reviews.

## Three benefits, then a forward-looking line

Plus gates exactly four things in the code — scan/guide limits, to-do limits,
family profiles, devices — so there is no fifth feature to list. "No extra charge
per person" is folded into the family bullet rather than given its own, since
*"do I have to pay again for Mom?"* is the objection that actually blocks the sale.

Bullet 4 promises **inclusion, not features**: "new Plus features arrive as part of
your subscription" stays true whatever ships and whenever. Avoid a bare "more
features coming" — that reads as a roadmap commitment, the same shape as the
"alerts" bullet that had to be removed.

---

## 中文

**标题**
更多空间管理资料，自己用或和家人一起用

**副标题**
免费版支持 1 台设备，并提供有限的扫描次数。升级 Tadah Plus 后，可获得更多扫描额度，还能为家人创建独立空间，把全家要办的事放在一个清单里。

**1 · 家庭成员空间**
为每位家人创建独立空间，全家共用一份订阅，无需为每人额外付费。一个页面就能看到全家要办的事，每条都标明是谁的。

**2 · 更多扫描与记录空间**
扫描、指南和待办事项的额度都大幅提高，不必担心很快达到免费版上限。

**3 · 多台设备同步**
在你的多台设备上使用，全家的更新随时保持一致。免费账户一次只能在一台设备上使用。

**4 · 更多功能陆续加入**
Tadah 仍在持续开发，后续新增的 Plus 功能都会包含在你的订阅中。

---

## English

**Title**
More room for your paperwork — on your own, or with family

**Subtitle**
The free plan covers one device and a limited number of scans. Tadah Plus raises
the limits, gives each family member their own space, and puts everything the
family has to do in one list.

**1 · A space for each family member**
Give a parent or partner their own space — one subscription covers everyone, with
no extra charge per person. See everything the family has to do in one list,
marked by person.

**2 · More scans, and more room**
Higher limits for scans, guides and to-dos, so you stop bumping into the free
plan's ceiling.

**3 · All your devices, in step**
Use Tadah on your other devices and stay up to date. A free account works on one
device at a time.

**4 · More to come, included**
Tadah is still being built. New Plus features arrive as part of your subscription.

---

## Español

**Título**
Más espacio para tus papeles — para ti, o para toda la familia

**Subtítulo**
El plan gratuito cubre un dispositivo y un número limitado de escaneos. Tadah Plus
amplía los límites, da su propio espacio a cada familiar y reúne en una sola lista
todo lo que la familia tiene que hacer.

**1 · Un espacio para cada familiar**
Dale su propio espacio a un padre o a tu pareja: una suscripción cubre a todos, sin
cargo adicional por persona. Ve en una sola lista todo lo que la familia tiene que
hacer, marcado por persona.

**2 · Más escaneos y más espacio**
Límites más altos para escaneos, guías y tareas, para que no choques con el tope
del plan gratuito.

**3 · Todos tus dispositivos, al día**
Usa Tadah en tus otros dispositivos y mantente al día. Una cuenta gratuita se usa
en un dispositivo a la vez.

**4 · Más por venir, incluido**
Tadah sigue creciendo. Las nuevas funciones Plus llegan incluidas en tu suscripción.

---

## Add back when it exists

Instant push notifications are deferred (`later_ideas.md` §1). When they ship, the
old bullet becomes true and can return:

> **共享任务与提醒** — 有人新增、更新或完成任务时，你都能及时收到提醒。
> **Shared tasks and alerts** — Get told the moment someone adds or finishes a to-do.

Family **deadline** reminders already work — once a to-do syncs, every device
schedules its own — which is covered by the "devices in step" bullet.

## Also check in the builder

- Prices come from the Offering. Confirm they match the products in App Store
  Connect before publishing.
- Do all three languages — `PaywallView` passes the user's chosen language, and a
  missing one silently falls back to English, for exactly the audience this is for.
- Lead with the family bullet. It's the hook; "more room" is the weakest opener.
