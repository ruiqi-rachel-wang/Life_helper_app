# Privacy Policy for Cuevi

**Effective date:** June 18, 2026
**Last updated:** June 23, 2026

> ⚠️ **Template — not legal advice.** This draft reflects how Cuevi actually
> handles data today, but you should have a lawyer review it before a paid or
> public App Store launch, especially because Cuevi touches tax, immigration,
> insurance, medical, and legal topics. Fill in every **[BRACKETED]** placeholder.

Cuevi ("Cuevi", "we", "us") is an iOS app that helps you understand letters,
bills, and official documents and turn them into reminders and checklists. This
policy explains what data the app handles and what happens to it.

The short version: **your documents and data stay on your device.** Cuevi has no
accounts and no sign-in. Two things leave your phone, both described below: (1) the
*text* of a document you scan is sent for AI processing, and (2) **anonymous,
non-identifying usage statistics** — which features you use, never your content —
are sent to a backend we run, so we can improve the app. You can turn off (2)
anytime in the app.

---

## 1. Who is responsible

Cuevi is operated as a sole proprietorship based in New York,
United States.
Questions about this policy: **support.cuevi@gmail.com**.

(If a business entity such as an LLC is formed later, this section will be updated
with its legal name and address.)

---

## 2. What we collect and process

### Stays entirely on your device
- **Your documents, photos, and scans.** Photos you take or upload are read by
  on-device text recognition (Apple Vision OCR). The **photo** and the **extracted
  details** (the item we create — title, amount, due date, steps, saved fields,
  notes) are stored locally on your device. The raw recognized text itself is **not
  kept** by the app — but when you scan, it **is sent to OpenAI** to produce the
  summary and steps (see the next section), so a scanned document's text does leave
  your device.
- **Items you create** — titles, amounts, due dates, steps, saved fields, notes,
  and reminders — are stored locally on your device using Apple's on-device
  database (SwiftData).
- **Reminders/notifications** are scheduled locally by iOS. We do not see them.
- **Your settings** (such as your chosen explanation language) are stored locally.

We do **not** have a server that stores any of the above. We cannot see your
documents or items. Uninstalling the app removes this local data.

### What is sent to OpenAI when you scan
- When you **scan or upload a document**, the app recognizes its text on-device and
  then sends that **full recognized text to OpenAI** to generate the summary and
  steps. **This text can include sensitive personal information** — whatever appears
  on the document, such as health, financial, tax, or immigration details, your
  name, and account, policy, or case numbers. If you'd rather not send a document's
  text, use **manual entry** instead of scanning.
- We don't attach a separate account or device identifier (the app has no account),
  but the document's text is sent as-is, so any personal details on it are included.
- For **non-sensitive guides**, the built checklist is sent to OpenAI to reword and
  translate it. **Sensitive guides** (below) are never sent.
- The request goes through a **Cloudflare Worker** we run, so our OpenAI key isn't in
  the app. Cloudflare may briefly process your device's IP address; we don't store it.
- OpenAI processes the text and returns the result; Cuevi keeps no server-side copy.
  Per OpenAI's API policy, API data is **not used to train their models**, but OpenAI
  may **retain it for up to ~30 days** for abuse monitoring.

### Sensitive GUIDES are generated on your device
The built-in **guides** we classify as sensitive — money/banking, taxes, immigration
(USCIS), medical, and similar — are generated **entirely on your device** and are
**never sent to OpenAI** (they show a "stays on your device" badge). This applies to
those guides only; it does **not** apply to **scanning**, where the recognized text is
sent to OpenAI as described above, however sensitive the document is.

### Anonymous usage statistics (sent to a backend we run)
To understand whether Cuevi actually helps — for example, of the items you add, how
many you come back and complete — the app sends a small amount of **anonymous,
non-identifying** usage data to a backend we operate (a Cloudflare database):
- **What happened, not what's in it:** that an item was *added* (and whether from a
  scan, a guide, or manual entry), or *completed* (and whether on time).
- A random **install identifier** created on your device, plus the app version and the
  time of the event. This labels an app installation — it is **not** your name, email,
  account, or Apple ID, and we cannot use it to identify you.
- It **never** includes your documents, photos, titles, amounts, due dates, notes, or
  any text from your items.

This is **first-party** data, used only to improve Cuevi. It is **not** advertising, is
**not** sold or shared, and is **not** used to track you across other apps or websites.
You can turn it off anytime under **Profile → Privacy → Share anonymous usage data**.

### We do NOT
- We do **not** sell or rent your data.
- We do **not** use your data for advertising.
- We do **not** link your bank, process payments, or use autopay.
- We do **not** use third-party analytics SDKs, advertising, or cross-app tracking.
  *(We do collect our own anonymous, non-identifying usage statistics, described above;
  you can turn them off in Profile.)*

---

## 3. Third parties that may process data

| Provider | What they process | Why |
|---|---|---|
| **OpenAI** | The full recognized text of any document you scan/upload (may include sensitive personal info), plus non-sensitive guide checklists. May be retained ~30 days for abuse monitoring; not used for training. | To generate the summary, steps, and translations |
| **Cloudflare** | Your IP address (transiently, when proxying the AI request); and the anonymous usage statistics we store (feature used, random install id, app version, timestamp — never your content) | To proxy the AI request without shipping the OpenAI key, and to store anonymous usage stats so we can improve the app |
| **Apple** | Local storage, on-device OCR, local notifications | Standard iOS app functionality (on your device) |

We are not responsible for these providers' own practices; please review their
privacy policies (OpenAI, Cloudflare, Apple).

---

## 4. Data retention

- **On-device data** stays until you delete the item or uninstall the app. You are
  in control.
- **AI requests** are processed in transit and returned; we keep no server copy.
  OpenAI's retention of API data is governed by their policy.
- **Anonymous usage statistics** are stored on our backend (Cloudflare) until we no
  longer need them for product analysis. They contain no personal identifiers and
  aren't linked to you. Turning the setting off stops new data from being sent.

---

## 5. Your choices and rights

Because your data lives on your device and we hold no server copy:
- **Delete anytime** — delete an item, or uninstall the app, to remove your data.
- **Don't want text sent to OpenAI?** Use the manual-entry option instead of
  scanning, or use the on-device sensitive guides.
- **Turn off usage statistics** — go to **Profile → Privacy** and switch off *Share
  anonymous usage data*; the app stops sending new usage events.

**California (CCPA) and EU/UK (GDPR):** we do not maintain personal data on our
servers, so there is no server-side profile to access, port, or delete — you
already control it on your device. For any questions about your rights, email us
at the address above.

---

## 6. Children

Cuevi is **not directed to children under 13** and we do not knowingly collect
data from them. (COPPA.)

---

## 7. Security

- Our AI key is held server-side in the Cloudflare Worker and is **not** shipped
  inside the app.
- The app limits how many scans you can run (per day and per month).
- Your photos and saved items are stored in the app's protected on-device storage.
- No method of transmission or storage is 100% secure, but we minimize risk by
  keeping data on-device and sending the least amount of text necessary.

---

## 8. Changes to this policy

We may update this policy as the app evolves (for example, if we add accounts,
sync, or analytics). We will revise the "Last updated" date above, and material
changes will be reflected in the app.

---

## 9. Contact

**Cuevi Support** — **support.cuevi@gmail.com**
