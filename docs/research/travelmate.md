# Travelmate Captive Portal Login System — Deep Research

> Research document for the captive-portal-recipes compiler project.
> Source: [openwrt/packages — net/travelmate](https://github.com/openwrt/packages/tree/master/net/travelmate)
> Date: 2026-05-26

---

## 1. Overview

| Field | Value |
|-------|-------|
| **Project** | Travelmate — wlan connection manager for travel routers |
| **Repository** | `openwrt/packages`, path `net/travelmate/` |
| **Maintainer** | Dirk Brenken (`dibdot` on GitHub, dev@brenken.org) |
| **License** | GPL-3.0 |
| **Platform** | OpenWrt (current stable + snapshot) |
| **Backend version (as of research)** | 2.3.x series |
| **Key file** | `travelmate-functions.sh` (~1527 lines, the entire engine) |

Travelmate turns a small OpenWrt router into a travel router: it connects to upstream Wi-Fi (hotel, train, café), provides its own AP for your devices, and handles captive portal detection/login automatically. Login scripts are the primary extension mechanism for portal auto-authentication.

---

## 2. Login Script System

### 2.1 Script Format and Location

- Scripts live in `/etc/travelmate/` with the `.login` extension.
- Must be executable (`chmod +x`).
- Referenced per-uplink via UCI options `script` and `script_args` in the travelmate config.
- A login script is a plain POSIX shell script (runs under `ash`/busybox `sh`).

### 2.2 Standard Boilerplate

Every shipped login script begins with:

```sh
#!/bin/sh
# captive portal auto-login script for <description>
# Copyright (c) <year> Dirk Brenken (dev@brenken.org)
# This is free software, licensed under the GNU General Public License v3.

# shellcheck disable=all

export LC_ALL=C
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

trm_funlib="/usr/lib/travelmate-functions.sh"
if [ -z "${trm_bver}" ]; then
    . "${trm_funlib}"
    f_conf
fi
```

**What this does:**

1. Sources the travelmate function library (`travelmate-functions.sh`).
2. Calls `f_conf()` which loads the UCI config, resolves all command paths, and builds `trm_fetchparm`.
3. The `if [ -z "${trm_bver}" ]` guard prevents re-sourcing when the script is already running inside the travelmate process (where `trm_bver` is already set).

After sourcing, the following variables are available to the script:

### 2.3 Available Variables

| Variable | Type | Description |
|----------|------|-------------|
| `trm_fetch` / `trm_fetchcmd` | command path | Full path to `curl` (e.g., `/usr/bin/curl`) |
| `trm_fetchparm` | string | Pre-built curl flags: `--silent --show-error --location --fail --referer http://www.example.com --retry N --retry-delay N --max-time N [--interface DEVICE]` |
| `trm_useragent` | string | Configurable user-agent (default: `Mozilla/5.0 (X11; Linux x86_64; rv:144.0) Gecko/20100101 Firefox/144.0`) |
| `trm_captiveurl` | string | URL used for captive detection (default: `http://detectportal.firefox.com`) |
| `trm_domain` | string | **Set by the login script itself** — the target portal domain. Used for display/logging. |
| `trm_lookupcmd` | command path | Full path to `nslookup` |
| `trm_awkcmd` | command path | Full path to `gawk` or `awk` |
| `trm_jsoncmd` | command path | Full path to `jsonfilter` (OpenWrt's JSON CLI) |
| `trm_sortcmd` | command path | Full path to `sort` |
| `trm_bver` | string | Travelmate backend version |
| `trm_fver` | string | Travelmate frontend (LuCI) version |
| `trm_maxwait` | integer | Max wait time in seconds (default 30) |

**Note:** Login scripts should reference `trm_fetch` (without "cmd" suffix) for running curl — this is the convention used in all shipped scripts. The `trm_fetchcmd` variant is used internally by `f_net()`.

### 2.4 Return Codes

Return codes are the **only** way login scripts communicate with travelmate (stdout/stderr are redirected to `/dev/null`):

| Code | Meaning | When to Use |
|------|---------|-------------|
| `0` | **Success** — login completed, internet should be accessible | After successful authentication |
| `1` | **Lookup failure** — DNS lookup for the portal domain failed | After `trm_lookupcmd` fails |
| `2` | **Token extraction failure** — security token/session could not be extracted | After CSRF token, session ID, etc. is empty |
| `3`+ | **Step-specific failures** — used for multi-step flows | Each step can have its own exit code |
| `255` | **Generic failure** — the login request itself failed or returned unexpected data | Catch-all for auth failures |

The maintainer (Dirk) specifically rejected `set -eu` in login scripts during PR #15250, because he wants **individual, specific return codes** that are logged meaningfully, not generic "parameter not set" errors.

### 2.5 Script Arguments Mechanism

Per-uplink UCI option `script_args` provides runtime arguments passed as positional parameters:

```
"${login_script}" ${login_script_args} >/dev/null 2>&1
```

Note: `script_args` is **unquoted** — it undergoes word splitting. This means space-separated arguments become `$1`, `$2`, etc. in the script. Typical usage:

```sh
username="${1}"
password="${2}"
```

Added via PR #10034 (merged 2019-09-24, by @onjen). Motivation: hotel portals requiring fresh credentials weekly, allowing users to change args via LuCI without editing the script.

### 2.6 How Travelmate Detects Captive Portals and Triggers Login Scripts

The full flow is inside `f_check()` (lines 828-1038 of `travelmate-functions.sh`):

1. **Signal quality check**: `f_check` polls the STA interface, checks signal ≥ `trm_minquality`.
2. **`f_net()` call**: Fetches `trm_captiveurl` with curl's `--write-out "%{json}"` to get structured metadata.
3. **Captive detection** (`f_net()` returns `net cp '<domain>'`):
   - **HTTP redirect**: If curl followed a redirect to a different host → captive portal at that host.
   - **Meta-refresh**: Scans HTML body for `<meta http-equiv="refresh"` → extracts target domain.
   - **JS redirect**: Scans for `location.href=` patterns → extracts target domain.
   - **Curl error code 6** (DNS failure): Extracts trailing domain from error message → captive portal.
4. **DHCP rebind whitelist**: The detected `cp_domain` is added to dnsmasq's `rebind_domain` list via `uci_add_list`, then dnsmasq is reloaded. This allows the router to resolve the captive portal domain despite DNS rebind protection.
5. **Login script invocation**: If a `script` is configured and executable for the current uplink:
   ```sh
   "${login_script}" ${login_script_args} >/dev/null 2>&1
   rc="${?}"
   ```
6. **Post-login verification**: If `rc = 0`, `f_net()` is called again to verify internet access.

---

## 3. Shipped Login Scripts Analysis

### 3.1 wifibahn.login — DB/ICE Railway Hotspots (DE)

**Domain**: `wifi.bahn.de` (fallback: `login.wifionice.de`)

**Auth type**: CSRF form submit (no credentials)

**Flow**:

1. **DNS lookup**: Try `wifi.bahn.de`, fallback to `login.wifionice.de`. Exit 1 if both fail.
2. **CSRF token acquisition**: Fetch the portal page with `--cookie-jar`, extract the `csrf` cookie value via awk (`/csrf/{print $7}`).
3. **Login POST**: Submit `login=true&CSRFToken=${sec_token}` with the CSRF cookie in a header.

**Tools used**: `curl` (cookie-jar, data POST), `awk` (cookie parsing), `rm` (cleanup)

**Return codes**: 1 (DNS fail) → 2 (no token) → 0 (empty response = success) / 255 (non-empty = fail)

**Complexity**: Low. Single fallback, cookie-based CSRF, no credentials.

### 3.2 telekom.login — Telekom Hotspots (DE)

**Domain**: `hotspot.t-mobile.net`

**Auth type**: XML-based redirect with username/password (URL-encoded)

**Flow**:

1. **URL-encode credentials**: Custom `urlencode()` function for ash (handles `[a-zA-Z0-9.~_-]` as-is, space as `%20`, everything else as `%XX`).
2. **DNS lookup**: `hotspot.t-mobile.net`. Exit 1 on failure.
3. **Fetch captive URL**: Response is XML containing `<LoginURL>...</LoginURL>`.
4. **Extract redirect URL**: `awk` extracts the login URL from XML tags, with `&amp;` → `&` entity decoding.
5. **Login POST**: Submit `UserName=${username}&Password=${password}&FNAME=0&button=Login&OriginatingServer=http%3A%2F%2F${trm_captiveurl}` to the extracted URL.
6. **Verify**: Check for `<LogoffURL>` in response (presence = success).

**Tools used**: `curl`, `awk` (XML parsing, URL entity decoding), custom `urlencode()`

**Return codes**: 1 (DNS fail or no redirect URL) → 255 (no logoff URL in response) → 0 (logoff URL found = success)

**Complexity**: Medium. XML parsing, URL encoding, redirect chain.

### 3.3 vodafone.login — Vodafone Hotspots (DE)

**Domain**: `hotspot.vodafone.de`

**Auth type**: JSON API multi-step with credentials

**Flow**:

1. **DNS lookup**: `hotspot.vodafone.de`. Exit 1 on failure.
2. **Get SID**: Fetch `trm_captiveurl` with `--write-out "%{redirect_url}"` to capture the HTTP redirect. Extract `sid` from query params using awk (`FS="[=&]"`).
3. **Get session**: GET `https://${trm_domain}/api/v4/session?sid=${sid}`. Extract `session` token and `loginProfiles[*].id` array via jsonfilter.
4. **Select profile**: Loop through profile IDs, select profile `4` (csc-community access type). Exit 3 if not found.
5. **Login POST**: POST to `https://${trm_domain}/api/v4/login?sid=${sid}` with profile, session, and credentials.
6. **Verify**: Check `@.success == "true"` in JSON response.

**Tools used**: `curl` (redirect capture, data POST), `awk` (URL param parsing), `jsonfilter` (JSON extraction), `sort` (profile ID sorting)

**Return codes**: 1 (DNS fail or no SID) → 2 (no session) → 3 (no valid profile) → 0 (success=true) / 255 (success≠true)

**Complexity**: High. Multi-step JSON API, profile selection, credential injection.

### 3.4 generic-user-pass.login — Template Script

**Domain**: `example.com` (placeholder)

**Auth type**: Simple form POST (template/demo)

**Flow**:

1. **DNS lookup**: `example.com`. Exit 1 on failure.
2. **Login POST**: Submit `username=${user}&password=${password}` as form data.

**Tools used**: `curl` (form POST)

**Return codes**: 0 (empty response = success) / 255 (non-empty = failure)

**Complexity**: Minimal. Serves as a template for users to adapt.

**Important note**: The success check is inverted compared to intuition — an **empty** response body is treated as success. This pattern appears in `wifibahn.login` too, where the login page returns a redirect/empty body on success.

---

## 4. Community Contributions

### 4.1 MikroTik Login Script — PR #15250 (closed, superseded by #15254)

- **Author**: Christian Kühnel (`@ChristianKuehnel`)
- **Date**: March 2021
- **Status**: Closed. Superseded by PR #15254 (which was merged).
- **What happened**: The PR added a `mikrotik.login` script for MikroTik CHAP-based captive portals. Dirk requested several changes:
  - Remove `set -eu` (wanted specific return codes, not generic errors)
  - Add explicit user/password parameter validation
  - Remove `echo` statements (only return codes are visible in logs)
  - Add a `return` at end of file
  - Squash commits

**Key takeaway**: The maintainer has strong opinions about error handling — no `set -eu`, no echo, specific exit codes only.

### 4.2 strayer/travelmate-vodafone-hotspot-login

- **Author**: Sven Grunewaldt (`@strayer`)
- **URL**: https://github.com/strayer/travelmate-vodafone-hotspot-login
- **Date**: July 2021
- **Status**: Independent community fork (not merged into travelmate)

**Key differences from the shipped `vodafone.login`**:

| Aspect | Shipped (Dirk) | strayer fork |
|--------|----------------|--------------|
| JSON parsing | `jsonfilter` (OpenWrt native) | `jq` (requires `opkg install jq`) |
| Auth profile | Profile 4 (csc-community, with credentials) | Profile 2 (termsOnly, no credentials) |
| Error handling | Individual exit codes per step | `set -euo pipefail` |
| Config source | Sources `travelmate-functions.sh` | Reads UCI directly via `uci_get` |
| User-agent | From `trm_useragent` variable | Reads from UCI config with fallback |

The fork uses `jq` instead of `jsonfilter`, which is an additional dependency. It targets the free tier (profile 2, termsOnly) rather than the credential-based profile 4.

### 4.3 Bayern WLAN — PR #21093 (draft, ongoing)

- **Author**: `@0x6368` (Christian Bieg)
- **Date**: May 2023
- **Status**: Draft/ongoing
- **Pattern**: Very similar to `vodafone.login` but uses profile ID 6 and no credentials.

### 4.4 Optional Args — PR #10034 (merged)

- **Author**: `@onjen` (Johannes Rothe)
- **Date**: September 2019
- **Status**: Merged
- **What it added**: UCI option `script_args` per uplink, passed as positional parameters to the login script. This enables changing credentials per-uplink without editing scripts. Also added `generic-user-pass.login` as a demo.

### 4.5 BTLogin — g0wfv/BTLogin

- **Author**: `@g0wfv`
- **URL**: https://github.com/g0wfv/BTLogin
- **Pattern**: Shell script for BT FON logins. Can be symlinked into `/etc/travelmate/` with `.login` extension. Checks internet connectivity, determines login status, and performs form-based login.

### 4.6 Bare-Mode Service Toggling — Issue #28646 (open)

- **Author**: `@SeanLF`
- **Date**: February 2026
- **Status**: Open feature request

**Problem**: When travelmate detects a captive portal and runs login scripts, services like encrypted DNS (stubby, adguardhome), Tailscale mesh VPN, and DNS-based ad blockers interfere with portal authentication. The portal is detected but login fails because DNS queries bypass the portal's DNS interception.

**Proposed solution**: A "bare-mode" callback (like the existing `travelmate.vpn` hook):

1. New UCI options: `trm_baremode`, `trm_baremode_services`
2. Optional per-uplink override: `baremode_services`
3. Callback script `/etc/travelmate/travelmate.baremode` called with "disable"/"enable"
4. Flow: disable services → portal auth → re-enable services

**Prior art**: GL.iNet implements this in their [portal-detection](https://github.com/gl-inet/portal-detection) tool.

---

## 5. Detection Flow

### 5.1 f_net() — Captive Portal Detection

`f_net()` (lines 762-824) is the core detection function. It returns one of:

| Result string | Meaning |
|---------------|---------|
| `"net ok"` | Internet accessible (no captive portal) |
| `"net cp '<domain>'"` | Captive portal detected at `<domain>` |
| `"net nok"` | No connectivity at all |

**Detection mechanism**:

```sh
raw="$("${trm_fetchcmd}" ${trm_fetchparm} \
    --user-agent "${trm_useragent}" \
    --header "Cache-Control: no-cache, no-store, must-revalidate, max-age=0" \
    --write-out "%{json}" \
    "${trm_captiveurl}")"
```

1. **Fetch `trm_captiveurl`** (default: `http://detectportal.firefox.com`) with curl's `--write-out "%{json}"` which appends JSON metadata including `exitcode`, `response_code`, and `redirect_url`.
2. **Split response**: HTML body = everything before `{`, JSON metadata = everything from `{`.
3. **Check curl exit code**:
   - **`exitcode = 0`** (success):
     - If `redirect_url` points to a different host → **captive portal** at that host.
     - If no redirect, scan HTML body for:
       - `<meta http-equiv="refresh"` meta-refresh → extract target domain.
       - `location.href=` JavaScript redirect → extract target domain.
     - Otherwise → **net ok**.
   - **`exitcode = 6`** (DNS resolution failure):
     - Extract trailing domain from error message → **captive portal** (DNS interception detected).
   - **Other errors**: `net nok`.

### 5.2 Captive Portal Domain Extraction

The domain is extracted from the redirect URL by splitting on `/` and taking the 3rd field (host):

```sh
json_cp="$(printf "%s" "${json_cp_url}" | "${trm_awkcmd}" 'BEGIN{FS="/"}{printf "%s",tolower($3)}')"
```

For meta-refresh and JS redirects, the URL is similarly parsed to extract the host portion.

### 5.3 DHCP Rebind Whitelist Management

After detecting a captive portal domain, `f_check()` adds it to dnsmasq's rebind protection whitelist:

```sh
while :; do
    cp_domain="$(printf "%s" "${result}" | "${trm_awkcmd}" -F '['\''| ]' '/^net cp/{printf "%s",$4}')"
    # Check if dnsmasq config is available and domain is not empty
    if [ ! -x "/etc/init.d/dnsmasq" ] || [ ! -f "/etc/config/dhcp" ] || [ -z "${cp_domain}" ]; then
        break
    fi
    # Skip if already in whitelist
    case " $(uci_get "dhcp" "@dnsmasq[0]" "rebind_domain") " in
    *" ${cp_domain} "*) break ;;
    esac
    # Add and reload
    uci_add_list "dhcp" "@dnsmasq[0]" "rebind_domain" "${cp_domain}"
    [ -n "$(uci -q changes "dhcp")" ] && uci_commit "dhcp"
    /etc/init.d/dnsmasq reload
    f_log "info" "captive portal domain '${cp_domain}' added to to dhcp rebind whitelist"
    result="$(f_net)"  # Re-check after whitelist addition
done
```

This loop runs until:
- No more captive portal domains are detected (login succeeded)
- The domain is already in the whitelist
- dnsmasq is not available

### 5.4 Heartbeat Monitoring

Travelmate continuously monitors the connection by calling `f_check()` periodically. The "heartbeat" is the main polling loop in `f_main()`:

1. `f_main()` is called on a timer (via `sleep ${trm_timeout}`).
2. `f_check("initial", "false")` runs on each tick.
3. If already connected (`net ok`), the VPN hook runs (`f_vpn "enable_keep"`).
4. If proactive scanning is enabled, it looks for better uplinks.

The heartbeat ensures that if a portal re-appears (e.g., session timeout), it will be detected and the login script re-invoked.

---

## 6. Hook Architecture

### 6.1 VPN Hook (f_vpn)

Travelmate manages VPN connections via `f_vpn()` (lines 260-337):

- **External script**: `/etc/travelmate/travelmate.vpn` (configurable via `trm_vpnpgm`)
- **Called with**: `"${vpn}" "${vpn_action}" "${vpn_service}" "${vpn_iface}" "${vpn_instance}"`
- **Actions**: `enable`, `enable_keep`, `disable`
- **Per-uplink config**: `vpn`, `vpnservice`, `vpniface` in the uplink section
- **Behavior**:
  - On portal detection: `f_vpn "disable"` — tears down all VPN interfaces before login
  - On successful connection: `f_vpn "enable"` — brings up the configured VPN
  - On proactive switch: `f_vpn "enable_keep"` — keeps current VPN, tears down only foreign interfaces

### 6.2 Login Script Hook

The login script hook is the primary extensibility point:

```
UCI: config uplink → option script '/etc/travelmate/myportal.login'
UCI: config uplink → option script_args 'myuser mypass'
```

Invocation (inside `f_check()`):
```sh
"${login_script}" ${login_script_args} >/dev/null 2>&1
rc="${?}"
```

Key properties:
- **stdout/stderr silenced**: Only return codes matter.
- **args unquoted**: Word-split into positional parameters.
- **Blocking**: Travelmate waits for the script to complete.
- **Timeout**: Governed by the polling loop's `trm_maxwait` (default 30s).

### 6.3 Mail Hook

- External script: `/etc/travelmate/mail.template`
- Triggered after successful uplink connection
- Uses `msmtp` for sending

### 6.4 Bare-Mode Proposal (Issue #28646)

The proposed bare-mode hook would follow the VPN hook pattern:

```
UCI: option trm_baremode '1'
UCI: option trm_baremode_services 'stubby adguardhome tailscale'
UCI: config uplink → option baremode_services 'stubby adguardhome'
Script: /etc/travelmate/travelmate.baremode <action> <services...>
```

Flow: disable interfering services → portal auth → re-enable services.

This is not yet implemented but represents a likely future direction.

### 6.5 Per-Uplink Configuration

Each uplink section can have:
- `enabled` — enable/disable the uplink
- `script` — path to login script
- `script_args` — runtime arguments
- `vpn` — per-uplink VPN toggle
- `vpnservice` — per-uplink VPN service reference
- `vpniface` — per-uplink VPN interface
- `macaddr` — per-uplink MAC address
- `con_start_expiry` — auto-disable after N minutes
- `con_end_expiry` — auto-re-enable after N minutes

---

## 7. What We Can Learn

### 7.1 Variable Naming Conventions

Our compiler should emit scripts using the exact same variable names:

| Variable | Convention | Our Compiler |
|----------|-----------|--------------|
| `trm_domain` | Set by script, used in fetch URLs | Uses `%%DOMAIN%%` → correct |
| `trm_fetch` | Command path to curl | Used correctly in templates |
| `trm_fetchparm` | Pre-built curl flags | Used correctly in templates |
| `trm_useragent` | User-agent string | Used correctly in templates |
| `trm_captiveurl` | Detection URL | Used correctly in templates |
| `trm_lookupcmd` | nslookup path | Used correctly in templates |
| `trm_awkcmd` | awk/gawk path | Used correctly in templates |
| `trm_jsoncmd` | jsonfilter path | Used correctly in templates |
| `trm_sortcmd` | sort path | Used in vodafone recipe |
| `sec_token` | CSRF/security token | Used correctly in templates |
| `raw_html` | HTTP response body | Used correctly in templates |
| `redirect_url` | Captured redirect URL | Used correctly in templates |
| `username` / `password` | Credential variables | Used correctly in templates |

### 7.2 Return Code Conventions

Our compiler should follow the same exit code scheme:

- `0` — success
- `1` — DNS lookup failure
- `2` — token extraction failure (CSRF, session, etc.)
- `3+` — step-specific failures (each multi-step increment)
- `255` — generic/unknown failure

Our `gen_success_check()` function currently uses `0` and `255`, which is correct. The `gen_json_api_steps()` generator uses `${_step}` as the exit code for required fields, which aligns with the step-number convention.

### 7.3 Error Handling Patterns in ash/busybox

Key patterns from the shipped scripts:

1. **No `set -eu`**: Explicit error checking at each step, with specific exit codes.
2. **Guard pattern**: `[ -z "${var}" ] && exit N` after each extraction step.
3. **DNS guard first**: Always check `trm_lookupcmd` before making HTTP requests.
4. **Cleanup**: Remove temp files (`rm -f "/tmp/${trm_domain}.cookie"`).
5. **Silent stderr**: `2>/dev/null` on all extraction commands.
6. **Printf over echo**: Consistent use of `printf "%s"` for string output.

### 7.4 Script Structure for Maximum Compatibility

The optimal structure (matching shipped scripts):

```
1. shebang + header
2. shellcheck disable
3. LC_ALL + PATH exports
4. Source travelmate-functions.sh (with trm_bver guard)
5. Credential setup (from positional params)
6. DNS lookup of trm_domain (with fallbacks)
7. Auth steps (each with guard and specific exit code)
8. Success check with final exit code
```

Our templates follow this structure exactly. This is a strong validation of our approach.

---

## 8. Integration Path

### 8.1 Drop-In Replacement Compatibility

Our compiled `.login` files are designed as drop-in replacements for travelmate's shipped scripts. The compatibility checklist:

| Requirement | Status | Notes |
|-------------|--------|-------|
| Shebang `#!/bin/sh` | Correct | All templates start with this |
| `LC_ALL=C` + `PATH` export | Correct | Standard boilerplate |
| Source `travelmate-functions.sh` with `trm_bver` guard | Correct | All templates include this |
| Use `trm_*` variables | Correct | Templates reference all standard variables |
| Exit code conventions | Correct | 0/1/2/3/255 scheme followed |
| No `set -eu` | Correct | Not used in any template |
| No echo statements | Correct | Only exit codes |
| Use `trm_fetch` (not raw `curl`) | Correct | All templates use `${trm_fetch}` |
| Use `trm_fetchparm` | Correct | Included in all curl invocations |
| `shellcheck disable=all` | Correct | Present in all templates |

### 8.2 What Our Compiler Already Gets Right

1. **Template structure** matches the shipped script boilerplate exactly.
2. **Variable naming** uses the correct `trm_*` convention.
3. **CSRF form submit** (`csrf-form-submit.sh.template`) produces output structurally identical to `wifibahn.login`.
4. **JSON API** (`json-api.sh.template`) produces output matching the `vodafone.login` pattern.
5. **Fallback domain handling** (`gen_fallback_domains()`) generates the nested if/fi pattern used in `wifibahn.login`.
6. **URL encoding** (`gen_urlencode_func()`) generates the same `urlencode()` function as `telekom.login`.
7. **Success checks** are configurable (`empty_body`, `json_true`, `contains_string`, `json_not_null`) matching all shipped patterns.

### 8.3 What Needs Adjustment

1. **`trm_fetch` vs `trm_fetchcmd`**: Our templates use `${trm_fetch}` (correct — this is what the function library sets). But we should verify this is always the correct variable. In `travelmate-functions.sh`, `trm_fetchcmd` is the variable set by `f_cmd()`, but login scripts source the library and use `${trm_fetch}` — the naming is slightly inconsistent in the upstream code. **Our templates are correct** in using `${trm_fetch}` since that's what all shipped login scripts use.

2. **Referer handling**: Some shipped scripts use explicit `--referer` with specific URLs (e.g., vodafone uses `--referer "http://${trm_domain}/portal/?sid=${sid}"`). Our JSON API template supports this via `stepN_referer` params. Good.

3. **Cookie-jar pattern**: The wifibahn CSRF pattern (cookie-jar → extract → cleanup) is correctly implemented in `gen_csrf_cookie_fetch()`.

4. **Response variable naming**: Our templates use `raw_html` for the response body, matching the convention. `redirect_url` is used for redirect captures. These match upstream.

5. **Per-uplink service toggling**: The bare-mode proposal (#28646) would add a new hook pattern. Our compiler doesn't need to emit this, but it's worth tracking for future integration.

6. **`trm_sortcmd` usage**: The vodafone login uses `${trm_sortcmd}` for sorting profile IDs. Our JSON API template generates step code that includes this variable when needed, but we should ensure recipes that need sorting have the appropriate extract logic.

### 8.4 Recipe Coverage Mapping

| Shipped Script | Our Recipe | Auth Type | Match Quality |
|----------------|-----------|-----------|---------------|
| `wifibahn.login` | `wifibahn.json` | `csrf-form-submit` | Exact structural match |
| `vodafone.login` | `vodafone-de.json` | `json-api` | Exact flow match (3 steps) |
| `telekom.login` | `t-mobile-hotspot.json` | `json-api` | Different flow (our recipe uses JSON API, theirs uses XML redirect) |
| `generic-user-pass.login` | `generic-form.json` | `form-submit` | Same pattern, different defaults |
| — | `mikrotik-chap.json` | `chap-md5` | Covers the PR #15250 use case |

**Note**: Our `t-mobile-hotspot.json` uses the newer JSON API (`/wlan/rest/freeLogin`) while the shipped `telekom.login` uses the XML-based redirect flow. Both target Telekom hotspots but may cover different tiers (free vs. paid).

---

## Appendix A: Command Resolution

All commands are resolved at startup via `f_cmd()`:

```sh
trm_catcmd="$(f_cmd cat)"
trm_awkcmd="$(f_cmd gawk awk)"           # primary: gawk, fallback: awk
trm_sortcmd="$(f_cmd sort)"
trm_pgrepcmd="$(f_cmd pgrep)"
trm_killcmd="$(f_cmd kill)"
trm_jsoncmd="$(f_cmd jsonfilter)"         # OpenWrt-specific JSON tool
trm_ubuscmd="$(f_cmd ubus)"               # OpenWrt RPC bus
trm_logcmd="$(f_cmd logger)"
trm_wificmd="$(f_cmd wifi)"
trm_fetchcmd="$(f_cmd curl)"              # always curl
trm_ifstatuscmd="$(f_cmd ifstatus)"
trm_ipcalccmd="$(f_cmd ipcalc.sh)"
trm_lookupcmd="$(f_cmd nslookup)"
trm_mailcmd="$(f_cmd msmtp optional)"     # optional: no error if missing
```

The `f_cmd()` function takes a primary and optional secondary command. If the secondary is `"optional"`, missing commands are silently skipped. Otherwise, missing commands cause an emergency log and exit.

## Appendix B: trm_fetchparm Construction

Built in `f_conf()`:

```sh
trm_fetchparm="--silent --show-error --location --fail \
    --referer http://www.example.com \
    --retry $((trm_maxwait / 6)) \
    --retry-delay $((trm_maxwait / 6)) \
    --max-time $((trm_maxwait / 6))"
device="$("${trm_ifstatuscmd}" "${trm_iface}" | "${trm_jsoncmd}" -ql1 -e '@.device')"
[ -n "${device}" ] && trm_fetchparm="${trm_fetchparm} --interface ${device}"
```

The `--interface ${device}` binding ensures curl uses the correct network interface (the uplink STA), preventing routing issues when multiple interfaces are present.

## Appendix C: File Locations in OpenWrt

| File | Path | Purpose |
|------|------|---------|
| Function library | `/usr/lib/travelmate-functions.sh` | Core engine, sourced by login scripts |
| Login scripts | `/etc/travelmate/*.login` | Captive portal auto-login scripts |
| VPN hook | `/etc/travelmate/travelmate.vpn` | VPN connection handler |
| Mail template | `/etc/travelmate/mail.template` | Email notification template |
| PID file | `/var/run/travelmate/travelmate.pid` | Process tracking |
| Runtime JSON | `/var/run/travelmate/travelmate.runtime.json` | Status information |
| Init script | `/etc/init.d/travelmate` | Service management |
| UCI config | `/etc/config/travelmate` | Main configuration |
