## 2025-02-12 - Prevent Command Injection via String Interpolation
**Vulnerability:** Found unquoted string interpolation in `ShellClient.run` commands (`gh run list --repo \(config.repositorySlug)`). A malicious string could inject shell commands.
**Learning:** In Swift, string interpolations passed to bash commands without quotes can lead to command injection if the variable data can be influenced by users.
**Prevention:** Always use `quoted(value)` when interpolating string variables into shell commands. Ensure that all string input is properly escaped.

## 2024-05-24 - Validate System Command Input
**Vulnerability:** Input values used in shell commands, such as URL parameters or system output (e.g. `uid`), lack proper integer/format validation. Malicious or malformed inputs could lead to command injection.
**Learning:** Always validate that system-provided inputs, such as user IDs (`id -u`), are indeed integers before passing them to subsequent commands like `launchctl print gui/\(uid)`. For GitHub inputs, reject inputs that start with `-` or `.`. Reconstruct URLs using explicit validation components rather than raw inputs.
**Prevention:** Enforce strict type validation (`Int(uid) != nil`) and format checking (`isValidGitHubComponent`) before interpolation, and use the `quoted()` function for variable strings.

## 2025-02-12 - Secure Info.plist by Enforcing ATS
**Vulnerability:** Found lack of App Transport Security (ATS) enforcement in the generated Info.plist via Xcode configuration. Local HTTP tools or external calls could be intercepted via plaintext.
**Learning:** ATS should be explicitly configured in the Xcode project to enforce strict HTTPS connections while allowing necessary local networking.
**Prevention:** Set `INFOPLIST_KEY_NSAppTransportSecurity` to define `<key>NSAllowsArbitraryLoads</key><false/>` and `<key>NSAllowsLocalNetworking</key><true/>` when `GENERATE_INFOPLIST_FILE` is enabled.
