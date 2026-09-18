# RevenueCat Shipaton 2026 — the plan

> Created 2026-09-18. **Deadline: Wednesday September 30, 2026, 11:45 pm PDT**
> (2:45 am New York, Oct 1). Winners announced October 21.
> Rules: https://revenuecat-shipaton-2026.devpost.com/rules

**Twelve days.** The app is already built and shipped. Everything below is
submission work, not product work. Resist adding features.

---

## 1. Are we even eligible? Yes — verified

The rule that disqualifies most people is this one:

> "The first public version of the Project must be released during the
> Submission Period on Apple's App Store, the Google Play Store, or the
> Samsung Galaxy Store."

Submission period is **August 1 – September 30, 2026**.

| Check | Status |
|---|---|
| First public release inside the window | ✅ **1.0 went live September 10, 2026.** Verified on the live App Store page, not from notes. |
| No earlier public release under another name | ✅ The store shows Sept 10 as the earliest version. Cuevi/Notie never shipped publicly — only TestFlight. |
| TestFlight doesn't count as prior publication | ✅ Rules say only official store releases disqualify. |
| RevenueCat SDK powers at least one purchase | ✅ `Purchases.configure` in `TadahApp.swift:50`, entitlement `Tadah Pro`. |
| Fully published by the deadline | ✅ 1.0 live Sept 10, **1.1 with Calls live Sept 17**. |
| Accessible from the United States | ✅ |
| Age 18+ | ✅ |

**This is a real advantage.** Most entrants are shipping on the last day and
praying App Review clears them. You are already live, with two versions out and
a shipped AI calling feature. Nothing about the deadline is a risk for you.

### Next Gen Award — not entering

$20k, judged only on video + public repo, no store release needed. Tempting,
but it requires **active students**, and you've graduated. The .edu address may
still pass the automated swot/JetBrains domain check, but the check validates
the *domain*, not your enrolment. Entering as a non-student is a
misrepresentation the rules let them disqualify you for, and it would also
force the repo public. Skipped by decision, 2026-09-18.

---

## 2. Which awards to enter

You said: whichever fits and gives a good chance. Here is the honest ranking.
One video and one Devpost entry serve all of them, so this is about which
boxes to tick, not extra work.

### ✅ Enter: RevenueCat Peace Prize — $20k / $10k / $5k

Judged on **social impact: feasibility, reach, community benefit.** Not on
revenue, not on polish, not on traction.

This is your best category by a wide margin, because the story is true and
almost nobody else at this hackathon has one like it:

- Tadah exists for people who open English mail they can't fully read — new
  immigrants, elderly parents, mixed-language households.
- It works in **English, Spanish and Chinese**, which is reach, not a feature list.
- Calls solves the part nobody automates: the phone call in a second language,
  through a phone menu, on hold.
- **Feasibility is proven** — it's shipped and live, not a prototype.

Most Shipaton entries are productivity tools and AI toys. A trilingual life-admin
app that phones institutions for people who can't is genuinely differentiated.

### ✅ Enter: HAMM (Help Apps Make Money) — $20k / $10k / $5k

Judged on **clear revenue streams, monetization innovation, sustainability** —
explicitly the *design* of the business, not the size of the revenue. Good,
because the app is eight days old.

You have a real answer here, and it's the one worth telling:

- Free tier is generous but bounded (20 scans/day, 50/30 days, 20 to-dos).
- Plus at **$6.99/mo or $59.99/yr** raises the limits — but that's the weak pitch.
- **Calls is the actual reason to pay.** "Tadah will make the call for you" is a
  benefit, where "60 scans" is just a bigger number.
- Calls has **real marginal cost** (~$1.56 per call), so it's capped at 5/month
  for Plus. That's an honest unit-economics story, and judges notice when a
  monetization model survives contact with COGS.
- RevenueCat isn't decoration: the Worker checks the entitlement
  **server-side** via the REST API before it will place a call. Purchase
  gates a real, expensive action.

### ⚠️ Optional: #BuildInPublic — $30k / $20k / $10k

Biggest prize pool, judged on how much you shared the journey publicly. You
haven't been posting, and twelve days of posts against people who've posted all
summer is weak. **Only do this if posting is something you want anyway** — it's
also useful for the job search. If you do: post daily, tag `#Shipaton` and
`#BuildInPublic`, and collect the links for the submission form.

### ❌ Skip

| Award | Why not |
|---|---|
| Grand Prize | Shortlist is ranked by RevenueCat revenue during the window. Eight days of sales won't rank. |
| Design Award | Competes with design-led showpiece apps. Tadah is clean and clear, not a visual showcase. |
| Productivity (Lawley) | Reads like a fit — "file/text organization" — but his audience is iPad/Shortcuts power users. Tadah is for people who need *less* to operate, the opposite user. |
| Catvertising | Needs RevenueCat Ads. Not integrated, and ads would be wrong for this app. |
| OneSignal / Layers / Noise / Stripe / Replit / Kotlin / Samsung / Best Game | Each needs an SDK or platform you haven't shipped. Not worth twelve days. |

---

## 3. The new video — the one thing that must be made

**Hard limit: under 2:00.** The CALL-E cut is **2:22**, so it cannot be reused
as-is. Judges aren't required to watch past two minutes.

Requirements: must show the app **running on a real device**, hosted publicly
on **YouTube or Vimeo**, no third-party trademarks.

### What changes from the CALL-E video

