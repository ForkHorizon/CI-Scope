## 2025-02-12 - Prevent Command Injection via String Interpolation
**Vulnerability:** Found unquoted string interpolation in `ShellClient.run` commands (`gh run list --repo \(config.repositorySlug)`). A malicious string could inject shell commands.
**Learning:** In Swift, string interpolations passed to bash commands without quotes can lead to command injection if the variable data can be influenced by users.
**Prevention:** Always use `quoted(value)` when interpolating string variables into shell commands. Ensure that all string input is properly escaped.
## 2024-06-04 - Safely Append URL Path Components
**Vulnerability:** Path Traversal
**Learning:** `URL.appendingPathComponent` in Swift retains `../` components, allowing dynamic inputs to construct paths outside the intended base directory. Furthermore, string comparisons using `hasPrefix` must ensure directory boundaries to prevent bypasses.
**Prevention:** Use a custom `safelyAppendingPathComponent` extension that leverages `resolvingSymlinksInPath()`, prevents absolute paths (`/`), and strictly checks path prefixes to enforce directory containment.
