//
//  Syncable.swift
//  SchrammScape Calendar
//
//  Common sync metadata for models mirrored to Supabase. New records are
//  born dirty; edits call markDirty() so the SyncEngine pushes them.
//

import Foundation

protocol Syncable: AnyObject {
    var remoteID: UUID { get set }
    var syncedAt: Date? { get set }
    var isDirty: Bool { get set }
}

extension Syncable {
    func markDirty() {
        isDirty = true
    }
}

extension Customer: Syncable {}
extension WorkRecord: Syncable {}
extension ServiceItem: Syncable {}
extension JobType: Syncable {}
extension Invoice: Syncable {}
extension MileageEntry: Syncable {}
