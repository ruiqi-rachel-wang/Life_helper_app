# Privacy Policy for Plaino

**Effective date:** June 18, 2026
**Last updated:** June 18, 2026

> ⚠️ **Template — not legal advice.** This draft reflects how Plaino actually
> handles data today, but you should have a lawyer review it before a paid or
> public App Store launch, especially because Plaino touches tax, immigration,
> insurance, medical, and legal topics. Fill in every **[BRACKETED]** placeholder.

Plaino ("Plaino", "we", "us") is an iOS app that helps you understand letters,
bills, and official documents and turn them into reminders and checklists. This
policy explains what data the app handles and what happens to it.

The short version: **your documents and data stay on your device.** Plaino has no
accounts, no sign-in, and no server database. The only time information leaves
your phone is when the *text* of a document is sent for AI processing, described
below.

---

## 1. Who is responsible

Plaino is operated by **Ruiqi Wang**, as a sole proprietor based in New York,
United States.
Questions about this policy: **ruiqiwang_rachel@outlook.com**.

(If a business entity such as an LLC is formed later, this section will be updated
with its legal name and address.)

---

## 2. What we collect and process

### Stays entirely on your device
- **Your documents, photos, and scans.** Photos you take or upload are read by
  on-device text recognition (Apple Vision OCR). The photo and the recognized
  text are stored **locally on your device only**, attached to the item you save.
- **Items you create** — titles, amounts, due dates, steps, saved fields, notes,
  and reminders — are stored locally on your device using Apple's on-device
  database (SwiftData).
- **Reminders/notifications** are scheduled locally by iOS. We do not see them.
- **Your settings** (such as your chosen explanation language) are stored locally.

We do **not** have a server that stores any of the above. We cannot see your
documents or items. Uninstalling the app removes this local data.

### Text sent off the device for AI processing
- When you scan or upload a document, or build certain non-sensitive guides, the
  **recognized text** of that document is sent to **OpenAI** to generate a plain-
  language summary, action steps, and (for guides) lightly reworded checklist text.
- We send only the **document text** and your chosen explanation language. We do
  **not** send your name, an account ID, or a device identifier (there is no
  account).
- The request is routed through a privacy proxy we operate (a **Cloudflare
  Worker**) so that our API key is never embedded in the app. Cloudflare may
  briefly process your device's **IP address** to rate-limit abuse; it is not used
  to identify you and we do not store it.
- OpenAI processes the text to return the result. Plaino does **not** store your
  document text on any server of ours. OpenAI's handling of API data is governed
  by OpenAI's own policies; per OpenAI's API terms, data submitted via the API is
  not used to train their models.

### Sensitive topics never leave your device
Guides we classify as **sensitive** — money/banking, taxes, immigration (USCIS),
medical, and similar — are generated **entirely on your device** and are **never
sent to OpenAI**. These show a "stays on your device" badge in the app.

### We do NOT
- We do **not** sell or rent your data.
- We do **not** use your data for advertising.
- We do **not** link your bank, process payments, or use autopay.
- We do **not** currently use any third-party analytics or tracking. *(If we add
  privacy-first, no-PII analytics in the future, we will update this policy first.)*

---

## 3. Third parties that may process data

| Provider | What they process | Why |
|---|---|---|
| **OpenAI** | The text of documents you scan/upload (non-sensitive only) | To generate summaries and action steps |
| **Cloudflare** | Your IP address, transiently | To proxy the AI request and rate-limit abuse |
| **Apple** | Local storage, on-device OCR, local notifications | Standard iOS app functionality (on your device) |

We are not responsible for these providers' own practices; please review their
privacy policies (OpenAI, Cloudflare, Apple).

---

## 4. Data retention

- **On-device data** stays until you delete the item or uninstall the app. You are
  in control.
- **AI requests** are processed in transit and returned; we keep no server copy.
  OpenAI's retention of API data is governed by their policy.

---

## 5. Your choices and rights

Because your data lives on your device and we hold no server copy:
- **Delete anytime** — delete an item, or uninstall the app, to remove your data.
- **Don't want text sent to OpenAI?** Use the manual-entry option instead of
  scanning, or use the on-device sensitive guides.

**California (CCPA) and EU/UK (GDPR):** we do not maintain personal data on our
servers, so there is no server-side profile to access, port, or delete — you
already control it on your device. For any questions about your rights, email us
at the address above.

---

## 6. Children

Plaino is **not directed to children under 13** and we do not knowingly collect
data from them. (COPPA.)

---

## 7. Security

- Our AI key is held server-side in the Cloudflare Worker and is **not** shipped
  inside the app.
- Requests are rate-limited to deter abuse.
- Your documents are stored within the app's protected on-device storage.
- No method of transmission or storage is 100% secure, but we minimize risk by
  keeping data on-device and sending the least amount of text necessary.

---

## 8. Changes to this policy

We may update this policy as the app evolves (for example, if we add accounts,
sync, or analytics). We will revise the "Last updated" date above, and material
changes will be reflected in the app.

---

## 9. Contact

**Ruiqi Wang** — **ruiqiwang_rachel@outlook.com**
