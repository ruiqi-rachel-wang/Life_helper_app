//  LegalContent.swift
//
//  Privacy policy + terms shown IN-APP (Profile → About & Legal). Generated from
//  legal/*.md (dev-only notes stripped; paragraphs reflowed to single lines so the
//  renderer handles inline bold/links). Keep in sync with those files.
//

import Foundation

enum LegalContent {
    static let privacyPolicy = #"""
# Privacy Policy for Tadah

**Effective date:** June 18, 2026 **Last updated:** August 15, 2026

Tadah ("Tadah", "we", "us") is an iOS app that helps you understand letters, bills, and official documents and turn them into reminders and checklists. This policy explains what data the app handles and what happens to it.

The short version: you can use Tadah **without an account**, and then your items stay on your device. Three things leave your phone: (1) the *text* of a document you scan is sent for AI processing; (2) **if you sign in**, your saved items are backed up to your account on our backend so they survive a new phone and appear on your other devices — **your scanned photos are not uploaded**; and (3) **anonymous, non-identifying usage statistics** — which features you use, never your content — are sent to a backend we run. You can turn off (3) anytime, and you can use the app signed out to avoid (2).

---

## 1. Who is responsible

Tadah is operated as a sole proprietorship based in New York, United States. Questions about this policy: **support.tadah@gmail.com**.

(If a business entity such as an LLC is formed later, this section will be updated with its legal name and address.)

---

## 2. What we collect and process

### Stored on your device
- **Your documents, photos, and scans.** Photos you take or upload are read by on-device text recognition (Apple Vision OCR). The **photo** and the **extracted details** (the item we create — title, amount, due date, steps, saved fields, notes) are stored on your device. The raw recognized text itself is **not kept** by the app — but when you scan, it **is sent to OpenAI** to produce the summary and steps (see below), so a scanned document's text does leave your device.
- **Your scanned photos stay on your device.** They are **not** uploaded to your account, even when you are signed in. If you use Tadah on a second device, your items appear there but their photos do not. You can also stop photos being saved at all under **Profile → Privacy → Save uploaded photos**.
- **Items you create** are stored on your device using Apple's database (SwiftData). If you sign in, they are **also** backed up to your account — see the next section.
- **Reminders/notifications** are scheduled locally by iOS. We do not see them.
- **Your settings** (such as your chosen explanation language) are stored on your device.

If you never sign in, we have no server copy of your items and cannot see them. Uninstalling the app removes the local data.

### Your account and backed-up items (only if you sign in)

Signing in is optional. It exists so your items survive signing out, a reinstall, or a new phone, and so they can appear on more than one device.

- **How you sign in.** Tadah uses an **email address and a password**. We store your email address on our backend — it is how your account is identified and how we send you a password-reset code. Your password itself is **never sent to us and never stored**: your phone converts it into an unreadable verifier before it leaves the device, and only that verifier is stored, so nobody at Tadah can read or recover your password. If you forget it, we email you a one-time code to set a new one.
- **What is backed up to your account.** The content of your items: **title, category, amount, due date, notes, checklist steps and their details, reminder times, and any reference numbers you save** (for example a claim, policy, or case number). **This can include personal and sensitive information**, because it is whatever your document or your own notes contain. It is stored on our backend (a Cloudflare database) with your Tadah user identifier.
- **What is NOT backed up.** Your **scanned photos**, and the raw recognized text of a document.
- **Family profiles — information about other people.** Tadah Plus lets you add profiles for family members (for example a parent), so each person's letters stay in their own list. For each profile we store **only the name you type and a colour** — no email, phone number, date of birth, or any contact details — plus the to-dos you file under that person, which can contain personal information about them. Please add only names you have a good reason to keep, and remember these are **labels inside your account, not accounts of their own**: the person named does not get a login, is not contacted by us, and anyone signed into your account can see every profile. Removing a profile deletes that person's to-dos from your account. An account can hold up to **8 profiles** and be signed in on up to **8 devices**.
- **Devices and sessions.** We store a **session record** for each signed-in device: a random session token, your Tadah user identifier, a random **device identifier**, and timestamps. That device identifier is generated separately from the one used for usage statistics, and the two are never the same value — so the statistics cannot be traced back to your account. A **free account is used on one device at a time** — signing in on another device ends the earlier device's session. Tadah Plus allows more devices.
- **We do not read your items.** They are stored so we can give them back to you; we do not use their content for advertising, profiling, or model training.
- **Signing out** removes the session from that device. Your items remain on that device and remain in your account until you delete them.

### What is sent to OpenAI when you scan
- When you **scan or upload a document**, the app recognizes its text on-device and then sends that **full recognized text to OpenAI** to generate the summary and steps. **This text can include sensitive personal information** — whatever appears on the document, such as health, financial, tax, or immigration details, your name, and account, policy, or case numbers. If you'd rather not send a document's text, use **manual entry** instead of scanning.
- **OpenAI does not receive your account.** We don't attach your name, email, or Tadah user identifier to the request — but the document's text is sent as-is, so any personal details printed on it are included. (Our own Worker does see a random **install identifier**, used only to enforce the per-device scan limit.)
- For **non-sensitive guides**, the built checklist is sent to OpenAI to reword and translate it. **Sensitive guides** (below) are never sent.
- The request goes through a **Cloudflare Worker** we run, so our OpenAI key isn't in the app. Cloudflare may briefly process your device's IP address; we don't store it.
- OpenAI processes the text and returns the result; Tadah keeps no server-side copy. Per OpenAI's API policy, API data is **not used to train their models**, but OpenAI may **retain it for up to ~30 days** for abuse monitoring.

### Sensitive GUIDES are generated on your device
The built-in **guides** we classify as sensitive — money/banking, taxes, immigration (USCIS), medical, and similar — are generated **entirely on your device** and are **never sent to OpenAI**. This applies to those guides only; it does **not** apply to **scanning**, where the recognized text is sent to OpenAI as described above, however sensitive the document is. Note that once you add a guide's checklist to your list, that item is backed up to your account like any other item if you are signed in.

### Anonymous usage statistics (sent to a backend we run)
To understand whether Tadah actually helps — for example, of the items you add, how many you come back and complete — the app sends a small amount of **anonymous, non-identifying** usage data to a backend we operate (a Cloudflare database):
- **What happened, not what's in it:** that an item was *added* (and whether from a scan, a guide, or manual entry), or *completed* (and whether on time).
- A random **install identifier** created on your device, plus the app version and the time of the event. This labels an app installation — it is **not** your name, email, account, or Apple ID, and we cannot use it to identify you. It is also **deliberately different** from the device identifier stored with your account session, so even signed in, these statistics cannot be linked back to you.
- It **never** includes your documents, photos, titles, amounts, due dates, notes, or any text from your items.

This is **first-party** data, used only to improve Tadah. It is **not** advertising, is **not** sold or shared, and is **not** used to track you across other apps or websites. You can turn it off anytime under **Profile → Privacy → Share anonymous usage data**.

### We do NOT
- We do **not** sell or rent your data.
- We do **not** use your data for advertising.
- We do **not** link your bank account, pay your bills for you, or set up autopay. (Tadah Plus subscriptions are billed by **Apple** through the App Store — we never see your card details.)
- We do **not** use third-party analytics SDKs, advertising, or cross-app tracking. *(We do collect our own anonymous, non-identifying usage statistics, described above; you can turn them off in Profile.)*

---

## 3. Third parties that may process data

| Provider | What they process | Why |
|---|---|---|
| **OpenAI** | The full recognized text of any document you scan/upload (may include sensitive personal info), plus non-sensitive guide checklists. May be retained ~30 days for abuse monitoring; not used for training. | To generate the summary, steps, and translations |
| **Cloudflare** | Your IP address (transiently, when proxying the AI request); the anonymous usage statistics we store; and — **if you sign in** — your backed-up items, your family profiles, and your session records | To proxy the AI request without shipping the OpenAI key, to store anonymous usage stats, and to host your account backup |
| **Apple** | Device storage, on-device OCR, local notifications; App Store purchases | Standard iOS functionality and subscription billing |
| **Resend** | Sends account emails (password-reset codes) — receives your email address | Delivering the code that lets you back into your account |
| **RevenueCat** | Your Tadah user identifier and your subscription status | To manage Tadah Plus subscriptions and tell the app (and our backend) whether your account is Plus |

We are not responsible for these providers' own practices; please review their privacy policies (OpenAI, Cloudflare, Apple).

---

## 4. Data retention

- **On-device data** stays until you delete the item or uninstall the app. You are in control.
- **AI requests** are processed in transit and returned; we keep no server copy. OpenAI's retention of API data is governed by their policy.
- **Backed-up items (signed-in accounts)** are kept for as long as your account exists, so we can restore them to you. Deleting an item in the app removes it from your account on the next sync. To delete the whole account and everything in it, use **Profile → your name → Delete account** in the app (see *Your choices and rights*); you can also email us if you'd rather we did it.
- **Family profiles** are kept for as long as your account exists, or until you remove the person or delete the account.
- **Session records** are kept while a device is signed in, and for a short period afterwards for security; ended sessions are marked revoked and cleaned up. Sessions also expire on their own, so a device left unused eventually has to sign in again.
- **Anonymous usage statistics** are stored on our backend (Cloudflare) until we no longer need them for product analysis. They contain no personal identifiers and aren't linked to you. Turning the setting off stops new data from being sent.

---

## 5. Your choices and rights

- **Use Tadah without an account** — signing in is optional. Signed out, nothing you save is backed up to us.
- **Delete anytime** — delete an item to remove it from this device and, on the next sync, from your account. Uninstalling removes the local copy.
- **Delete your account and everything in it, from inside the app** — **Profile → your name → Delete account**. You'll be asked to confirm with your password, and then we: erase your saved items, your family profiles, your email address, your stored password verifier and your session records from our backend on every device; and delete your subscription record from RevenueCat. It does **not** delete the copy saved on your phone — the app says so before you confirm, and you can delete those items yourself, or uninstall, whenever you want. Deletion touches two systems (our backend and our payments provider), so it happens in steps. If a step fails, the app tells you rather than pretending it worked, and tapping Delete account again is safe — retrying picks up the unfinished work and repeating a step that already succeeded does no harm. Until every step has completed, your account is not fully deleted; if you can't get it to finish, email us and we'll complete it for you.
- **Remove one family member** — Profile → Family → long-press a person → Remove. Their to-dos are deleted from the account too.
- **Sign out on this device** — Profile → Log out. This ends the session on our side straight away, rather than leaving it valid until it expires.
- **Don't want text sent to OpenAI?** Use the manual-entry option instead of scanning, or use the sensitive guides, which are generated on your device.
- **Don't want photos kept?** Switch off **Profile → Privacy → Save uploaded photos**. (Photos are never uploaded to your account either way.)
- **Turn off usage statistics** — go to **Profile → Privacy** and switch off *Share anonymous usage data*; the app stops sending new usage events.

**California (CCPA) and EU/UK (GDPR):** if you are signed in, we hold your Tadah user identifier, the items you have saved, and any family-profile names you have entered, and you have the right to access, correct, port, or delete them — email us at the address above and we will action it. We do **not** sell or share personal information, and we do not use it for advertising or cross-context behavioural profiling. If you never sign in, we hold no personal data about you at all.

---

## 6. Children

Tadah is **not directed to children under 13** and we do not knowingly collect data from them. (COPPA.)

---

## 7. Security

- Our AI key is held server-side in the Cloudflare Worker and is **not** shipped inside the app.
- The app limits how many scans and guides you can run (per day, and per 30 days).
- Your photos and saved items are stored in the app's protected device storage.
- Your password is turned into an unreadable verifier **on your phone** before it is sent, and our backend stores only a further-protected form of that — so a copy of our database would not reveal anyone's password. Your device's session token is stored in the iOS **Keychain**, and all traffic to our backend uses **HTTPS**.
- No method of transmission or storage is 100% secure, but we minimize risk by keeping photos on your device, sending the least amount of text necessary, and storing only what is needed to give your items back to you.

---

## 8. Changes to this policy

We may update this policy as the app evolves (for example, if we add accounts, sync, or analytics). We will revise the "Last updated" date above, and material changes will be reflected in the app.

---

## 9. Contact

**Tadah Support** — **support.tadah@gmail.com**

"""#

    static let terms = #"""
# Terms of Service & Disclaimers for Tadah

**Effective date:** June 18, 2026 **Last updated:** August 15, 2026

By downloading or using **Tadah** ("the app"), you agree to these Terms. If you do not agree, do not use the app.

---

## 1. What Tadah is

Tadah helps you read letters, bills, and official documents and turn them into reminders and checklists. It uses text recognition and AI to summarize documents and suggest steps, and it provides general "life-admin" guides. An optional free account backs up your items and syncs them between your devices.

---

## 2. Informational only — NOT professional advice

**Tadah is for general information only. It is not legal, tax, immigration, financial, insurance, or medical advice, and it is not a substitute for a qualified professional.**

- The summaries, steps, and guides are **general** and may not fit your specific situation.
- Rules and deadlines **vary by state and change over time**. Always confirm the specifics on the relevant **official government or provider website**, or with a licensed professional (for example, an attorney, accountant, or, for immigration, a DOJ-recognized representative or accredited organization).
- **Do not rely on Tadah alone** for decisions that affect your money, legal status, health, or immigration status.

## 3. AI can make mistakes

Tadah uses artificial intelligence to read and explain documents. **AI can misread a document or produce inaccurate or incomplete information.** Always double-check important details — amounts, dates, names, and required actions — against the original document and the official source before acting.

## 4. You are responsible for your decisions

You are solely responsible for verifying information and for any actions you take (or don't take), including meeting deadlines, making payments, and filing forms. Tadah schedules reminders to help, but you are responsible for acting on them.

---

## 5. Acceptable use

You agree not to: use the app for any unlawful purpose; upload content you have no right to use; attempt to break, overload, reverse-engineer, or abuse the app or its AI proxy; or use it to harm others.

## 6. Your content

You keep ownership of the documents and content you put into Tadah. When you scan or upload a document, its full recognized text is sent for AI processing — however sensitive the document is — as described in the Privacy Policy. (This does not apply to the built-in guides classified as sensitive, which are generated entirely on your device.) If you **sign in**, the items you save are also stored in your account on our backend so we can restore them to you and sync them between your devices; your scanned photos are not uploaded. You grant us only the limited permission needed to process that text, store your items for you, and return them to you.

## 7. No warranty

The app is provided **"as is" and "as available," without warranties of any kind**, express or implied, including fitness for a particular purpose, accuracy, or non-infringement, to the fullest extent permitted by law.

## 8. Limitation of liability

To the fullest extent permitted by law, **Tadah** will not be liable for any indirect, incidental, special, consequential, or punitive damages, or for any loss arising from missed deadlines, penalties, fees, reliance on AI output, or inaccurate information. Where liability cannot be excluded, it is limited to the amount you paid for the app (which, for the free version, is **$0**).

## 9. Third-party services

Tadah relies on Apple, OpenAI, Cloudflare, and RevenueCat. Your use is also subject to their terms. We are not responsible for third-party services.

## 10. Apple standard EULA

Unless you and we have signed a separate agreement, the app is also licensed to you under Apple's standard **Licensed Application End User License Agreement (EULA)**: <https://www.apple.com/legal/internet-services/itunes/dev/stdeula/>. Where that EULA and these Terms conflict for App Store users, the stricter user-protective term applies.

## 11. Changes

We may update these Terms as the app changes. Continued use after an update means you accept the revised Terms. We will update the "Last updated" date above.

## 12. Governing law

These Terms are governed by the laws of **New York, United States**, without regard to conflict-of-laws rules.

## 13. Contact

**Tadah Support** — **support.tadah@gmail.com**

"""#
}
