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

## 3. The video — built, one story, 1:33

**Hard limit: under 2:00.** Judges aren't required to watch past two minutes.
Must show the app on a device, be public on YouTube or Vimeo, and use no
third-party trademarks.

Lives in **`../../misc/shipaton_video/`** (outside this repo). `SCRIPT.md` there
has every line, what's on screen during it, and how to record your own voice.

**One video, not two** (Rachel, 2026-09-18: "why two videos? I thought we only
need one"). It is the submission and the ad.

**It tells Rachel's story, told in the third person until the last line:**
Mom texts a photo of a letter ("这是什么意思？ 要紧吗？ 你帮我处理一下吧") → *Now
there's Tadah* → **1 Mom scans** it herself → **2 Mom understands** it in Chinese
→ **3 Daughter sees it** on her own phone → **4 Knows what to do** → **5 Does it**:
Tadah makes the call → **6 Done**, with confetti and "Ta-dah." → Mom texts
thanks → *"I was that kid. I built Tadah because I hope…"* A six-chip rail
across the top tracks the steps, so the features read as a workflow and not a
list.

**Screens are rebuilt from the SwiftUI source, not guessed.** The first draft's
call screens were rejected ("the layout doesn't seem like mine"), because they
were invented. Now every screen follows `Color+Tadah.swift`,
`Font+Tadah.swift`, the 16pt / 14pt-radius / hairline card, the real section
order in `ReviewView` / `DetailView` / `InboxView` / `CallCard.swift`, and the
app's own Chinese from `Localizable.xcstrings`. The "Before Tadah calls" page is
the real 1.1 capture.

**Honest about how the app behaves**, all checked in code:
- The family feature is **profiles on one account**. A to-do filed under
  "Mom" syncs to every phone on that account (`TaskDTO.profileID`), and so do
  the profiles.
- The explanation language is **per phone** (`ExplainLanguage`, `@AppStorage`).
  So Mom's to-do still reads in Chinese on her daughter's English phone. The
  video shows it that way on purpose.
- The call answer comes back in the **caller's** language, so it's English on
  the daughter's phone.
- `markDone()` completes in place, so the finale is the real `✓ COMPLETED`.

**Still to do:**
- **Voice.** The draft uses the Mac's robot voice, as a timing placeholder
  only. The "I was that kid" ending in particular has to be Rachel. Record
  `voice/<line id>.m4a` and re-run. Or install Ava (Premium) and pass
  `--voice Ava`.
- **Optional real footage.** A few seconds of screen recording over the matching
  scene makes "functioning on the device" unarguable.
- Upload to YouTube with `tadah_shipaton.srt` as captions.

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
