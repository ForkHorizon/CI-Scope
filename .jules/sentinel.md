## 2025-02-12 - Prevent Command Injection via String Interpolation
**Vulnerability:** Found unquoted string interpolation in `ShellClient.run` commands (`gh run list --repo \(config.repositorySlug)`). A malicious string could inject shell commands.
**Learning:** In Swift, string interpolations passed to bash commands without quotes can lead to command injection if the variable data can be influenced by users.
**Prevention:** Always use `quoted(value)` when interpolating string variables into shell commands. Ensure that all string input is properly escaped.

## 2024-06-04 - Safely Append URL Path Components
**Vulnerability:** Path Traversal
**Learning:** `URL.appendingPathComponent` in Swift retains `../` components, allowing dynamic inputs to construct paths outside the intended base directory. Furthermore, string comparisons using `hasPrefix` must ensure directory boundaries to prevent bypasses.
**Prevention:** Use a custom `safelyAppendingPathComponent` extension that leverages `resolvingSymlinksInPath()`, prevents absolute paths (`/`), and strictly checks path prefixes to enforce directory containment.

## 2024-05-18 - [Add strict validation to repository URL inputs]
**Vulnerability:** Weak string parsing using prefix matching and string splitting allowed arbitrary characters into the repository string variables.
**Learning:** Manual string manipulation is prone to bugs and bypasses. Regular expressions are better suited for strict input validation, specifically for specific URL formats and usernames constraints.
**Prevention:** Always use strict regular expressions with anchor tags (`^` and `$`) and strict character classes when parsing and validating potentially malicious input.

## 2024-05-24 - Validate System Command Input
**Vulnerability:** Input values used in shell commands, such as URL parameters or system output (e.g. `uid`), lack proper integer/format validation. Malicious or malformed inputs could lead to command injection.
**Learning:** Always validate that system-provided inputs, such as user IDs (`id -u`), are indeed integers before passing them to subsequent commands like `launchctl print gui/\(uid)`. For GitHub inputs, reject inputs that start with `-` or `.`. Reconstruct URLs using explicit validation components rather than raw inputs.
**Prevention:** Enforce strict type validation (`Int(uid) != nil`) and format checking (`isValidGitHubComponent`) before interpolation, and use the `quoted()` function for variable strings.

## 2025-02-12 - Secure Info.plist by Enforcing ATS
**Vulnerability:** Found lack of App Transport Security (ATS) enforcement in the generated Info.plist via Xcode configuration. Local HTTP tools or external calls could be intercepted via plaintext.
**Learning:** ATS should be explicitly configured in the Xcode project to enforce strict HTTPS connections while allowing necessary local networking.
**Prevention:** Set `INFOPLIST_KEY_NSAppTransportSecurity` to define `<key>NSAllowsArbitraryLoads</key><false/>` and `<key>NSAllowsLocalNetworking</key><true/>` when `GENERATE_INFOPLIST_FILE` is enabled.

## 2025-02-14 - Prevent Terminal Injection
**Vulnerability:** ShellClient command outputs directly rendered in UI without sanitizing ANSI control sequences.
**Learning:** Raw terminal outputs can contain malicious ANSI escape sequences that manipulate logs or inject terminal commands when rendered.
**Prevention:** Use regex replacement to strip out CSI, OSC sequences and raw ESC characters from shell outputs.
