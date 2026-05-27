# Research: auto-captive-portal (ACP)

> Architecture study of a well-engineered Rust captive portal daemon with cross-platform support, OS keychain integration, and hybrid network monitoring.

---

## 1. Overview

| Field | Value |
|-------|-------|
| **Repository** | https://github.com/AmanSikarwar/auto-captive-portal |
| **Author** | AmanSikarwar |
| **License** | MIT |
| **Language** | Rust (edition 2024) |
| **Current Version** | 0.8.1 (as of March 2026) |
| **Target Portal** | IIT Mandi (single institution), but architecturally generalizable |
| **Platforms** | macOS (x86_64, ARM64), Linux (x86_64, ARM64), Windows (x86_64) |
| **Binary Size** | Static binaries per platform, distributed via GitHub Releases |

### Source Structure

```
src/
  main.rs            CLI entry point with clap subcommands (setup, status, health, run, logout, init)
  daemon.rs          Core daemon loop — hybrid monitoring (netwatcher + adaptive polling)
  captive_portal.rs  Portal detection (HTTP 204 check) and DOM-based authentication
  config.rs          TOML configuration with defaults, env var overrides
  credentials.rs     OS keychain abstraction via keyring-rs
  service.rs         Platform-specific service management (LaunchAgent, systemd, Windows Service)
  state.rs           Persistent JSON state (timestamps, last portal URL)
  notifications.rs   Desktop notifications via notify-rust
  logging.rs         Structured logging via tracing with log rotation
  error.rs           Error types (keyring, network, IO, login, service)
```

### Key Dependencies

| Crate | Version | Purpose |
|-------|---------|---------|
| `netwatcher` | 0.4.1 | Real-time network interface change detection (from Mullvad) |
| `keyring` | 3.6.3 | Cross-platform OS keychain access |
| `scraper` | 0.26.0 | HTML DOM parsing with CSS selectors |
| `reqwest` | 0.13.2 | HTTP client (TLS, form POST) |
| `tokio` | 1.50.0 | Async runtime |
| `clap` | 4.6.0 | CLI argument parsing (derive) |
| `tracing` + `tracing-subscriber` | 0.1.44 / 0.3 | Structured logging |
| `notify-rust` | 4.12.0 | Desktop notifications |
| `indicatif` | 0.18 | CLI progress spinners |
| `toml` + `serde` | 1.0.7 / 1.0.228 | Configuration serialization |
| `windows-service` | 0.8 | Windows Service API (cfg-gated) |

---

## 2. Hybrid Monitoring Architecture

This is the most architecturally interesting aspect of ACP. It combines two monitoring strategies that complement each other.

### 2.1 Real-Time Network Event Detection (netwatcher)

The `netwatcher` crate (maintained by Mullvad, the VPN company) provides OS-level network interface change notifications:

```rust
let _watcher_handle = netwatcher::watch_interfaces(move |update| {
    let has_relevant_change = !update.diff.added.is_empty()
        || update.diff.modified.values()
            .any(|d| !d.addrs_added.is_empty());

    if has_relevant_change {
        tx.try_send(()).ok();  // signal daemon loop
    }
});
```

**What it detects:**
- New network interfaces appearing (Wi-Fi connect, ethernet plug-in)
- IP address assignments on existing interfaces
- VPN tunnel creation/destruction

