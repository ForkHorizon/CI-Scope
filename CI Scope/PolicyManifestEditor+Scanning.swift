import Foundation

/// String-aware scanning helpers for PolicyManifestEditor: braces inside JSON
/// strings never count, so a value like "{{x}}" cannot throw off the matching.
extension PolicyManifestEditor {
    static func enclosingOpen(_ chars: [Character], before index: Int) throws -> Int {
        var stack: [Int] = []
        var inString = false
        var escaped = false
        for position in 0..<index {
            let character = chars[position]
            if inString {
                (inString, escaped) = stringStep(character, escaped: escaped)
            } else if character == "\"" {
                inString = true
            } else if character == "{" || character == "[" {
                stack.append(position)
            } else if character == "}" || character == "]" {
                _ = stack.popLast()
            }
        }
        guard let open = stack.last, chars[open] == "{" else {
            throw PolicyManifestError.invalid("The manifest check list could not be parsed.")
        }
        return open
    }

    static func matchingClose(_ chars: [Character], from open: Int, open opener: Character, close closer: Character)
        throws -> Int
    {
        var depth = 0
        var inString = false
        var escaped = false
        for position in open..<chars.count {
            let character = chars[position]
            if inString {
                (inString, escaped) = stringStep(character, escaped: escaped)
                continue
            }
            if character == "\"" { inString = true }
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 { return position }
            }
        }
        throw PolicyManifestError.invalid("The manifest has an unbalanced \(opener).")
    }

    static func previousNonSpace(_ chars: [Character], before index: Int) -> Int? {
        var position = index - 1
        while position >= 0, chars[position].isWhitespace { position -= 1 }
        return position >= 0 ? position : nil
    }

    static func nextNonSpace(_ chars: [Character], from index: Int) -> Int? {
        var position = index
        while position < chars.count, chars[position].isWhitespace { position += 1 }
        return position < chars.count ? position : nil
    }

    /// Indentation of the first element after `[`, reused for an appended check.
    static func elementIndent(_ chars: [Character], after open: Int) -> String? {
        guard let first = nextNonSpace(chars, from: open + 1), chars[first] == "{" else { return nil }
        var start = first
        while start > 0, chars[start - 1] == " " || chars[start - 1] == "\t" { start -= 1 }
        return String(chars[start..<first])
    }

    private static func stringStep(_ character: Character, escaped: Bool) -> (inString: Bool, escaped: Bool) {
        if escaped { return (true, false) }
        if character == "\\" { return (true, true) }
        return (character != "\"", false)
    }
}
