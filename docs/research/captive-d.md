# janisstreib/captive.d — Research Report

> Research document for the captive-portal-recipes compiler project.
> Target: `github.com/janisstreib/captive.d`
> Date: 2026-05-27
> Status: **Active repo, fully analyzed**

---

## 1. Overview

| Field | Value |
|-------|-------|
| **Repository** | [janisstreib/captive.d](https://github.com/janisstreib/captive.d) |
| **Author** | Janis Streib (`janisstreib`) |
| **License** | BSD-3-Clause |
| **Language** | Python 93.7%, Shell 6.3% |
| **Platform** | Linux (NetworkManager dispatcher), NOT OpenWrt |
| **Stars** | 6 |
| **Forks** | 1 |
| **Commits** | 11 (Aug 2019 – Feb 2020) |
| **Last activity** | Feb 24, 2020 |
| **Portal scripts** | 3 (OEBB, WIFIonICE, generic_avm) |
| **Dependencies** | Python 3 + `requests` + `bs4` (BeautifulSoup 4), or `bash` + `curl` |

**Purpose**: A minimal, convention-based collection of scripts for auto-logging into captive portals. Each script is named after the WiFi SSID it handles. The framework is designed as a plugin directory for NetworkManager's `dispatcher.d` on desktop Linux.

---

## 2. Architecture

### 2.1 File Layout

```
captive.d/
  README.md        — Documentation + dispatcher integration example
  LICENSE           — BSD-3-Clause
  OEBB              — Python script for ÖBB (Austrian Federal Railways) WiFi
  WIFIonICE         — Python script for Deutsche Bahn ICE WiFi
  generic_avm       — Bash script for AVM Fritz!Box guest portal
```

### 2.2 Design Philosophy

captive.d follows a **pure convention-over-configuration** pattern:

- **No config file.** No YAML, JSON, or INI. Portal "definitions" are just executable scripts named after the SSID.
- **No runtime engine.** The "dispatcher" is a bash snippet in the README that the user manually installs into `/etc/NetworkManager/dispatcher.d/`.
- **No abstraction layer.** Each script is a standalone program that independently handles the full login flow.
- **No shared library.** Scripts don't import common code. Each script re-implements HTTP session management from scratch.

### 2.3 How It Works (Full Flow)

The README provides an example dispatcher script (`02-captive`) that:

1. **Trigger**: NetworkManager fires the dispatcher when interface state changes (`wlp3s0`, state `up`).
2. **Detect**: `curl http://portalcheck.yellowant.de` — if response ≠ "success", a captive portal is present.
3. **Identify**: `nmcli -t -f active,ssid dev wifi | egrep '^yes' | cut -d: -f2` — extracts the active SSID.
4. **Match**: Check if file `/etc/NetworkManager/dispatcher.d/captive.d/${SSID}` exists.
5. **Validate**: Regex check `[[ "$SSID" =~ [a-zA-Z0-9\!-:space:]* ]]` — basic path traversal guard.
6. **Execute**: Source the script (`. "/path/captive.d/$SSID"`) — runs in the dispatcher's shell context.

### 2.4 Configuration Format

**There is none.** The only "configuration" is:
- Drop a script into `captive.d/` named exactly after the target SSID
- The script must be executable
- For Python scripts: `#!/usr/bin/env python3` shebang
- For Bash scripts: `#!/bin/bash` shebang

The dispatcher sources Bash scripts directly (`. file`). Python scripts would need to be executed (`$SSID`) rather than sourced, but the README example uses sourcing — suggesting it was written primarily for Bash scripts and the Python ones may not work correctly with the example dispatcher as-is.

---

## 3. Portal Coverage

| Script | Portal | Country | Language | WiFi SSID (assumed) |
|--------|--------|---------|----------|---------------------|
| `OEBB` | ÖBB Railnet (Austrian Federal Railways) | AT | Python | `OEBB` |
| `WIFIonICE` | DB WIFIonICE (Deutsche Bahn ICE trains) | DE | Python | `WIFIonICE` |
| `generic_avm` | AVM Fritz!Box Guest WiFi | DE/AT/CH | Bash | `generic_avm` (or any Fritz!Box SSID) |

Total: **3 portals**, all German-speaking region, all transport/home-router category.

---

## 4. Auth Patterns

### 4.1 CSRF Token + Form POST (OEBB)

```python
# Step 1: Hit portal detection URL → get redirected to captive login page
session = requests.session()
resp = session.get("http://detectportal.firefox.com")

# Step 2: Parse HTML with BeautifulSoup, extract hidden form fields
bs = BeautifulSoup(resp.text, 'lxml')
token = bs.find("input", attrs={"name": "_token"})['value']
ceid = bs.find("input", attrs={"name": "_ceid"})['value']

# Step 3: POST form data with extracted tokens
resp_login = session.post("https://railnet.oebb.at/connecttoweb", data={
    '_token': token,
    '_ceid': ceid,
    'checkit': 'on',
    'form_type': 'registration'
}, headers={'referer': resp.url})
```

**Pattern**: `detectportal.firefox.com` → redirect → scrape HTML for `_token` + `_ceid` → POST to `connecttoweb`. No user credentials needed (accept-only).

### 4.2 CSRF Token + Form POST (WIFIonICE)

```python
# Step 1: Hit portal detection URL → get redirected
resp = session.get("http://detectportal.firefox.com")

# Step 2: Parse HTML, extract CSRF token
token = bs.find("input", attrs={"name": "CSRFToken"})['value']

# Step 3: POST with token + login flag
resp_login = session.post("http://www.wifionice.de/de/", data={
    'CSRFToken': token,
    'login': 'true'
})
```

**Pattern**: Same structure as OEBB but different token field name (`CSRFToken` vs `_token`/`_ceid`). Single token, no multi-field registration form. No user credentials.

### 4.3 Direct GET Accept (generic_avm)

```bash
curl "http://192.168.179.1:8186/trustme.lua?accept=yes"
```

**Pattern**: No detection redirect, no token extraction. Just a single GET request to a hardcoded IP with `accept=yes` query param. The simplest possible captive portal login — equivalent to our `fritzbox-guest.json` recipe.

### Auth Method Summary

| Method | Count | Portals |
|--------|-------|---------|
| Click-through (GET accept) | 1 | generic_avm |
| CSRF form POST (no credentials) | 2 | OEBB, WIFIonICE |
| Username/password form POST | 0 | — |
| JSON API | 0 | — |

---

## 5. Detection Mechanism

### 5.1 Portal Detection

Uses `http://portalcheck.yellowant.de` — a third-party captive portal detection service. If the response is not "success", a portal is assumed. This is similar to:
- Android's `http://connectivitycheck.gstatic.com/generate_204`
- Firefox's `http://detectportal.firefox.com`
- Apple's `http://captive.apple.com`

Interestingly, the scripts also use `detectportal.firefox.com` internally for the redirect-to-login-page flow, while the dispatcher uses `portalcheck.yellowant.de` for detection. These are two separate concerns:
1. **Detection** (dispatcher): Is there a portal? (`portalcheck.yellowant.de`)
2. **Entry point** (scripts): Get the login page HTML (`detectportal.firefox.com`)

### 5.2 Portal Matching

**Filename = SSID**. The dispatcher checks:

```bash
if [[ -f "/etc/NetworkManager/dispatcher.d/captive.d/${SSID}" ]]; then
```

This is a direct string match: SSID "WIFIonICE" → file `WIFIonICE`. No fuzzy matching, no domain-based detection, no content-based detection. The `generic_avm` script is presumably named after whatever SSID the user's Fritz!Box uses, or users rename it.

### 5.3 Security: Path Traversal Fix

A significant security vulnerability existed in the original dispatcher pattern. SSIDs can contain special characters. A malicious SSID like `../../etc/passwd` could cause the script to source arbitrary files.

**Fix** (commit `e22a459`, PR #3 by `felixdoerre`, Feb 2020): Added regex validation:

```bash
if [[ "$SSID" =~ [a-zA-Z0-9\!-:space:]* ]]; then
```

This restricts SSIDs to alphanumeric characters, `!`, and spaces. Notably absent: periods (`.`), slashes (`/`), hyphens (`-`), underscores (`_`) — meaning many real SSIDs (like `WIFIonICE` which works because it's pure alpha) would pass, but SSIDs with dots or hyphens would be rejected. This is a conservative whitelist approach.

---

## 6. System Integration

### 6.1 NetworkManager Dispatcher (Linux Desktop)

captive.d is designed for **NetworkManager's dispatcher system** on desktop Linux distributions. The user:

1. Creates `/etc/NetworkManager/dispatcher.d/02-captive` (the dispatcher script from README)
2. Creates `/etc/NetworkManager/dispatcher.d/captive.d/` directory
3. Copies portal scripts into this directory
4. Names each script to match the target SSID exactly

NetworkManager automatically calls dispatcher scripts on network state changes, passing the interface name and state as arguments.

### 6.2 NOT OpenWrt Compatible

This project is **not designed for OpenWrt**:
- Depends on NetworkManager (not available on OpenWrt)
- Uses `nmcli` for SSID detection
- Uses `python3` + `requests` + `bs4` (heavy dependencies for embedded routers)
- Sources scripts in bash (OpenWrt uses ash/busybox)
- Hardcoded desktop paths (`/etc/NetworkManager/`)

To use these patterns on OpenWrt, one would need to:
- Rewrite Python scripts in POSIX shell + curl
- Use `uci` or `iwinfo` instead of `nmcli` for SSID detection
- Use travelmate's detection mechanism instead of NetworkManager dispatchers

---

## 7. Comparison to Our Recipe JSON Format

### 7.1 Structural Comparison

| Aspect | captive.d | Our Recipe JSON |
|--------|-----------|-----------------|
| **Definition format** | Executable script files | JSON files with schema |
| **Matching** | Filename = SSID | `match.ssids`, `match.domains`, `match.paths`, `match.body_contains` |
| **Auth config** | Hardcoded in each script | `auth_type` + `params` fields |
| **Credentials** | None supported (all accept-only) | `"none"`, `"username_password"`, etc. |
| **Dependencies** | Python + requests + bs4, or bash + curl | POSIX shell + curl only |
| **Platform** | NetworkManager (desktop Linux) | OpenWrt (travelmate) |
| **Extensibility** | Add a new script file | Add a new JSON file |
| **Validation** | None (runtime only) | JSON schema validation possible |
| **Security** | Path traversal regex (incomplete) | No script execution risk (data-driven) |

### 7.2 Pattern Mapping: captive.d → Our Recipes

| captive.d Portal | Equivalent Recipe | Auth Pattern Mapping |
|------------------|-------------------|---------------------|
| `generic_avm` (Fritz!Box) | `fritzbox-guest.json` | Both: single GET to `trustme.lua?accept=yes`. Our recipe uses `form-submit` with `success_check: "empty_body"` |
| `WIFIonICE` (DB ICE) | `wifibahn.json` | Same portal, different approach: captive.d scrapes CSRFToken via BeautifulSoup; our recipe declares the form fields in JSON |
| `OEBB` (ÖBB) | No direct equivalent | CSRF token extraction pattern similar to `wifibahn.json` — could be expressed as a recipe with `extra_fields: "_token,_ceid"` |

### 7.3 What captive.d Does That Our Format Doesn't

1. **HTML parsing for dynamic tokens**: The Python scripts use BeautifulSoup to extract CSRF tokens from the login page HTML. Our JSON format currently relies on static field definitions — we'd need a `"token_extraction"` pattern to support this declaratively.

2. **Session cookies**: Python `requests.session()` automatically manages cookies across the redirect→scrape→POST flow. Our curl-based approach needs explicit cookie handling (`-c`/`-b` flags).

3. **Referer headers**: The OEBB script explicitly sets `headers={'referer': resp.url}`. Our recipe format doesn't currently support custom header injection.

---

## 8. What We Can Learn

### 8.1 Patterns Worth Adopting

1. **`detectportal.firefox.com` as universal entry point**: Both OEBB and WIFIonICE scripts start by hitting Firefox's portal detection URL. The captive portal intercepts this request and redirects to the actual login page. This is a reliable way to discover the login URL regardless of the specific portal implementation. We could add this as a standard `"detection_url"` field in our recipes.

2. **Convention-based naming for simple cases**: The filename=SSID approach, while too rigid as the sole mechanism, is an elegant default. A recipe named `wifionice.json` matching SSID `WIFIonICE` is intuitive. Our `match.ssids` field is more powerful but less discoverable.

3. **Click-through as first-class pattern**: The `generic_avm` script demonstrates that many captive portals need zero intelligence — just hit a URL. Our `fritzbox-guest.json` already handles this, but we should ensure our compiler treats click-through as the simplest base case with zero overhead.

### 8.2 Anti-Patterns to Avoid

1. **No config format**: captive.d's approach of "just write a script" doesn't scale. We can't validate, compile, or optimize scripts. Our JSON format is the right call.

2. **Python dependency**: Requiring `requests` + `bs4` on an embedded router is a non-starter. Sticking with POSIX shell + curl is correct for our target platform.

3. **Sourcing untrusted scripts**: The dispatcher sources (`. file`) the portal scripts, executing them in the same shell context. This is dangerous — a malicious or buggy script could break the dispatcher. Our approach of generating compiled shell functions from JSON is safer.

4. **SSID-only matching**: Real portals often share infrastructure (same login URL, different SSIDs). Domain-based and content-based matching (which we support) is essential for coverage.

5. **Incomplete path traversal fix**: The regex `[a-zA-Z0-9\!-:space:]*` is too restrictive (rejects valid SSIDs with dots, hyphens, underscores) yet potentially still exploitable depending on the shell implementation. Our data-driven JSON approach avoids this class of vulnerability entirely.

### 8.3 Potential Enhancements to Our Format

Based on captive.d patterns, consider adding:

| Enhancement | Why | Example |
|-------------|-----|---------|
| `"token_scraping"` field | Declaratively specify which HTML fields to extract before POST | `"token_fields": ["CSRFToken"]` |
| `"detection_url"` field | Allow recipes to specify which URL to hit first for redirect discovery | `"detection_url": "http://detectportal.firefox.com"` |
| `"custom_headers"` field | Support referer and other headers in POST requests | `"custom_headers": {"Referer": "$redirect_url"}` |
| `"session_cookies"` flag | Auto-enable curl cookie jar for multi-step flows | `"session_cookies": true` |

---

## 9. Attribution Notes

- **Author**: Janis Streib ([GitHub](https://github.com/janisstreib))
- **License**: BSD-3-Clause — permissive, compatible with our project
- **Security contributor**: Felix Dörre (`felixdoerre`) — path traversal fix (PR #3)
- **Repository**: https://github.com/janisstreib/captive.d
- **Topics**: wifi, captive-portal, network-manager, avm, wifionice, oebb

If we adopt patterns from captive.d (particularly the `detectportal.firefox.com` redirect technique or CSRF token extraction logic), attribution should reference:

> Based on patterns from janisstreib/captive.d (BSD-3-Clause)
> https://github.com/janisstreib/captive.d

The ÖBB and WIFIonICE login flows documented here may be useful as reference implementations when creating or validating our own recipes for these portals.

---

## Appendix A: Full Source Code

### A.1 `generic_avm` (Bash — 3 lines)

```bash
#!/bin/bash
curl "http://192.168.179.1:8186/trustme.lua?accept=yes"
```

### A.2 `WIFIonICE` (Python — 12 lines)

```python
#!/usr/bin/env python3
import requests
from bs4 import BeautifulSoup

session = requests.session()
resp = session.get("http://detectportal.firefox.com")
bs = BeautifulSoup(resp.text, 'lxml')
token = bs.find("input", attrs={"name": "CSRFToken"})['value']
print("Token:", token)
resp_login = session.post("http://www.wifionice.de/de/", data={
    'CSRFToken': token,
    'login': 'true'
    })
print(resp_login)
```

### A.3 `OEBB` (Python — 18 lines)

```python
#!/usr/bin/env python3
import requests
from bs4 import BeautifulSoup

session = requests.session()
resp = session.get("http://detectportal.firefox.com")
bs = BeautifulSoup(resp.text, 'lxml')
token = bs.find("input", attrs={"name": "_token"})['value']
ceid = bs.find("input", attrs={"name": "_ceid"})['value']
print("Token:", token, "CEID:", ceid)
print("url:", resp.url)
resp_login = session.post("https://railnet.oebb.at/connecttoweb", data={
    '_token': token,
    '_ceid': ceid,
    'checkit': 'on',
    'form_type': 'registration'
    },
    headers={'referer': resp.url})
print(resp_login)
```

### A.4 Dispatcher Script (from README)

```bash
#!/bin/bash
INTERFACE=$1
STATE=$2
if [[ $INTERFACE = 'wlp3s0' &&  $STATE = 'up' ]]; then
    PORTALCHECK=`curl http://portalcheck.yellowant.de`
    if [[ "$PORTALCHECK" != "success" ]]; then
        echo "Captive Portal detected!"
        SSID=`nmcli -t -f active,ssid dev wifi | egrep '^yes' | cut -d: -f2`
        echo "SSID: $SSID"
        if [[ -f "/etc/NetworkManager/dispatcher.d/captive.d/${SSID}" ]]; then
            if [[ "$SSID" =~ [a-zA-Z0-9\!-:space:]* ]]; then
                echo "Running command \"/etc/NetworkManager/dispatcher.d/captive.d/$SSID\""
                . "/etc/NetworkManager/dispatcher.d/captive.d/$SSID"
            else
                echo "Invalid SSID!"
            fi
        else
            echo "No profile found."
        fi
    fi
fi
```

---

## Appendix B: Commit History

| Date | Hash | Message | Author |
|------|------|---------|--------|
| 2020-02-24 | `bc9a0c5` | Merge branch 'master' | janisstreib |
| 2020-02-24 | `6b8f83c` | UPD: enhanced sample script | janisstreib |
| 2020-02-09 | `3edcc80` | Merge pull request #3 (path traversal fix) | janisstreib |
| 2020-02-09 | `e22a459` | fix path traversal vulnerability | felixdoerre |
| 2019-11-04 | `a957017` | Update README.md | janisstreib |
| 2019-11-04 | `8e8ee1f` | Update LICENSE | janisstreib |
| 2019-08-18 | `0265d13` | ADD: more readme | janisstreib |
| 2019-08-18 | `7329142` | FIX: correct wifi on ice login | janisstreib |
| 2019-08-18 | `00551a9` | ADD: better check url | janisstreib |
| 2019-08-18 | `dde4145` | ADD: readme | janisstreib |
| 2019-08-18 | `747ac73` | INIT | janisstreib |
