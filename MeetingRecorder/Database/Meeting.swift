import Foundation
import GRDB

// MARK: - Meeting Model

struct Meeting: Identifiable, Equatable {
    var id: Int64?
    var title: String
    var date: Date
    var duration: TimeInterval      // seconds
    var transcript: String          // formatted transcript
    var rawTranscript: String?      // raw Whisper output before any processing
    var audioPath: String?          // nil after deletion (always nil in final state)
    var createdAt: Date
    var updatedAt: Date

    init(
        id: Int64? = nil,
        title: String = "",
        date: Date = Date(),
        duration: TimeInterval = 0,
        transcript: String = "",
        rawTranscript: String? = nil,
        audioPath: String? = nil
    ) {
        self.id = id
        self.title = title.isEmpty ? Meeting.defaultTitle(for: date) : title
        self.date = date
        self.duration = duration
        self.transcript = transcript
        self.rawTranscript = rawTranscript
        self.audioPath = audioPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "Meeting — \(formatter.string(from: date))"
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes == 0 {
            return "\(seconds)s"
        } else if seconds == 0 {
            return "\(minutes)m"
        } else {
            return "\(minutes)m \(seconds)s"
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - GRDB Conformance

extension Meeting: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "meetings"

    enum Columns: String, ColumnExpression {
        case id, title, date, duration, transcript, rawTranscript, audioPath, createdAt, updatedAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        title = row[Columns.title]
        date = row[Columns.date]
        duration = row[Columns.duration]
        transcript = row[Columns.transcript]
        rawTranscript = row[Columns.rawTranscript]
        audioPath = row[Columns.audioPath]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.date] = date
        container[Columns.duration] = duration
        container[Columns.transcript] = transcript
        container[Columns.rawTranscript] = rawTranscript
        container[Columns.audioPath] = audioPath
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
