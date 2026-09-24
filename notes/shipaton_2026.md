# RevenueCat Shipaton 2026 — the plan

> Created 2026-09-18. **Deadline: Wednesday September 30, 2026, 11:45 pm PDT**
> (2:45 am New York, Oct 1). Winners announced October 21.
> Rules: https://revenuecat-shipaton-2026.devpost.com/rules

**Six days left as of Sept 24.** The app is already built and shipped, and the
video is built. Everything below is submission work, not product work. Resist
adding features.

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

## 3. The video — built, one story, 1:43

**Hard limit: under 2:00.** Must show the app on a device, be public on YouTube
or Vimeo, and use no third-party trademarks.

Lives in **`../../misc/shipaton_video/`** (outside this repo). `SCRIPT.md` there
has every line, what's on screen during it, and how to record your own voice.

**One video** — it is the submission and the ad.

### What it shows

It opens on **three phones at once**: a Chinese mom, a Spanish-speaking mamá and
an English-speaking mom, each texting their daughter the same thing, with one
English subtitle under all three. That makes the point early that this is not
only an immigrant-family app — anyone can be handed a letter they can't parse.

Then it follows one family: **1 Mom scans** it herself → **2 Mom understands**
it in her language (the letter fans out into Español · 中文 · English) →
**3 Daughter sees it** on her own phone → **4 Knows what to do** → **5 Does it**,
Tadah makes the call → **6 Done**, confetti and "Ta-dah." → all three moms text
back. A six-step rail across the top tracks it, so the features read as a
workflow rather than a list.

**It isn't only about Calls.** After the call answer there is a reminder beat:
the bill is still due, so Tadah posts a reminder on *Mom's* phone, in Chinese
(`医院账单：$284.50 · 明天到期`), while the daughter's phone shows the REMINDERS
card. And the closing recap runs one phone through the whole app — scan ·
understand · steps · **a reminder arriving** · **the real Life Guides library** ·
calling — so the video covers reminders and guides, not just the phone call.

It ends in first person — *"This happened in my family, too. So I built Tadah,
to help."* — then a summary for everyone: *"for anyone who's ever opened a
letter and thought:"* with the question cycling through all three languages,
and a six-line recap (scan it · understand it · know what to do · get reminded ·
follow a guide · or let Tadah call).

### How it's made

**Not slides.** The phones sit at fixed places on one big canvas and a camera
glides and zooms between them, over a background that drifts more slowly for
depth. Text animates in word by word next to the action; translations appear as
film-style subtitles. (The first version was rejected as "like powerpoint":
fixed layouts, crossfades, and a heading/subheading block on every scene.)

**Screens are rebuilt from the SwiftUI source, not guessed.** Every screen
follows `Color+Tadah.swift`, `Font+Tadah.swift`, the 16pt / 14pt-radius /
hairline card, and the real section order in `ReviewView` / `DetailView` /
`InboxView` / `CallCard.swift`. Chinese and Spanish labels come from
`Localizable.xcstrings`, never translated by hand. The "Before Tadah calls"
page is the real 1.1 capture.

**Honest about how the app behaves**, all checked in code:
- Family = **profiles on one account**. A to-do filed under "Mom" syncs to every
  phone on that account (`TaskDTO.profileID`), and so do the profiles.
- The explanation language is **per phone** (`ExplainLanguage`, `@AppStorage`),
  so Mom's to-do still reads in Chinese on her daughter's English phone. The
  video shows it that way on purpose.
- The call answer comes back in the **caller's** language, so it's English on
  the daughter's phone.
- `markDone()` completes in place, so the finale is the real `✓ COMPLETED`.

### Feature coverage

Rachel's note, 2026-09-24: cover most features, but don't overemphasise any.
So the **call sequence was cut from four spoken lines to two**, and the time
went to everything else.

**Given a moment of their own:** scan · the explanation in three languages ·
**translating the document itself** (she taps the letter, 翻译 turns the page
Chinese) · action steps · **reminders and the notification they post** · family
profiles and "who it's for" · sync · Calls end to end · mark done · **the Guides
library and its tailoring questions**.

**Seen in passing, with no narration spent:** the three ways to add · DETAILS
and REFERENCE on the Review · NOTES on the to-do · the reminder list · due
dates and the urgency sections · free vs Plus · privacy (one subtitle:
reminders follow the person they belong to, and you choose whether they show
detail).

**Still out:** repeats for monthly bills, the stored-original card, the overdue
nudge. Each needs its own beat and the limit is 2:00.

### Still to do

- **Voice.** The draft uses the Mac's robot voice as a timing placeholder only.
  The two first-person lines especially have to be Rachel. Record
  `voice/<line id>.m4a` and re-run; each scene re-times around the take. Or
  install Ava (Premium) free and pass `--voice Ava`. At 1:36 there is ~20s of
  slack under the 2:00 limit for a slower human read.
- **Optional real footage.** A few seconds of screen recording dropped over the
  matching scene makes "functioning on the device" unarguable.
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

## 6. What's left, and when

Updated 2026-09-24. Done so far: eligibility confirmed, categories chosen, and
the video built (1:36, `misc/shipaton_video/`).

| When | What |
|---|---|
| **Now — before anything else** | **Register on Devpost and open the submission.** Nothing else counts without it, and it takes minutes. Save a draft so the form exists. |
| **Sept 24–25** | Record the narration in your own voice (18 lines, `voice/<id>.m4a`, re-run `make_video.py`). This is the single biggest improvement left. |
| **Sept 25–26** | Optional but strong: a few seconds of real screen recording over the matching scenes. Check the CALL-E balance and the demo accounts' Plus grant first. |
| **Sept 26–27** | Upload to YouTube (public/unlisted) with `tadah_shipaton.srt` as captions. Screenshots at 1179×2556 without frames, 1024×1024 icon. |
| **Sept 27–28** | Write the Devpost description, tick **Peace Prize** and **HAMM**, add judge access (demo account or offer codes). **Submit.** |
| **Sept 29–30** | Buffer only. Don't add features; don't ship a build. |

---

## 7. What not to do

- **Don't ship a new feature for this.** The app is live and working. A
  rejected build during judging is the only way to lose eligibility now.
- **Don't rebuild the app for the video.** Record what's live.
- **Don't chase Grand Prize.** It's revenue-ranked; the math doesn't work.
- **Don't make the repo public just to enter Next Gen.** You're not an active
  student, and the repo is private by decision.
