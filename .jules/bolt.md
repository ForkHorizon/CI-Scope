## 2024-05-14 - NSRegularExpression Precompilation
**Learning:** `String.replacingOccurrences(of:with:options: .regularExpression)` re-compiles the Regex on *every single invocation*, which is extremely expensive in hot paths (like `ShellClient.sanitizeOutput`, which runs constantly during polling). Pre-compiling static `NSRegularExpression`s avoids this significant overhead.
**Action:** When regular expressions are used in frequently-executed methods or loops, always pre-compile them into static `NSRegularExpression` variables.
