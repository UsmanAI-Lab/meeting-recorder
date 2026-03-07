import Foundation
import GRDB

// MARK: - AppDatabase

/// The single source of truth for all persistent data.
/// Access via `AppDatabase.shared`.
final class AppDatabase {

    // MARK: - Shared instance

    static let shared: AppDatabase = {
        do {
            let dbPath = AppDatabase.databaseURL.path
            let db = try AppDatabase(path: dbPath)
            return db
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    // MARK: - Storage

    private let dbWriter: DatabaseWriter

    // MARK: - Database URL

    static var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MeetingRecorder")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("meetings.db")
    }

    // MARK: - Initializer

    init(path: String) throws {
        dbWriter = try DatabasePool(path: path)
        try migrator.migrate(dbWriter)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1: initial schema
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: Meeting.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("transcript", .text).notNull().defaults(to: "")
                t.column("rawTranscript", .text)
                t.column("audioPath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Index for sorting by date
            try db.create(index: "meetings_date_idx", on: Meeting.databaseTableName, columns: ["date"])
        }

        return migrator
    }
}

// MARK: - Write Operations

extension AppDatabase {

    /// Insert a new meeting and return it with its assigned ID.
    func saveMeeting(_ meeting: inout Meeting) throws {
        try dbWriter.write { db in
            try meeting.save(db)
        }
    }

    /// Update an existing meeting.
    func updateMeeting(_ meeting: Meeting) throws {
        try dbWriter.write { db in
            var m = meeting
            m.updatedAt = Date()
            try m.update(db)
        }
    }

    /// Delete a meeting by ID.
    func deleteMeeting(id: Int64) throws {
        try dbWriter.write { db in
            _ = try Meeting.deleteOne(db, key: id)
        }
    }

    /// Update just the title of a meeting.
    func renameMeeting(id: Int64, title: String) throws {
        try dbWriter.write { db in
            if var meeting = try Meeting.fetchOne(db, key: id) {
                meeting.title = title
                meeting.updatedAt = Date()
                try meeting.update(db)
            }
        }
    }
}

// MARK: - Read Operations

extension AppDatabase {

    /// Fetch all meetings sorted by date descending.
    func fetchAllMeetings() throws -> [Meeting] {
        try dbWriter.read { db in
            try Meeting.order(Meeting.Columns.date.desc).fetchAll(db)
        }
    }

    /// Fetch a single meeting by ID.
    func fetchMeeting(id: Int64) throws -> Meeting? {
        try dbWriter.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    /// Search meetings by transcript or title content.
    func searchMeetings(query: String) throws -> [Meeting] {
        try dbWriter.read { db in
            let pattern = "%\(query)%"
            return try Meeting
                .filter(Meeting.Columns.transcript.like(pattern) ||
                        Meeting.Columns.title.like(pattern))
                .order(Meeting.Columns.date.desc)
                .fetchAll(db)
        }
    }

    /// Observe all meetings for reactive UI updates.
    func meetingsObservation() -> ValueObservation<ValueReducers.Fetch<[Meeting]>> {
        ValueObservation.tracking { db in
            try Meeting.order(Meeting.Columns.date.desc).fetchAll(db)
        }
    }
}
