//  TaskDTO.swift
//
//  The wire form of an ActionItem — a plain Codable value keyed by the item's
//  stable `id`, used by cross-device sync (Part 3). Deliberately NOT the @Model
//  itself, so the wire format is decoupled from SwiftData and can be versioned
//  independently.
//
//  `imageData` is intentionally omitted: scanned photos are large external-storage
//  blobs. Task metadata syncs cheaply; images (if ever) go via a blob store (R2),
//  not inline JSON. Applying a pulled DTO therefore keeps whatever photo is
//  already on-device and never clobbers it with nil. The flip side, stated plainly
//  in the privacy policy: photos are device-only and are NOT backed up.
//
//  Decoding is TOLERANT (decodeIfPresent + defaults) so a record written by an
//  older app version — before some field existed — still applies cleanly.
//

import Foundation

struct TaskDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var category: ItemCategory
    var amount: Decimal?
    var currency: String
    var dueDate: Date?
    var note: String
    var status: WorkStatus
    var steps: [ChecklistStep]
    var recurrence: Recurrence?
    var seriesID: UUID?
    var recurrenceAnchorDay: Int?
    var isExample: Bool
    var createdAt: Date
    var updatedAt: Date
    var profileID: UUID?
    var summary: String
    var documentType: String
    var sender: String
    var senderShort: String
    var dueHasTime: Bool
    var siteURL: String
    var otherIDs: [DocID]
    var notes: [String]
    var source: ItemSource
    var reminderLeadHours: Int
    var reminders: [ReminderItem]
    var callOfferJSON: String
    var remindersCustomized: Bool

    // MARK: from a live item

    init(_ item: ActionItem) {
        callOfferJSON = item.callOfferJSON
        id = item.id
        title = item.title
        category = item.category
        amount = item.amount
        currency = item.currency
        dueDate = item.dueDate
        note = item.note
        status = item.status
        steps = item.steps
        recurrence = item.recurrence
        seriesID = item.seriesID
        recurrenceAnchorDay = item.recurrenceAnchorDay
        isExample = item.isExample
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        profileID = item.profileID
        summary = item.summary
        documentType = item.documentType
        sender = item.sender
        senderShort = item.senderShort
        dueHasTime = item.dueHasTime
        siteURL = item.siteURL
        otherIDs = item.otherIDs
        notes = item.notes
        source = item.source
        reminderLeadHours = item.reminderLeadHours
        reminders = item.reminders
        remindersCustomized = item.remindersCustomized
    }

    // MARK: to a live item

    // A brand-new ActionItem carrying this DTO's data (preserving id/timestamps).
    // `imageData` starts nil — the caller keeps any on-device photo separately.
    func makeItem() -> ActionItem {
        let item = ActionItem(title: title, category: category, amount: amount,
                              currency: currency, dueDate: dueDate, note: note,
                              status: status, steps: steps, recurrence: recurrence)
        apply(to: item)
        return item
    }

    // Overwrite an existing item's synced fields (used by last-writer-wins). Never
    // touches imageData, so a pulled update can't wipe a device-local photo.
    func apply(to item: ActionItem) {
        item.callOfferJSON = callOfferJSON
        item.id = id
        item.title = title
        item.category = category
        item.amount = amount
        item.currency = currency
        item.dueDate = dueDate
        item.note = note
        item.status = status
        item.steps = steps
        item.recurrence = recurrence
        item.seriesID = seriesID
        item.recurrenceAnchorDay = recurrenceAnchorDay
        item.isExample = isExample
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        item.profileID = profileID
        item.summary = summary
        item.documentType = documentType
        item.sender = sender
        item.senderShort = senderShort
        item.dueHasTime = dueHasTime
        item.siteURL = siteURL
        item.otherIDs = otherIDs
        item.notes = notes
        item.source = source
        item.reminderLeadHours = reminderLeadHours
        item.reminders = reminders
        item.remindersCustomized = remindersCustomized
    }

    // MARK: tolerant decode (older backups missing a field just default)

    enum CodingKeys: String, CodingKey {
        case callOfferJSON
        case id, title, category, amount, currency, dueDate, note, status, steps
        case recurrence, seriesID, recurrenceAnchorDay, isExample, createdAt, updatedAt, profileID
        case summary, documentType, sender, senderShort, dueHasTime, siteURL
        case otherIDs, notes, source, reminderLeadHours, reminders, remindersCustomized
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        callOfferJSON = try c.decodeIfPresent(String.self, forKey: .callOfferJSON) ?? ""
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        category = try c.decodeIfPresent(ItemCategory.self, forKey: .category) ?? .other
        amount = try c.decodeIfPresent(Decimal.self, forKey: .amount)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try c.decodeIfPresent(WorkStatus.self, forKey: .status) ?? .todo
        steps = try c.decodeIfPresent([ChecklistStep].self, forKey: .steps) ?? []
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        seriesID = try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        recurrenceAnchorDay = try c.decodeIfPresent(Int.self, forKey: .recurrenceAnchorDay)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        documentType = try c.decodeIfPresent(String.self, forKey: .documentType) ?? ""
        sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? ""
        senderShort = try c.decodeIfPresent(String.self, forKey: .senderShort) ?? ""
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        siteURL = try c.decodeIfPresent(String.self, forKey: .siteURL) ?? ""
        otherIDs = try c.decodeIfPresent([DocID].self, forKey: .otherIDs) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        source = try c.decodeIfPresent(ItemSource.self, forKey: .source) ?? .custom
        reminderLeadHours = try c.decodeIfPresent(Int.self, forKey: .reminderLeadHours) ?? 2
        reminders = try c.decodeIfPresent([ReminderItem].self, forKey: .reminders) ?? []
        remindersCustomized = try c.decodeIfPresent(Bool.self, forKey: .remindersCustomized) ?? false
    }
}

// Lets SyncService overwrite a pulled DTO's timestamp with the SERVER-VALIDATED
// one from the wire envelope, and check its identity against the validated id.
// See the note in SyncService's decodeAll: the payload is stored opaquely and can
// disagree with the envelope the server actually vetted.
protocol SyncEnvelopeBacked: Decodable {
    var id: UUID { get }
    var updatedAt: Date { get set }
}

extension TaskDTO: SyncEnvelopeBacked {}
