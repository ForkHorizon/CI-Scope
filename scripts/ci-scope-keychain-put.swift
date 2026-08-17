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
    kSecAttrAccount as String: account
]

SecItemDelete(query as CFDictionary)
var item = query
item[kSecValueData as String] = secret
let status = SecItemAdd(item as CFDictionary, nil)
guard status == errSecSuccess else {
    fputs("Keychain write failed: \(status)\n", stderr)
    exit(1)
}
