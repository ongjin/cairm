# SSH password auth + Keychain-backed reconnect

Date: 2026-04-23
Scope: third SSH auth mode alongside Agent and Key file. Password stored in macOS Keychain keyed by the ssh_config nickname, and on silent reconnect from the sidebar the password is pulled without re-showing the sheet.

Reference pattern user provided:
```
{ host: "aible.kro.kr", port: "222", user: "khs", keychain_account: "ssh-aible" }
```
Mapping: `keychain_account` → `ssh-pw:<nickname>` entry in macOS Keychain (service `com.cairn.ssh.password`).

## Architecture

### Rust (`cairn-ssh`)

`auth.rs`:
- `AuthMethod::Password(String)` variant — carries the password value to attempt directly.
- `PasswordResolver` trait — `async fn resolve(&self, host: &str, user: &str) -> Option<String>`. Called on retry when a preset password fails, or when no preset was provided.
- `format_tried` renders `Password(_)` as `"password"` — never leaks the value.

`types.rs`:
- `ResolvedConfig.password: Option<String>` — set by Swift via `ConnectSpecOverrides` when the user chose Password mode, or when a stored keychain value is pulled on reconnect.

`pool.rs`:
- `dial()` gains a `password: Arc<dyn PasswordResolver>` arg (parallel to `passphrase`).
- `planned_methods(resolved)` — when `resolved.password.is_some()`, push `AuthMethod::Password(value)` to the **front** of the vec so it is tried before Agent/Key. Without an override the vec is unchanged (no password attempts).
- New `try_password_auth(handle, user, password, resolver)`:
  1. `handle.authenticate_password(user, password)` — primary path.
  2. If the server requires it, `handle.authenticate_keyboard_interactive_start/respond` with the same password as the first response.
  3. On rejection, call `resolver.resolve(host, user)` up to 3 times (matches key-passphrase retry budget).

### FFI (`cairn-ffi/src/ssh.rs`)

- `extern "Swift"` adds `PasswordCallback { ask_password(host: String, user: String) -> Option<String> }`.
- `ssh_pool_connect(..., password_cb: PasswordCallback)` — new trailing arg.
- `ConnectSpecBridge.password: String` — empty string = unset (matches the existing empty-string convention for optional fields).
- New `SwiftPasswordAdapter` implements `PasswordResolver`, shuttling calls to the Swift closure.

### Swift

`Services/KeychainPasswordStore.swift` (new):
- Mirror of `KeychainPassphraseStore`: service `com.cairn.ssh.password`, account `ssh-pw:<alias>`.
- `load(for:) -> String?`, `save(_, for:)`, `delete(for:)`.
- Alias resolution: ssh_config nickname when present; otherwise `user@host:port`.

`Views/Connect/ConnectSheetModel.swift`:
- `enum AuthMode { agent, keyFile, password }`.
- `var password: String = ""`.

`Views/Connect/ConnectSheetView.swift`:
- Picker gains a "Password" tag.
- `authMode == .password` reveals a `SecureField("Password", text: $model.password)`.

`Services/SshPoolService.swift` (extend):
- `ConnectSpecOverrides.password: String?` pass-through to the FFI bridge.
- `SwiftPasswordAdapter` that presents an NSAlert with SecureField on retry; returns nil on cancel (connect fails).

`ContentView.swift performConnect`:
- On success, if `authMode == .password && saveToConfig && !nickname.isEmpty`, call `KeychainPasswordStore.save(model.password, for: model.nickname)`.

`Views/Sidebar/SidebarView.swift connectHost(alias)`:
- Before opening the ConnectSheet, probe `KeychainPasswordStore.load(for: alias)`.
- If non-nil: call `app.ssh.connect(hostAlias: alias, overrides: ConnectSpecOverrides(password: stored, ...))` directly and open the remote tab on success. **No sheet shown.**
- On connection failure (including wrong stored password), fall through to the existing sheet-based path with the nickname pre-filled.

### Security / UX

- `kSecAttrAccessibleWhenUnlocked` — same posture as the existing passphrase store.
- Password never logged; Rust `SshError::Russh` strings come from russh's `Debug`, which does not include the secret. Verify with a grep of the call sites.
- Sheet retry on wrong password: inline `model.error = "Authentication failed"`; user edits password and retries without reopening.

## Files touched

New:
- `apps/Sources/Services/KeychainPasswordStore.swift`

Modified:
- `crates/cairn-ssh/src/auth.rs`
- `crates/cairn-ssh/src/pool.rs`
- `crates/cairn-ssh/src/types.rs`
- `crates/cairn-ffi/src/ssh.rs`
- `apps/Sources/Views/Connect/ConnectSheetModel.swift`
- `apps/Sources/Views/Connect/ConnectSheetView.swift`
- `apps/Sources/Services/SshPoolService.swift`
- `apps/Sources/ContentView.swift`
- `apps/Sources/Views/Sidebar/SidebarView.swift`

## Verification

1. **New host via sheet.** Enter user@host, pick Password, enter password, tick "Save to ~/.ssh/config as:" with a nickname → connects; Keychain Access shows `com.cairn.ssh.password` / `ssh-pw:<nickname>`.
2. **Silent reconnect.** Click the saved host in the sidebar → remote tab opens without a sheet appearing. Disconnect and re-click — still silent.
3. **Stale password.** Change password on the server. Click the saved host → silent attempt fails, sheet opens with nickname pre-filled and an error message. Enter new password → connects and overwrites Keychain entry.
4. **Keyboard-interactive-only server.** A server configured with `PasswordAuthentication no`, `KbdInteractiveAuthentication yes` — connect with Password mode still succeeds (fallback path).
5. **Cancel on retry.** During an in-flight retry, dismissing the NSAlert returns nil and surfaces "Authentication failed" in the sheet without crashing.
