## 2025-02-12 - Prevent Command Injection via String Interpolation
**Vulnerability:** Found unquoted string interpolation in `ShellClient.run` commands (`gh run list --repo \(config.repositorySlug)`). A malicious string could inject shell commands.
**Learning:** In Swift, string interpolations passed to bash commands without quotes can lead to command injection if the variable data can be influenced by users.
**Prevention:** Always use `quoted(value)` when interpolating string variables into shell commands. Ensure that all string input is properly escaped.
## 2024-05-18 - [Add strict validation to repository URL inputs]
**Vulnerability:** Weak string parsing using prefix matching and string splitting allowed arbitrary characters into the repository string variables.
**Learning:** Manual string manipulation is prone to bugs and bypasses. Regular expressions are better suited for strict input validation, specifically for specific URL formats and usernames constraints.
**Prevention:** Always use strict regular expressions with anchor tags (`^` and `$`) and strict character classes when parsing and validating potentially malicious input.