| CALL-E cut | Shipaton cut | Why |
|---|---|---|
| "approved by App Review" | **"live on the App Store"** | It is now. This is your credibility beat — say it early. |
| Mockup screens in scenes 3–7 | **Real screen recordings** | 1.1 is live and `CALLE_DRY_RUN = "0"`. The excuse for mockups is gone, and "footage on the device" is required. |
| Scene 9: Worker/CALL-E architecture (21s) | **Cut to ~5s or drop** | Shipaton judges are scoring product and monetization, not your webhook design. This is where you buy back the 25 seconds. |
| No monetization beat | **New scene: free → Plus → Calls** | HAMM needs it, and it's the business story. |
| "CALL-E hackathon" framing | RevenueCat / Shipaton framing | Don't hand judges another sponsor's name. |

### Target running order (~1:50)

| # | Time | Scene | Beat |
|---|---|---|---|
| 1 | 0:00 | Title | "Tadah. Paperwork, handled. **Live on the App Store.** And it makes the phone call for you." |
| 2 | 0:10 | Problem | Mail you can't fully read ends in a call you can't make. |
| 3 | 0:22 | Scan → understand | **Real footage.** Bill → Review screen explains it. |
| 4 | 0:36 | The offer | "Tadah can make this call." Number comes from the document; never invented. |
| 5 | 0:48 | You confirm | Who, what it asks, what it may agree to (nothing by default), account number off by default. |
| 6 | 1:02 | The call | **Real call, real answer landing on the to-do**, in her language. |
| 7 | 1:22 | **Why it's a business** | Free tier is generous. Calls costs real money per call, so it's Plus — 5/month. RevenueCat gates it server-side before a line is ever seized. |
| 8 | 1:38 | Close | Live on the App Store, in three languages. "Let me do that for you." |

Front-load scenes 1–6: if a judge stops at 60 seconds they must already have
seen a real call happen.

### How to build it

The pipeline already exists in `../../misc/calle_video/`:

- `make_video.py` — all narration and on-screen text is at the top of the file.
- `frames/01…10_*.png` — 1920×1080 stills, reusable for scenes 1, 2, 8.
- `voice/*.m4a` — per-scene narration; **record in your own voice**, judges
  respond to the builder. File must start with the scene name.
- `tadah_calle_roughcut.srt` — regenerate, don't reuse; the narration changes.

The venv it referenced lived in a temp folder that's now gone. Recreate:

```
cd "/Users/rachelwang/Project!/misc/calle_video"
python3 -m venv vid && vid/bin/pip install imageio-ffmpeg
vid/bin/python make_video.py
```

**Shoot the real footage first** (it's the long pole), then cut narration to fit.
Screen-record on the iPhone with Control Center → Screen Recording, microphone
**on**. Call your second phone and play the rep — say so in the voiceover
("for this demo it's calling my other phone"). Honest, and judges prefer it to
a staged claim. Budget 3–4 takes.

⚠️ Calls are **live and cost ~$1.56 each**. Check the CALL-E balance before a
recording session — it has been negative before.

---

## 4. Judges must be able to use Plus for free

Easy to miss, and it's a rule:

> "The Entrant must make the Project available free of charge and without any
> restriction, for testing, evaluation and use by the Sponsor, Administrator
> and Judges until the Judging Period ends."

The app is a free download, so the free tier is already open to them. But
**Calls is the whole demo and it's Plus-only.** Options:

1. **Demo account (easiest).** `support.tadah@gmail.com` is verified and has
   Plus. `appletesting@tadah.com` is verified and needs the `Tadah Pro` grant
   in RevenueCat. Both were built for App Review — reuse them.
2. **App Store offer codes.** Generated in App Store Connect for the
   subscription. Cleaner for judges, since they use their own account.

⚠️ **Watch the call cap.** Plus is 5 calls/month. If several judges share one
demo account they'll exhaust it, and each call costs you real money. Before
submitting: raise the cap for the demo accounts, or hand out separate accounts,
and top up the CALL-E balance.

---

## 5. Submission checklist

Everything the Devpost form will want.

- [ ] **Register on Devpost and start the submission** — do this first, on day
      one, not on the 30th. Nothing else counts if this doesn't exist.
- [ ] Video, under 2:00, public on YouTube or Vimeo, captions uploaded
- [ ] App icon, 1024×1024
- [ ] Screenshots, **1179 × 2556, no device frames** (existing App Store
      screenshots are framed — check and re-export if so)
- [ ] App Store link (id6782480135)
- [ ] Text description of features and functionality
- [ ] Judge access: demo account credentials, or offer codes
- [ ] Tick **Peace Prize** and **HAMM**
- [ ] (If doing #BuildInPublic) links to the tagged posts
- [ ] Submit **at least 2 days early**. Devpost jams on deadline night.

---

## 6. Suggested order for the twelve days

| When | What |
|---|---|
| **Day 1 (Sept 18)** | Register on Devpost, open the submission, save a draft. Check the CALL-E balance and the demo accounts' Plus grant. |
| **Days 2–3** | Shoot real footage: scan, offer, confirm, live call, answer landing. Several takes. |
| **Days 4–5** | Rewrite narration in `make_video.py` to the running order above. Record your voice. |
| **Days 6–7** | Cut, caption, export. **Verify it's under 2:00.** Upload to YouTube. |
| **Days 8–9** | Screenshots at the required size, icon, write the Devpost description (adapt the CALL-E draft — strip CALL-E framing, add RevenueCat and the live-on-App-Store fact). |
| **Day 10 (Sept 27–28)** | Fill in and **submit**. |
| **Days 11–12** | Buffer. Fix anything that breaks. Don't add features. |

---

## 7. What not to do

- **Don't ship a new feature for this.** The app is live and working. A
  rejected build during judging is the only way to lose eligibility now.
- **Don't rebuild the app for the video.** Record what's live.
- **Don't chase Grand Prize.** It's revenue-ranked; the math doesn't work.
- **Don't make the repo public just to enter Next Gen.** You're not an active
  student, and the repo is private by decision.
