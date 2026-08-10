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
免费版仅限 1 台设备、扫描次数有限。Tadah Plus 提高额度，为每位家人建立独立空间，全家的事集中在一个清单里。

**1 · 家庭成员空间**
一份订阅覆盖全家，无需按人付费。全家的事在一个清单里，标明是谁的。

**2 · 更多扫描与空间**
扫描、指南和待办事项的额度都大幅提高。

**3 · 多台设备同步**
各台设备随时保持一致。免费版一次仅限一台。

**4 · 更多功能陆续加入**
后续新增的 Plus 功能都包含在订阅中。

---

## English

**Title**
More room for your paperwork, solo or with family

**Subtitle**
Free covers one device and limited scans. Plus raises the limits, gives each
person their own space, and keeps family tasks in one list.

**1 · A space for each person**
One subscription covers everyone. Family tasks in one list, marked by person.

**2 · More scans and room**
Higher limits for scans, guides and to-dos.

**3 · All your devices**
Stay in step everywhere. Free is one device at a time.

**4 · More to come**
New Plus features are included as they arrive.

---

## Español

**Título**
Más espacio para tus papeles, solo o en familia

**Subtítulo**
Gratis cubre un dispositivo y escaneos limitados. Plus amplía los límites, da su
propio espacio a cada persona y reúne las tareas de la familia en una lista.

**1 · Un espacio para cada persona**
Una suscripción cubre a todos. Las tareas de la familia en una lista, marcadas por
persona.

**2 · Más escaneos y espacio**
Límites más altos para escaneos, guías y tareas.

**3 · Todos tus dispositivos**
Todo al día en cada uno. Gratis: un dispositivo a la vez.

**4 · Más por venir**
Las nuevas funciones Plus se incluyen según llegan.

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
- Kept short on purpose (2026-08-09): one short sentence per bullet, so all four
  fit without scrolling. Longer copy pushed bullet 4 off-screen entirely.
