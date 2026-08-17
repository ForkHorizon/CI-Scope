# Agent staging bootstrap

The runnable Agent command is `go run ./cmd/ci-scope-agent` from this directory.
It fails closed unless all required staging configuration is present, acquires
the local owner lock, optionally consumes a one-time enrollment token, opens a
fenced server session, starts the `0600` Unix socket, sends heartbeats, and
closes the session on SIGTERM/SIGINT.

Required environment:

```text
CI_SCOPE_CONTROL_PLANE_URL=https://<control-plane-host>
CI_SCOPE_CREDENTIAL_PROOF=<device-credential-secret>
CI_SCOPE_V2_SHADOW_TOKEN=<staging-shadow-token>
CI_SCOPE_MACHINE_ID=<stable-machine-id>
CI_SCOPE_BOOT_ID=<current-boot-id>
CI_SCOPE_AGENT_INSTANCE_ID=<unique-agent-instance>
CI_SCOPE_CREDENTIAL_ID=<enrolled-credential-id>
CI_SCOPE_SESSION_REQUEST_ID=<unique-open-request-id>
CI_SCOPE_SOCKET_PATH=/var/run/ci-scope/agent.sock
CI_SCOPE_STATE_ROOT=/var/lib/ci-scope
```

`CI_SCOPE_CONTROL_PLANE_URL` is transport-neutral. For the VPS migration it
must point to the VPS HTTPS hostname; no Worker-specific URL or header is
required.

For production launchd, `CI_SCOPE_CREDENTIAL_PROOF` and
`CI_SCOPE_V2_SHADOW_TOKEN` may be omitted. The Agent then reads the device
credential from the macOS Keychain account named by `CI_SCOPE_CREDENTIAL_ID`
and the shadow token from account `shadow-token`, using service
`com.forkhorizon.ci-scope.agent`. Override the service or shadow-token account
with `CI_SCOPE_KEYCHAIN_SERVICE` or
`CI_SCOPE_V2_SHADOW_TOKEN_KEYCHAIN_ACCOUNT`. Do not put either secret in a
launchd plist, environment file, argument list, or Agent state directory.

Optional one-time enrollment configuration must be supplied as a complete set:

```text
CI_SCOPE_ENROLLMENT_TOKEN=<issuer-created-token>
CI_SCOPE_DEVICE_SECRET=<new-device-secret>
CI_SCOPE_ENROLLMENT_ISSUER=<server-enrollment-issuer-secret>
CI_SCOPE_POOL_IDENTITY=<configured-pool-identity>
```

`CI_SCOPE_DEVICE_SECRET`, enrollment tokens, and issuer secrets are accepted
only for the staging bootstrap seam. Production should source the credential
from Keychain/OS secret storage and must not persist these values in process
arguments, logs, or the Agent state directory.

Optional timing controls are `CI_SCOPE_HEARTBEAT_INTERVAL_MS` (1 second to 24
hours) and `CI_SCOPE_HTTP_TIMEOUT_MS` (100 milliseconds to 5 minutes).

The macOS launchd template and renderer are in
`watchdog/launchd/com.forkhorizon.ci-scope.agent.plist.tmpl` and
`watchdog/launchd/render-agent-plist.sh`. The renderer writes only non-secret
configuration into the plist; the Agent reads both production secrets from
Keychain at runtime. It does not install or start the service automatically.

The watchdog package currently has no executable or plist renderer. Do not
load `com.forkhorizon.ci-scope.watchdog.plist.tmpl` as a production service.
Once a signed watchdog binary and renderer exist, validate the rendered plist
with `watchdog/launchd/validate-watchdog-plist.sh <watchdog-path> <plist>`
before loading it; the guard rejects missing binaries and unresolved template
placeholders.

When a live session is open, the Agent atomically publishes
`$CI_SCOPE_STATE_ROOT/agent-session.json` with mode `0600`. It contains only
machine/session/fencing/socket identifiers, so the Swift app can discover the
current session without copying values into UserDefaults. The socket remains
the authority and rejects stale or forged envelopes.

With an explicit runner executable, workspace root, and runner script
(`CI_SCOPE_RUNNER_SCRIPT`), the Agent performs fenced JIT
prepare/start/observe/stop/release. The script must be an executable,
non-symlink path inside the configured workspace root; this is important when
multiple runner installations share a parent directory. It remains
fail-closed when any runner path is missing or invalid. Production GitHub JIT
is intentionally kept disabled until a real canary runner is installed and
rollback evidence is complete.
