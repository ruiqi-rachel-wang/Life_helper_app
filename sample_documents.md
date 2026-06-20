# Cuevi — extraction tuning corpus

Real OCR samples (Week 4) + a few standard bills/tax docs, each with the
**ideal `ExtractionResult`**. Used to tune the OpenAI prompt and as gold data
for tests. Samples 1–5 are Rachel's real documents; 6–8 are representative of
standard formats (modeled on the real layouts, not a specific scan).

> KEY INSIGHT from the real set: most are NOT "a bill with an amount due by a
> date." They're an itinerary, an appointment, a paid receipt with an expiry, a
> form with a submission deadline, and an account credit. `amount` is often nil
> and the actionable date is an expiry / appointment / departure / deadline —
> not "payment due." The prompt + parser must handle that, not assume a bill.

---

## 1. United Airlines — flight itinerary (travel)

```
Ticket Itinerary and Receipt for Confirmation A4C33C
United Airlines <Receipts@united.com>
Wednesday, June 3, 2026 at 10:16 AM
Flight to Chicago
United Airlines UA 623
Confirmation code: A4C33C
Departure: Thu 06/25/2026 8:05 AM (2 hrs 39 mins)
LGA  8:05 AM  Thu 6/25/2026  New York
ORD  9:44 AM  Thu 6/25/2026  Chicago
Flight 1 of 1 UA623   Class: United Economy (N)
Thu, Jun 25, 2026  08:05 AM  New York, NY, US (LGA)
Thu, Jun 25, 2026  09:44 AM  Chicago, IL, US (ORD)
Traveler Details
WANG/BAOCAI   eTicket number: 0162108515648   Seats: LGA-ORD
```

Ideal: documentType "Flight itinerary" · sender "United Airlines" · amount nil ·
dueDate **2026-06-25** (departure, NOT the June 3 sent-date) · accountNumber
"A4C33C" (confirmation) · category **personal** · repeats nil · summary "Your
United flight UA623 from New York (LGA) to Chicago (ORD) departs June 25 at
8:05 AM." · steps: check in 24h before · arrive ~2h early · save confirmation
A4C33C.
**Parser gotcha tested:** two dates (sent vs departure) → the "departure" cue
must win; the old "first date" rule wrongly picked June 3.

## 2. Costco Optical — contact-lens receipt + prescription (paid receipt)

```
COSTCO OPTICAL  —  FASHION FRAMES * CONTACT LENSES * PRESCRIPTION LENSES
INVOICE DATE 8/30/25   INVOICE NO. 6166840   MEMBER NO. 111975171988
PATIENT: WANG, RUIQI   8310 GLOBE DR, MADISON, WI 53717-4201
PRESCRIBING DOCTOR: Arthurs   Rx WRITTEN 8/27/25   Rx EXPIRES 8/27/26
CONTACT LENSES  R 8.40 14.00 -3.00   L 8.40 14.00 -2.25
794393 Acuvue Oasys 2 Week 24 Pk  116.49
794385 Acuvue Oasys 2 Week 24 Pk  116.49
SUBTOTAL 232.98   TAX 0.00   TOTAL 232.98   Visa 232.98   CHANGE 0.00
```

Ideal: documentType "Optical receipt / prescription" · sender "Costco Optical" ·
amount nil (already PAID — not money owed) · dueDate **2026-08-27** (Rx expires) ·
category **medical** · repeats nil · summary "Receipt for Acuvue Oasys contacts
($232.98, paid). Your prescription expires Aug 27, 2026." · steps: reorder before
the Rx expires · book an eye exam if it's expired · keep this receipt for FSA/HSA.
**Parser note:** "232.98" has no `$` but the trailing-cents rule still catches it;
the "expires" cue picks 8/27/26 over the three earlier dates.

## 3. NYC TLC — medical certification form (government deadline, bilingual)

```
NYC Taxi & Limousine Commission — Licensing, Driver Application Unit
31-00 47th Avenue, 3rd floor, Long Island City, NY 11101
医学证明表格—新驾驶员申请人  (Medical Certification Form — New Driver Applicant)
体检日期不能比 TLC 申请的提交日期早 90 天以上。
FOR LICENSED PHYSICIAN'S USE ONLY:
I certify that I have examined Baocai Wang ... on 5/22/2026
[x] is medically fit to safely operate a TLC licensed vehicle.
Physician: KAM, YI SHENG, DO   License: 262586
248-12 Northern Blvd. 2A, Little Neck, NY 11362   Tel: (718) 281-3028
NEW DRIVER APPLICATION - Medical Form
```

