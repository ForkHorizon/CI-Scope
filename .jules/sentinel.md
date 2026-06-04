## 2025-02-12 - Prevent Command Injection via String Interpolation
**Vulnerability:** Found unquoted string interpolation in `ShellClient.run` commands (`gh run list --repo \(config.repositorySlug)`). A malicious string could inject shell commands.
**Learning:** In Swift, string interpolations passed to bash commands without quotes can lead to command injection if the variable data can be influenced by users.
**Prevention:** Always use `quoted(value)` when interpolating string variables into shell commands. Ensure that all string input is properly escaped.
## 2025-02-14 - Prevent Terminal Injection
**Vulnerability:** ShellClient command outputs directly rendered in UI without sanitizing ANSI control sequences.
**Learning:** Raw terminal outputs can contain malicious ANSI escape sequences that manipulate logs or inject terminal commands when rendered.
**Prevention:** Use regex replacement to strip out CSI, OSC sequences and raw ESC characters from shell outputs.
