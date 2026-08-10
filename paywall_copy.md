# Tadah Plus paywall — copy to paste into RevenueCat

> Rewritten 2026-08-09 in the voice of the paywall Rachel already wrote — warm,
> benefit-first. Edit in RevenueCat → Paywalls; takes effect with no app release.
>
> **⚠️ NO EXPLICIT NUMBERS (Rachel, 2026-08-09).** Don't write "60 scans a day" or
> "100 to-dos". Apple treats an in-app purchase's description as a promise to the
> customer, so a published number locks the limits in — tuning them later would
> make the paywall false and mean another review. Say "much more than the free
> plan"; the real figures live in `ScanQuota.swift` / `TaskLimit.swift` and are
> shown in the app when someone actually hits a limit.
>
> The one number kept is **"a free account works on one device at a time"** —
> that's a rule people need up front, not a quota, and hiding it causes the
> "why was I signed out?" support email.

## What was wrong with the published version

| Bullet | Problem |
|---|---|
| 更多扫描次数 / More scans | ✅ fine as written |
| 家庭成员空间 / Spaces for family | ✅ **now true** — reworded so it also sells the shared list |
| 共享任务与提醒 / Shared tasks **and alerts** | ❌ "有人新增…你都能及时收到提醒" is **not built**. There is no push notification. Replaced with the multi-device benefit, which is real. |
| 不限量记录 / **Unlimited** tracking | ❌ "不再受数量限制" is false — Plus is capped. Reworded to "much more room", no number. |

---

## 中文

**标题**
更多空间管理资料，自己用或和家人一起用

**副标题**
免费版支持 1 台设备，并提供有限的扫描次数。升级 Tadah Plus 后，可获得更多扫描额度，还能为家人创建独立空间，把全家要办的事放在一个清单里。

**1 · 更多扫描次数**
大幅提高扫描和指南的使用额度，不必担心很快达到免费版上限。

**2 · 家庭成员空间**
为每位家人创建独立空间。一个页面就能看到全家要办的事，每条都标明是谁的，也可以只看自己的。

**3 · 多台设备同步**
在你的多台设备上使用，全家的更新随时保持一致。免费账户一次只能在一台设备上使用。

**4 · 更多记录空间**
每位家人都能保存远多于免费版的账单、任务和截止日期。

---

## English

**Title**
More room for your paperwork — on your own, or with family

**Subtitle**
The free plan covers one device and a limited number of scans. Tadah Plus raises
the limits, gives each family member their own space, and puts everything the
family has to do in one list.

**1 · More scans**
A much higher limit for scans and guides, so you stop bumping into the free
plan's ceiling.

**2 · A space for each family member**
Give a parent or partner their own space. See everything the family has to do in
one list, each to-do marked whose it is — or switch to just yours.

**3 · All your devices, in step**
Use Tadah on your other devices and everyone stays up to date. A free account
works on one device at a time.

**4 · More room for each person**
Every family member gets far more bills, tasks and due dates than the free plan
allows.

---

## Español

**Título**
Más espacio para tus papeles — para ti, o para toda la familia

**Subtítulo**
El plan gratuito cubre un dispositivo y un número limitado de escaneos. Tadah Plus
amplía los límites, da su propio espacio a cada familiar y reúne en una sola lista
todo lo que la familia tiene que hacer.

**1 · Más escaneos**
Un límite mucho más alto para escaneos y guías, para que no choques con el tope
del plan gratuito.

**2 · Un espacio para cada familiar**
Dale su propio espacio a un padre o a tu pareja. Ve en una sola lista todo lo que
la familia tiene que hacer, con cada tarea marcada de quién es, o cambia a ver
solo las tuyas.

**3 · Todos tus dispositivos, al día**
Usa Tadah en tus otros dispositivos y todos se mantienen al día. Una cuenta
gratuita se usa en un dispositivo a la vez.

**4 · Más espacio para cada persona**
Cada familiar guarda muchas más facturas, tareas y fechas límite que en el plan
gratuito.

---

## Add back when it exists

Instant push notifications are deferred (`later_ideas.md` §1). When they ship, the
old bullet becomes true again and can return:

> **共享任务与提醒** — 有人新增、更新或完成任务时，你都能及时收到提醒。
> **Shared tasks and alerts** — Get told the moment someone adds or finishes a to-do.

Until then it sells something the app can't do. Family **deadline** reminders do
already work — once a to-do syncs, every device schedules its own — and that's
covered by the "devices in step" bullet.

## Also check in the builder

- The prices shown come from the Offering. Confirm they match the products you
  created in App Store Connect before publishing.
- Do all three languages — `PaywallView` passes the user's chosen language, and a
  missing one silently falls back to English, for exactly the audience this is for.
- Then **Publish changes** (top right) — a draft isn't live.