Ideal: documentType "TLC medical certification" · sender "NYC Taxi & Limousine
Commission" · amount nil · dueDate **2026-08-20** (exam 5/22 + 90 days) — or flag
low-confidence if the model won't compute it · category **government** · summary
"Your TLC driver medical form (exam May 22, 2026, marked medically fit). Submit
to TLC within 90 days of the exam." · steps: upload at nyc.gov/tlcup · submit
within 90 days of 5/22 · keep a copy.
**Hard case:** the real deadline is *computed* (exam + 90d), not printed. Parser
returns the exam date or nil; the LLM should explain the 90-day rule.

## 4. GEICO — auto-repair appointment (appointment)

```
GEICO <geico@et.geico.com>   Friday, June 5, 2026 at 3:45 PM
Your GEICO vehicle appointment
You set up the following appointment for your vehicle at a GEICO Auto Repair Xpress shop:
Date: 06/24/2026   Time: 11:00 AM
Location: Northern Boulevard Collision-XD
325A GREAT NECK RD, GREAT NECK, NY, 11021-4204
Please be sure to bring your driver's license and vehicle registration ...
```

Ideal: documentType "Repair appointment" · sender "GEICO" · amount nil · dueDate
**2026-06-24** · category **personal** (or finance/insurance) · summary "Your
GEICO auto-repair appointment is June 24 at 11:00 AM at Northern Boulevard
Collision in Great Neck." · steps: arrive June 24 11:00 AM · bring driver's
license + vehicle registration · remove personal items · expect ~30 min drop-off.

## 5. GNPS — school lunch account balance (form / choose an option)

```
foodservices@greatneck.k12.ny.us   Friday, May 29, 2026 at 1:42 PM
GNPS Positive Lunch Account Balance
The Fangqin Zhu Household, 216 Schenck Ave, Great Neck, NY 11021
Student Name: Siyue Wang   Customer ID: 300012817   Balance $120.60
Our records indicate your 12th grade student has a positive balance ...
1. Donate the balance to a family in need within the district.
2. Request a refund.
3. Transfer the balance to a sibling currently enrolled in the GNPS.
```

Ideal: documentType "School lunch account notice" · sender "Great Neck Public
Schools" · amount **120.60** (a credit, not owed — note in summary) · dueDate
nil · accountNumber "300012817" · category **personal** · summary "Siyue Wang
has a $120.60 credit in the school lunch account. Choose what to do with it."
· steps: pick donate / refund / transfer · complete + return the form by email
or mail.
**Parser note:** "Balance $120.60" → amount 120.60; "Customer ID: 300012817" is
caught by the reference/number rule.

---

## 6. Con Edison — electricity bill (utility) · STANDARD, representative

```
Con Edison
Your Energy Bill
Account number: 12-3456-7890-0001
Service address: 100 Main St, Apt 4B, New York, NY 10001
Billing period: May 1 - May 31, 2026
Amount due: $86.42
Payment due date: June 15, 2026
Pay your bill at coned.com or by phone at 1-888-925-5016.
This is a monthly bill.
```

Ideal: documentType "Utility bill" · sender "Con Edison" · amount **86.42** ·
currency USD · dueDate **2026-06-15** · accountNumber "12-3456-7890-0001" ·
category **utility** · repeats **monthly** · steps: pay before June 15 · save
the confirmation.

## 7. NYC Dept of Finance — property tax bill (tax/government) · STANDARD

```
The City of New York — Department of Finance
Property Tax Bill — Quarterly Statement
Owner: BAOCAI WANG
Property: 8310 Globe Dr, Borough/Block/Lot ...
Account / BBL: 1-01234-0056
Amount due: $1,342.18
Due date: 07/01/2026
A 18% annual interest applies to late payments.
Pay online at nyc.gov/payonline.
```

Ideal: documentType "Property tax bill" · sender "NYC Department of Finance" ·
amount **1342.18** · currency USD · dueDate **2026-07-01** · accountNumber
"1-01234-0056" · category **government** · repeats **everyNDays(~90)** (quarterly)
· steps: pay before July 1 to avoid 18% interest · pay at nyc.gov/payonline.

## 8. IRS — CP14 balance-due notice (tax) · STANDARD

```
Internal Revenue Service
Notice CP14   Tax year 2025   Notice date: June 2, 2026
Taxpayer ID: XXX-XX-1234
Amount due: $1,247.00
Pay by July 1, 2026 to avoid additional interest and penalties.
Make your payment at irs.gov/payments.
```

Ideal: documentType "IRS notice (CP14)" · sender "Internal Revenue Service" ·
amount **1247.00** · dueDate **2026-07-01** · category **government** · steps:
pay $1,247 by July 1 at irs.gov/payments · keep the notice · set up a plan if you
can't pay in full.
