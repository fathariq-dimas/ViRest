import Foundation
import SwiftData

@MainActor
final class SwiftDataKeyValueStore {
    private let modelContainer: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<KeyValueRecord>(predicate: #Predicate { $0.key == key })

        guard let record = try context.fetch(descriptor).first else {
            return nil
        }

        do {
            return try decoder.decode(T.self, from: record.payload)
        } catch {
            throw AppError.persistence("Failed to decode value for key \(key): \(error.localizedDescription)")
        }
    }

    func save<T: Encodable>(_ value: T, forKey key: String) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<KeyValueRecord>(predicate: #Predicate { $0.key == key })

        let payload: Data
        do {
            payload = try encoder.encode(value)
        } catch {
            throw AppError.persistence("Failed to encode value for key \(key): \(error.localizedDescription)")
        }

        if let existing = try context.fetch(descriptor).first {
            existing.payload = payload
            existing.updatedAt = Date()
        } else {
            context.insert(KeyValueRecord(key: key, payload: payload))
        }

        do {
            try context.save()
        } catch {
            throw AppError.persistence("Failed to save value for key \(key): \(error.localizedDescription)")
        }
    }

    func remove(_ key: String) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<KeyValueRecord>(predicate: #Predicate { $0.key == key })

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            try context.save()
        }
    }

    func removeAll() throws {
        let context = ModelContext(modelContainer)
        let records = try context.fetch(FetchDescriptor<KeyValueRecord>())
        for record in records {
            context.delete(record)
        }
        try context.save()
    }
}
