import AppKit
import OpenDirectory

/// A person's account on this Mac.
public struct MacUser: Identifiable, Hashable, @unchecked Sendable {
    public let id: String
    public let accountName: String
    public let fullName: String
    public let home: URL
    public let picture: NSImage?
    public let isCurrent: Bool

    /// Where that person's games keep their save data.
    public var savesFolder: URL {
        home.appendingPathComponent("Library/Application Support/nxnative", isDirectory: true)
    }
}

/// Reads the Mac's user accounts from Open Directory (the same list as System Settings › Users & Groups).
public enum MacUsers {
    public static func all() -> [MacUser] {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes)),
              let query = try? ODQuery(
                node: node, forRecordTypes: kODRecordTypeUsers, attribute: nil,
                matchType: ODMatchType(kODMatchAny), queryValues: nil,
                returnAttributes: [kODAttributeTypeUniqueID, kODAttributeTypeFullName,
                                   kODAttributeTypeNFSHomeDirectory, kODAttributeTypeJPEGPhoto, kODAttributeTypePicture],
                maximumResults: 0),
              let records = try? query.resultsAllowingPartial(false) as? [ODRecord]
        else { return [] }
        let current = NSUserName()
        return records.compactMap { record -> MacUser? in
            func first(_ attribute: String) -> Any? {
                (try? record.values(forAttribute: attribute))?.first
            }
            // People have IDs from 501; lower ones and "_" names are system accounts.
            guard let name = record.recordName, !name.hasPrefix("_"),
                  let uid = (first(kODAttributeTypeUniqueID) as? String).flatMap(Int.init), uid >= 501,
                  let home = first(kODAttributeTypeNFSHomeDirectory) as? String, home.hasPrefix("/Users/")
            else { return nil }
            var picture = (first(kODAttributeTypeJPEGPhoto) as? Data).flatMap(NSImage.init(data:))
            if picture == nil, let path = first(kODAttributeTypePicture) as? String {
                picture = NSImage(contentsOfFile: path)
            }
            return MacUser(id: name, accountName: name,
                           fullName: (first(kODAttributeTypeFullName) as? String) ?? name,
                           home: URL(fileURLWithPath: home, isDirectory: true),
                           picture: picture, isCurrent: name == current)
        }
        .sorted { ($0.isCurrent ? 0 : 1, $0.fullName) < ($1.isCurrent ? 0 : 1, $1.fullName) }
    }
}
