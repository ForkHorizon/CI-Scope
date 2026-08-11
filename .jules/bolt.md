## 2024-06-13 - Native OS Functions over Shell Commands
**Learning:** Invoking shell commands (e.g. `id -u`) via `Process` or `ShellClient` is a major performance overhead, especially when performed frequently in background or periodic tasks.
**Action:** Always prefer native OS/Foundation functions like `geteuid()` or `FileManager` operations over shell equivalents for immediate, synchronous execution.
