import Darwin
import Foundation
import Security

guard CommandLine.arguments.count == 3 else {
    fputs("usage: ci-scope-keychain-put <service> <account>\n", stderr)
    exit(2)
}

let service = CommandLine.arguments[1]
let account = CommandLine.arguments[2]
let secret = FileHandle.standardInput.readDataToEndOfFile()
guard !service.isEmpty, !account.isEmpty, !secret.isEmpty else {
    fputs("service, account, and a non-empty secret are required\n", stderr)
    exit(2)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
]

// Add first, since that's the common case (item doesn't exist yet). Only an
// existing item falls back to update — a blind delete-then-add ignored the
// delete's result, so an item the ad-hoc-signed helper wasn't the original
// ACL owner of (e.g. one a human added via /usr/bin/security) could survive
// the delete and then fail the add with errSecDuplicateItem.
var item = query
item[kSecValueData as String] = secret
let addStatus = SecItemAdd(item as CFDictionary, nil)
if addStatus == errSecDuplicateItem {
    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
    guard updateStatus == errSecSuccess else {
        fputs("Keychain update failed: \(updateStatus)\n", stderr)
        exit(1)
    }
} else if addStatus != errSecSuccess {
    fputs("Keychain write failed: \(addStatus)\n", stderr)
    exit(1)
}
