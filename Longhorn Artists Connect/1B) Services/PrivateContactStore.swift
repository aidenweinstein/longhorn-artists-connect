//
//  PrivateContactStore.swift
//  Longhorn Artists Connect
//
//  Contact details that must never reach the public database. Profiles live in
//  CloudKit's public database, which every app user can read, so an alumni's
//  phone number goes to the user's *private* database instead — readable only
//  by their own Apple ID, and restored with their profile on a new device.
//

import CloudKit

enum PrivateContactStore {
    private static let recordID = CKRecord.ID(recordName: "AccountContact")
    private static let recordType = "AccountContact"
    private static var database: CKDatabase { CKContainer.default().privateCloudDatabase }

    static func save(phoneNumber: String) async {
        do {
            let record = (try? await database.record(for: recordID))
                ?? CKRecord(recordType: recordType, recordID: recordID)
            record["phoneNumber"] = phoneNumber as CKRecordValue
            _ = try await database.save(record)
        } catch {
            // Non-fatal: the number is still saved on this device.
            print("⚠️ Couldn't save contact details privately: \(error.localizedDescription)")
        }
    }

    static func fetchPhoneNumber() async -> String? {
        let record = try? await database.record(for: recordID)
        return (record?["phoneNumber"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
