import CryptoKit
import Foundation

enum PolicyRecordError: LocalizedError {
    case malformedRecord(String)
    case malformedManifest

    var errorDescription: String? {
        switch self {
        case .malformedRecord(let field): "The server's policy record is missing \(field)."
        case .malformedManifest: ".ci-scope.json at the merge commit is not a valid manifest."
        }
    }
}

/// Builds the record POSTed to /api/ci/policy after a policy PR merges. Same rules as
/// ci-gates preflight: protected files = the old record's files plus every tree path
/// matching its patterns, re-hashed at the merge commit; deleted files drop out.
enum PolicyRecordBuilder {
    typealias Record = [String: Any]

    static func protectedPaths(current: Record, treePaths: [String]) throws -> [String] {
        let listed = try fileEntries(current).compactMap { $0["path"] as? String }
        guard let patterns = current["protected_patterns"] as? [String] else {
            throw PolicyRecordError.malformedRecord("protected_patterns")
        }
        let existing = Set(treePaths)
        let discovered = treePaths.filter { PolicyProtectedPaths.matches($0, patterns: patterns) }
        return Set(listed.filter(existing.contains) + discovered).sorted()
    }

    static func record(current: Record, mergeSHA: String, files: [String: Data]) throws -> Record {
        guard let manifest = files[".ci-scope.json"],
            let value = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
            let checks = value["checks"] as? [[String: Any]]
        else { throw PolicyRecordError.malformedManifest }
        var record = current
        for key in ["signature", "policy_digest", "approved_by", "approved_at"] {
            record.removeValue(forKey: key)  // the server sets these itself
        }
        record["approved_sha"] = mergeSHA
        record["files"] = files.keys.sorted().map { path in
            ["path": path, "sha256": sha256Hex(files[path] ?? Data())]
        }
        // Server rule (verifyMergedRecord): every check is required except slop-review.
        record["checks"] = checks.compactMap { $0["id"] as? String }.map { id in
            ["id": id, "required": id != "slop-review"] as [String: Any]
        }
        return record
    }

    static func approvedSHA(_ record: Record) -> String? {
        record["approved_sha"] as? String
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileEntries(_ record: Record) throws -> [[String: Any]] {
        guard let files = record["files"] as? [[String: Any]] else {
            throw PolicyRecordError.malformedRecord("files")
        }
        return files
    }
}