**What it ignores:**
- Interface removal (losing connectivity doesn't help portal login)
- Modifications without new IP addresses (address removals, metric changes)

**Key design choice:** A 3-second debounce delay after receiving a network change signal before triggering the portal check. This allows DHCP and routing to stabilize.

### 2.2 Adaptive Polling with Exponential Backoff

The daemon runs a continuous polling loop with dynamically adjusted intervals:

| State | Interval | Rationale |
|-------|----------|-----------|
| Portal detected, login needed | `min_delay_secs` (default: 10s) | Aggressive — portal is blocking |
| Successfully logged in | `max_delay_secs` (default: 1800s = 30min) | Relaxed — periodic health check |
| No portal found (gradual decay) | Halves current interval, floors at `min_delay_secs` | Decays from max to min gradually |
| Login failed | `min_delay_secs` | Aggressive retry after failure |

**Backoff decay logic:**
```rust
Ok(false) => {  // no portal found
    let current_secs = sleep_duration.as_secs();
    let next_secs = (current_secs / 2).max(min_delay.as_secs());
    sleep_duration = Duration::from_secs(next_secs);
}
```

This is a half-life decay (not exponential growth). After a successful login at 1800s, the sequence when no portal is found goes: 900 → 450 → 225 → 112 → 56 → 28 → 14 → 10 (minimum). This gives ~7 checks over ~27 minutes to catch new portals before settling at the minimum.

### 2.3 The tokio::select! Loop

The hybrid design is implemented as a single `tokio::select!` with biased priority:

```rust
tokio::select! {
    biased;

    // Priority 1: Graceful shutdown (SIGTERM/SIGINT)
    result = shutdown_signal() => { break; }

    // Priority 2: Network change events (immediate response)
    Some(_) = rx.recv() => {
        tokio::time::sleep(Duration::from_secs(3)).await; // debounce
        // check and login, adjust sleep_duration
    }

    // Priority 3: Periodic polling (adaptive timer)
    _ = tokio::time::sleep(sleep_duration) => {
        // check and login, adjust sleep_duration
    }
}
```

**Why this works well:**
- Network events interrupt sleep immediately → responsive to new connections
- Polling catches portals that appear without network events (redirect changes)
- Biased select ensures shutdown isn't blocked by polling
- `mpsc::channel` with capacity 10 provides backpressure for rapid network changes

---

## 3. Credential Management

### 3.1 OS Keychain Integration

ACP uses the `keyring-rs` crate with platform-specific feature flags:

```toml
keyring = { version = "3.6.3", features = [
    "apple-native",        # macOS Keychain via Security.framework
    "sync-secret-service", # Linux Secret Service (GNOME Keyring, KWallet)
    "windows-native",      # Windows Credential Manager
] }
```

**Per-platform behavior:**

| Platform | Backend | Storage Location |
|----------|---------|-----------------|
| macOS | Security framework (native) | Login Keychain |
| Linux | D-Bus Secret Service API | GNOME Keyring / KWallet |
| Windows | Windows Credential Manager API | Credential Manager store |

### 3.2 Credential API Design

Simple and clean — three functions:

```rust
pub fn store_credentials(username: &str, password: &str) -> Result<()>
pub fn get_credentials() -> Result<(String, String)>
pub fn clear_credentials() -> Result<()>
```

**Key details:**
- Username and password stored as separate keyring entries (`ldap_username`, `ldap_password`)
- Service name is platform-specific: `com.user.acp` on macOS, `acp` on Linux/Windows
- No plaintext files involved — credentials never touch the filesystem
- Uses OS-level encryption automatically

### 3.3 Credential Update Workflow

The `update-credentials` command validates new credentials before storing:
1. Fetches current username from keychain (confirms credentials exist)
2. Prompts for new username/password via `console::Term::read_secure_line()`
3. Detects captive portal to test credentials live
4. Attempts login with new credentials
5. If validation fails, asks user whether to store anyway
6. If no portal detected, stores with warning

---

## 4. Portal Detection and Authentication

### 4.1 HTTP 204 Check Mechanism

The standard captive portal detection technique:

1. Send GET to `http://clients3.google.com/generate_204` (configurable)
2. **204 No Content** → Internet is accessible, no portal
3. **200 OK** → Captive portal intercepted the request, body contains redirect page
4. **Error** → Network unreachable or other failure

The check is retried up to 2 times with 1-second delays between attempts.

### 4.2 DOM Parsing for Portal URL and Magic Value

ACP uses the `scraper` crate (built on `html5ever` + `selectors`) to parse HTML responses without a full browser engine.

**Step 1: Extract portal redirect URL from JavaScript**

```rust
fn extract_captive_portal_url(html: &str) -> Option<String> {
    let document = Html::parse_document(html);
    let selector = Selector::parse("script").ok()?;
    for element in document.select(&selector) {
        let script_text: String = element.text().collect();
        if let Some(start) = script_text.find("window.location=\"") {
            // Extract URL between quotes
        }
    }
}
```

This finds `<script>` tags and looks for `window.location="..."` patterns. It's specific to the Fortinet-style portal that IIT Mandi uses, but the technique generalizes.

**Step 2: Extract magic value from portal page**

```rust
fn extract_magic_value(html: &str) -> Option<String> {
    let selector = Selector::parse("input[name=\"magic\"]").ok()?;
    document.select(&selector).next()?.attr("value")
        .filter(|v| !v.is_empty())
        .map(String::from)
}
```

The "magic" value is a one-time token embedded in a hidden form field — a common pattern in Fortinet and similar captive portals.

### 4.3 Authentication Flow (Step by Step)

```
1. check_captive_portal()
   ├── GET http://clients3.google.com/generate_204
   ├── If 204 → return None (no portal)
   └── If 200 → parse response body
       ├── extract_captive_portal_url() → portal URL from <script>
       ├── GET {portal_url} → fetch actual login page
       └── extract_magic_value() → hidden form token

2. login_with_retry(url, username, password, magic)
   ├── For attempt in 1..max_retries:
   │   ├── POST to portal URL with form data:
   │   │   ├── username
   │   │   ├── password
   │   │   ├── 4Tredir (redirect URL)
   │   │   └── magic (CSRF-like token)
   │   ├── Wait 2 seconds
   │   ├── verify_internet_connectivity()
   │   │   └── GET generate_204 → expect 204
   │   ├── If success → return Ok
   │   └── If failure → logout(), exponential backoff, retry
   └── Return last error after all retries exhausted

3. Retry backoff: initial_retry_delay * 2^(attempt-1)
   ├── Attempt 1: 2s delay
   ├── Attempt 2: 4s delay
   └── Attempt 3: 8s delay (default max_retries = 3)
```

**Smart detail:** Each retry starts with a logout to ensure a clean session state before re-attempting login.

### 4.4 HTTP Client Design

```rust
// Singleton client via OnceLock — reused across all requests
fn get_client() -> Result<reqwest::Client> {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(2)
            .build()
            .expect("Failed to create HTTP client")
    });
}
```

Connection pooling with tight limits prevents resource waste in a long-running daemon.

---

## 5. Cross-Platform Service Management

### 5.1 macOS — LaunchAgent

- Service name: `com.user.acp`
- Plist location: `~/Library/LaunchAgents/com.user.acp.plist`
- Key properties: `RunAtLoad = true`, `KeepAlive = true`
- Lifecycle: `launchctl load` / `launchctl unload`
- Created programmatically by writing the plist XML and calling `launchctl load`

**Plist generation (in Rust):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.user.acp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/acp</string><string>run</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
```

### 5.2 Linux — systemd User Service

- Service name: `acp`
- Unit file: `~/.config/systemd/user/acp.service`
- Lifecycle: `systemctl --user daemon-reload && enable && start`
- `Restart=on-failure` with `RestartSec=10`

**Unit file generation (in Rust):**
```ini
[Unit]
Description=Auto Captive Portal Login Service

[Service]
Environment=RUST_LOG=INFO
ExecStart={executable_path} run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

**Important:** Uses user-level systemd (no root required), making it work on shared systems and without sudo.

### 5.3 Windows — Windows Service

- Service name: `acp`
- Uses `windows-service` crate for the SCM (Service Control Manager) API
- `ServiceStartType::AutoStart` for automatic startup
- UAC manifest embedded via `build.rs` + `winres` crate to request admin elevation
- Custom `windows_service_main` module with proper service lifecycle:
  - `define_windows_service!` macro for the FFI entry point
  - `service_dispatcher::start()` for SCM integration
  - `mpsc::channel` for shutdown signaling between SCM handler and async runtime
  - Creates a dedicated Tokio runtime via `Runtime::new()` in the service thread
  - Reports `ServiceState::Running` / `ServiceState::Stopped` to SCM

**Windows-specific build configuration:**
```rust
// build.rs — embeds UAC manifest
res.set_manifest(requestedExecutionLevel level="requireAdministrator")

// Cargo.toml — conditional dependencies
[target.'cfg(windows)'.dependencies]
windows-service = "0.8"
eventlog = "0.4.0"

[target.'cfg(windows)'.build-dependencies]
winres = "0.1.12"
```

### 5.4 Platform Service Name Strategy

```rust
pub const SERVICE_NAME: &str = if cfg!(target_os = "macos") {
    "com.user.acp"     // reverse-DNS convention for macOS
} else {
    "acp"              // simple name for Linux/Windows
};
```

---

## 6. Build and Distribution

### 6.1 CI Pipeline

**Continuous Integration** (`.github/workflows/ci.yml`):
- **fmt**: `cargo fmt -- --check`
- **clippy**: `cargo clippy -- -D warnings` (with Linux deps installed)
- **test**: `cargo test` (with Linux deps installed)

**Release Pipeline** (`.github/workflows/release.yml`):
- Triggered by tag push (`v*`)
- Creates GitHub Release with auto-generated release notes
- Builds 5 platform binaries via matrix strategy:

| Runner | Target | Method | Output Binary |
|--------|--------|--------|--------------|
| ubuntu-latest | `x86_64-unknown-linux-gnu` | `cargo build` | `acp-script-linux-amd64` |
| ubuntu-latest | `aarch64-unknown-linux-gnu` | `cross build` (Docker) | `acp-script-linux-arm64` |
| macos-latest | `x86_64-apple-darwin` | `cargo build` | `acp-script-macos-x86_64` |
| macos-latest | `aarch64-apple-darwin` | `cargo build` | `acp-script-macos-arm64` |
| windows-latest | `x86_64-pc-windows-msvc` | `cargo build` | `acp-script-windows-amd64.exe` |

### 6.2 Cross-Compilation

Linux ARM64 uses the `cross` tool with a custom Docker image:

```dockerfile
# docker/Dockerfile.aarch64-unknown-linux-gnu
FROM ghcr.io/cross-rs/aarch64-unknown-linux-gnu:main
RUN dpkg --add-architecture arm64 && \
    apt-get install -y libdbus-1-dev:arm64
ENV PKG_CONFIG_ALLOW_CROSS=1
```

Configured via `Cross.toml`:
```toml
[target.aarch64-unknown-linux-gnu]
dockerfile = "docker/Dockerfile.aarch64-unknown-linux-gnu"
```

Linux x86_64 and macOS targets build natively on their respective runners. All builds use `Swatinem/rust-cache@v2` for dependency caching.

### 6.3 Install Script

The `install.sh` script handles the full user experience:

1. **Platform detection**: `uname -sm` → maps to binary name
2. **Binary download**: `curl` from GitHub Releases with retry (5 attempts, 5s delay)
3. **Installation**: `sudo mv` to `/usr/local/bin/acp`, `chmod 755`
4. **Setup**: Runs `acp setup` which prompts for LDAP credentials and creates the service
5. **Verification**: Checks service is running via `launchctl list` or `systemctl --user is-active`

**Uninstall** (`install.sh uninstall`):
1. Stops and removes the platform service (LaunchAgent / systemd unit)
2. Deletes credentials from keychain (`security delete-generic-password` / `secret-tool clear`)
3. Removes binary from `/usr/local/bin/acp`
4. Removes data directory `~/.local/share/acp/`

### 6.4 Logging

- Log file: `~/.local/share/acp/logs/acp.log` (Unix), `%APPDATA%\acp\logs\acp.log` (Windows)
- Auto-rotation: 5 MB max file size, 3 archive files (`acp.log.1`, `acp.log.2`, `acp.log.3`)
- When running as service: file-only output
- When running interactively: stdout + file dual output
- Noisy crates (reqwest, hyper, rustls, html5ever) set to warn level by default

---

## 7. What We Can Learn

### 7.1 OS Keychain Integration for Credential Storage

**Relevance: HIGH** — Our captive-portal-recipes project should support secure credential storage.

`keyring-rs` provides a clean, cross-platform abstraction. The API surface is minimal (store/get/clear), and the feature flags (`apple-native`, `sync-secret-service`, `windows-native`) let the same code work everywhere. The pattern of storing username and password as separate entries under a shared service name is simple and effective.

**Takeaway:** Use `keyring-rs` (or equivalent in our language) for any credential storage needs. Never write passwords to config files.

### 7.2 Hybrid Monitoring Architecture

**Relevance: HIGH** — Could directly inform our standalone daemon target.

The combination of event-driven (netwatcher) + adaptive polling is elegant:
- Events give instant response to network changes (user connects to Wi-Fi)
- Polling catches edge cases (portal changes without network event)
- Exponential decay (half-life) smoothly transitions between aggressive and relaxed polling
- `tokio::select!` with biased priority ensures correct precedence

**Takeaway:** If we build a standalone monitoring daemon, adopt this hybrid model. The netwatcher crate is specifically designed for this use case.

### 7.3 Cross-Platform Service Management Patterns

**Relevance: MEDIUM** — Useful if we distribute as native services.

The pattern of generating platform-specific service configuration files from within the application (not from the installer) is clean. Each platform gets:
- The right service type (LaunchAgent, systemd user service, Windows Service)
- Proper lifecycle management (auto-start, restart-on-failure)
- Platform-appropriate log locations and credential backends

**Takeaway:** Service configuration generation belongs in the application, not in external scripts. The `ServiceManager` struct with `create_service()` behind `#[cfg]` gates is a clean pattern.

### 7.4 DOM Parsing Approach

**Relevance: MEDIUM** — Alternative to full JavaScript execution for portal page analysis.

ACP proves that `scraper` (CSS selectors + HTML parsing) is sufficient for many captive portals. The Fortinet-style portal puts the magic token in a hidden form field and the redirect URL in a `<script>` tag — both extractable without running JavaScript.

**Takeaway:** Before reaching for a headless browser, try CSS selectors. Many captive portals use simple HTML forms that don't require JavaScript execution. This dramatically reduces complexity and resource usage.

### 7.5 Installer and Distribution Model

**Relevance: MEDIUM** — Good reference for our distribution strategy.

The `curl | bash` install pattern with platform detection, GitHub Release binary download, and integrated setup is user-friendly. The uninstall path is equally complete. The Windows approach (UAC manifest + Service Manager integration) shows how to handle privilege elevation properly.

**Takeaway:** The install script pattern (detect platform → download binary → run setup → verify) is a solid baseline. Consider adding version checking and self-update capability.

### 7.6 Exponential Backoff Retry Logic

**Relevance: HIGH** — Directly applicable to our authentication recipes.

```rust
let delay_secs = initial_retry_delay * 2u64.pow(attempt - 1);
// Attempt 1: 2s, Attempt 2: 4s, Attempt 3: 8s
```

Combined with logout-before-retry for clean state, this is a robust pattern for unreliable network authentication.

**Takeaway:** Always implement retry with backoff for portal authentication. Always clean state (logout) between retries to avoid session conflicts.

---

## 8. What We Can Skip

### 8.1 IIT Mandi-Specific Portal Logic

The portal URL (`login.iitmandi.ac.in:1003`), the `4Tredir` form field, and the `window.location` extraction pattern are specific to IIT Mandi's Fortinet deployment. Our project handles many different portal types.

### 8.2 Rust Language Specifics

The choice of Rust, specific crate versions, Rust edition 2024 features, and `OnceLock` patterns are language-specific. Our recipes are language-agnostic.

### 8.3 Desktop Notification Code

The `notify-rust` integration and notification UI are nice-to-have features but not core to the captive portal detection/authentication problem. Our compiler target is likely headless environments.

### 8.4 CLI UI (Status Display, Spinners)

The `indicatif` spinner-based status display and ASCII-art status boxes are user-facing polish, not architectural patterns we need to replicate.

### 8.5 State Persistence Format

The JSON-based state file (`state.json`) with timestamps is straightforward and not a novel pattern worth studying.

---

## 9. Attribution Notes

- All data sourced from the public GitHub repository: https://github.com/AmanSikarwar/auto-captive-portal
- Licensed under MIT — we study architecture patterns, we do not copy code
- Source files read: `main.rs`, `daemon.rs`, `captive_portal.rs`, `config.rs`, `credentials.rs`, `service.rs`, `state.rs`, `error.rs`, `logging.rs`, `notifications.rs`, `build.rs`, `Cargo.toml`, `Cross.toml`, `install.sh`, `release.yml`, `ci.yml`, `Dockerfile.aarch64-unknown-linux-gnu`
- README and source code accessed May 2026

---

## Appendix A: Configuration Defaults

```toml
# ~/.config/acp/config.toml (or %APPDATA%\acp\config.toml on Windows)
connectivity_check_url = "http://clients3.google.com/generate_204"
max_delay_secs = 1800          # 30 minutes — post-login polling interval
min_delay_secs = 10            # 10 seconds — aggressive portal-check interval
max_retries = 3                # Login attempt retries
initial_retry_delay_secs = 2   # Base delay for exponential backoff
log_level = "INFO"
portal_login_url = ""          # Optional override
```

Environment variable `ACP_CONNECTIVITY_URL` overrides `connectivity_check_url`.

## Appendix B: File Locations Summary

| Item | macOS | Linux | Windows |
|------|-------|-------|---------|
| Binary | `/usr/local/bin/acp` | `/usr/local/bin/acp` | `C:\Program Files\ACP\acp.exe` |
| Config | `~/.config/acp/config.toml` | `~/.config/acp/config.toml` | `%APPDATA%\acp\config.toml` |
| Logs | `~/.local/share/acp/logs/` | `~/.local/share/acp/logs/` | `%APPDATA%\acp\logs\` |
| State | `~/.local/share/acp/state.json` | `~/.local/share/acp/state.json` | `%APPDATA%\acp\state.json` |
| Credentials | macOS Keychain | Secret Service | Credential Manager |
| Service | `~/Library/LaunchAgents/com.user.acp.plist` | `~/.config/systemd/user/acp.service` | Windows Service `acp` |
