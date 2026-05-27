# nicoh88/captive-portal-auto-login-bash — Research Report

> Research document for the captive-portal-recipes compiler project.
> Target: `github.com/nicoh88/captive-portal-auto-login-bash`
> Date: 2026-05-26
> Status: **PROJECT NOT FOUND — presumed deleted/never existed**

---

## 1. Search Results

### 1.1 What We Searched For

We attempted **10 distinct search strategies** to locate the repository `nicoh88/captive-portal-auto-login-bash`:

| # | Strategy | Result |
|---|----------|--------|
| 1 | Direct API check: `api.github.com/repos/nicoh88/captive-portal-auto-login-bash` | **404 Not Found** |
| 2 | List all nicoh88 repos (17 public repos) | No captive portal repo found |
| 3 | List all nicoh88 gists (2 gists) | One about OpenWRT+Telekom FTTH, no captive portal |
| 4 | GitHub search: `captive-portal-auto-login-bash` (repos) | **0 results** |
| 5 | GitHub search: `captive-portal-auto-login-bash` (code) | **0 results** |
| 6 | GitHub search: `user:nicoh88 captive` (repos) | **0 results** |
| 7 | Web search: `nicoh88 captive portal auto login bash` | No direct hits |
| 8 | Web search: `loggn.de captive portal openwrt` (nicoh88's blog) | **0 search results** on blog |
| 9 | Wayback Machine CDX API: `github.com/nicoh88/captive*` | **No archived snapshots** |
| 10 | Web search: `site:web.archive.org nicoh88 captive portal` | **No results** |

### 1.2 Verdict

**The repository `nicoh88/captive-portal-auto-login-bash` does not exist and likely never existed.**

Possible explanations:
- The repo name may have been misremembered or misreported.
- nicoh88 may have created and deleted it between crawl intervals.
- The project may have existed as a private repo or a gist that was later removed.
- The reference may have been to a different user or a different project entirely.

### 1.3 What We Know About nicoh88

| Field | Value |
|-------|-------|
| **GitHub login** | `nicoh88` |
| **Real name** | Nico Hartung |
| **Location** | Deutschland (Germany) |
| **Blog** | [loggn.de](https://www.loggn.de) |
| **Public repos** | 17 |
| **Public gists** | 2 |
| **Account created** | 2010-05-04 |
| **Focus areas** | Checkmk/Nagios monitoring, FRITZ!Box, CrowdSec, OpenWrt networking |

nicoh88's repos are primarily monitoring plugins (Checkmk, CrowdSec, Shorewall, nftables) and utility scripts (FRITZ!Box reboot, Sonos reboot). He has **one OpenWrt-related gist**: configuring Deutsche Telekom FTTH access with OpenWrt (PPPoE, VLAN 7). This confirms OpenWrt familiarity but the blog search for "captive portal" returned zero results.

---

## 2. Alternative Bash-Based Captive Portal Projects Discovered

Since the target project was not found, we surveyed the broader landscape of bash/shell-based captive portal auto-login projects. These are the most relevant alternatives.

### 2.1 OpenWrt Travelmate Login Scripts (Best Match)

| Field | Value |
|-------|-------|
| **Project** | Travelmate — captive portal auto-login scripts |
| **Repository** | [openwrt/packages — net/travelmate/files](https://github.com/openwrt/packages/tree/master/net/travelmate/files) |
| **Maintainer** | Dirk Brenken (`dibdot`) |
| **License** | GPL-3.0 |
| **Platform** | OpenWrt |
| **Language** | POSIX shell (`#!/bin/sh`) |

**Portal coverage:**

| Script | Portal | Auth Method |
|--------|--------|-------------|
| `telekom.login` | Telekom HotSpot (DE), hotspot.t-mobile.net | WiSGri XML redirect → POST with username/password |
| `wifibahn.login` | DB Bahn/ICE WiFi (DE), wifi.bahn.de | CSRF token from cookie → POST |
| `vodafone.login` | Vodafone Hotspot (DE), hotspot.vodafone.de | Multi-step: redirect→SID→session JSON→login with profile selection |
| `generic-user-pass.login` | Template for any portal | Simple POST with username/password (user configures domain) |

**Key patterns (see full analysis in `travelmate.md`):**
- Uses travelmate's internal functions (`trm_fetch`, `trm_fetchparm`, `trm_useragent`, `trm_captiveurl`)
- Exit codes: `0` = success, `1` = DNS/connectivity fail, `2` = token extraction fail, `255` = login fail
- URL-encoding helper for credentials
- CSRF token extraction from cookies
- WiSGri XML parsing with awk

### 2.2 janisstreib/captive.d

| Field | Value |
|-------|-------|
| **Repository** | [janisstreib/captive.d](https://github.com/janisstreib/captive.d) |
| **License** | BSD-3-Clause |
| **Language** | Python 3 + Bash |
| **Stars** | 6 |
| **Created** | 2019-08-18 |
| **Last updated** | 2025-09-30 |
| **Topics** | avm, captive-portal, network-manager, oebb, wifi, wifionice |

**Portal coverage:**

| Script | Portal | Language | Auth Method |
|--------|--------|----------|-------------|
| `generic_avm` | AVM FRITZ!Box captive portals | Bash | Single GET: `curl "http://192.168.179.1:8186/trustme.lua?accept=yes"` |
| `WIFIonICE` | Deutsche Bahn ICE WiFi | Python 3 | CSRF token from HTML → POST with token |
| `OEBB` | ÖBB (Austrian Rail) WiFi | Python 3 | Token/CEID from HTML → POST with form data |

**Integration model:** NetworkManager dispatcher.d scripts. On interface up, checks connectivity, detects SSID, runs matching script from `captive.d/` directory by SSID name.

**Key pattern — the AVM one-liner (bash):**
```bash
curl "http://192.168.179.1:8186/trustme.lua?accept=yes"
```

**Key pattern — NetworkManager integration:**
```bash
INTERFACE=$1; STATE=$2
if [[ $INTERFACE = 'wlp3s0' && $STATE = 'up' ]]; then
    PORTALCHECK=$(curl http://portalcheck.yellowant.de)
    if [[ "$PORTALCHECK" != "success" ]]; then
        SSID=$(nmcli -t -f active,ssid dev wifi | egrep '^yes' | cut -d: -f2)
        if [[ -f "/etc/NetworkManager/dispatcher.d/captive.d/${SSID}" ]]; then
            . "/etc/NetworkManager/dispatcher.d/captive.d/$SSID"
        fi
    fi
fi
```

### 2.3 FON / NOS Auto-Login (OpenWrt Hotplug)

| Field | Value |
|-------|-------|
| **Source** | [gist: cusspvz/3ab1ea9110f4ef87f0d2e1cd134aca67](https://gist.github.com/cusspvz/3ab1ea9110f4ef87f0d2e1cd134aca67) |
| **Fork** | [gist: dks77 — Telekom_FON variant](https://gist.github.com/25822228910985159b251d9892d5201e) |
| **Platform** | OpenWrt |
| **Language** | Shell (`#!/bin/sh`) |
| **Integration** | `/etc/hotplug.d/iface/` |

**Auth flow:**
1. Triggered on `ifup`/`update` net events
2. `curl` a target URL (e.g., `http://google.com`)
3. Parse HTML for `<LoginURL>` (WiSGri pattern)
4. POST credentials to extracted URL
5. Parse response for `<LogoffURL>` to confirm success

**Key pattern — WiSGri XML extraction:**
```sh
POST_URL=$(echo "$DATA" | grep '<LoginURL>' | cut -d '<' -f 2 | cut -d '>' -f 2 | sed -r 's/\&amp;/\&/g')
curl --cookie-jar $COOKIE_JAR \
     --data "UserName=${FON_USERNAME}&Password=${FON_PASSWORD}" \
     "$POST_URL"
LOGOFF_URL=$(echo "$DATA" | grep '<LogoffURL>' | cut -d '<' -f 2 | cut -d '>' -f 2)
```

### 2.4 EE/BT WiFi Autologin (OpenWrt)

| Field | Value |
|-------|-------|
| **Repository** | [aidanmacgregor/BTWi-Fi_Autologin_-_OpenWRT](https://github.com/aidanmacgregor/BTWi-Fi_Autologin_-_OpenWRT) |
| **Platform** | OpenWrt |
| **Language** | Shell |
| **Features** | Service daemon, TLS handling, LED/theme support |

**Auth pattern:**
- Runs as continuous background service (start/stop with PID files)
- Periodically checks connectivity via ping
- On disconnect, POSTs credentials to `ee-wifi.ee.co.uk` endpoint
- Handles TLS certificate installation automatically
- Log rotation

### 2.5 OpenWrt Network Watchdog

| Field | Value |
|-------|-------|
| **Repository** | [xunchahaha/OpenWrt-Network-Watchdog](https://github.com/xunchahaha/OpenWrt-Network-Watchdog) |
| **Platform** | OpenWrt/Kwrt |
| **Language** | Shell + Batchfile (Windows generator) |
| **Stars** | 4 |

**Auth approach:**
- Windows tool captures browser cURL from DevTools
- Generates shell script with dynamic IP/MAC replacement
- Cron-based execution (every minute)
- Handles campus network re-authentication after DHCP renewal

### 2.6 Unifi Portal Login (Bash Gist)

| Field | Value |
|-------|-------|
| **Source** | [gist: jenda122](https://gist.github.com/jenda122/3d6619d00a134cf71d80280a90da61c0) |
| **Platform** | Linux |
| **Language** | Bash |
| **Target** | Ubiquiti UniFi captive portals |

**Auth flow:**
```bash
# 1. Hit captive portal check, get redirect URL + cookies
wget --save-cookies $COOKIE_JAR http://detectportal.firefox.com/success.txt
login_page_url=$(grep "^Location: http" /tmp/portal-output.txt | cut -d " " -f 2)
login_page_base=$(echo "$login_page_url" | cut -d / -f 1-3)

# 2. POST to login endpoint with Referer + cookies
wget --header="Referer: $login_page_url" \
     --load-cookies $COOKIE_JAR \
     --post-data "{}" \
     "$login_page_base/guest/s/default/login?t=$timestamp"
```

### 2.7 Telekom FON Hotspot (German)

| Field | Value |
|-------|-------|
| **Source** | [gist: dks77 — Telekom_FON](https://gist.github.com/25822228910985159b251d9892d5201e) |
| **Platform** | OpenWrt |
| **Language** | Shell |

This is the German Telekom FON variant of the FON/NOS script above. Uses WiSGri `<LoginURL>` extraction pattern. Notable for proper URL-encoded credential handling.

### 2.8 Additional Projects (Non-Bash, for Reference)

| Project | Language | Target |
|---------|----------|--------|
| [binarynoise/CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin) | Kotlin | Android + Linux, multi-portal |
| [SadeghHayeri/Mili](https://github.com/SadeghHayeri/Mili) | Shell | MikroTik captive portals, macOS + Linux |
| [denizsafak/HotspotAutoLogin](https://github.com/denizsafak/HotspotAutoLogin) | Python | Multi-SSID, config-driven |
| [fathonix/MikrotikCaptiveAutologin](https://github.com/fathonix/MikrotikCaptiveAutologin) | JavaScript/Node.js | MikroTik with MD5 password hashing |
| [berrabe/autologin-captive-portal-mikrotik](https://github.com/berrabe/autologin-captive-portal-mikrotik) | Bash | MikroTik CLI login |
| [charlie0129/bupt-net-login](https://github.com/charlie0129/bupt-net-login) | Bash | BUPT campus, AC redirect handling |

---

## 3. Common Bash Auth Patterns Across Projects

Analyzing all bash/shell captive portal auto-login projects reveals several recurring patterns:

### 3.1 Portal Detection

All projects use one of these methods:

```bash
# Method 1: HTTP status check (most common)
curl -s -o /dev/null -w "%{http_code}" http://captive.apple.com/hotspot-detect.html
# 200 = captive portal, 204 = free internet

# Method 2: Content check
curl http://detectportal.firefox.com/success.txt
# "success" = free, anything else = captive

# Method 3: Ping-based (OpenWrt watchdog style)
ping -c 1 -W 4 8.8.8.8
# exit code 0 = online, else = captive likely

# Method 4: Travelmate internal
"${trm_fetch}" ${trm_fetchparm} "${trm_captiveurl}"
# parses redirect/response for portal markers
```

### 3.2 Auth Flow Patterns

**Pattern A: Simple GET/POST (easiest portals)**
```bash
# AVM FRITZ!Box style — just hit accept URL
curl "http://192.168.179.1:8186/trustme.lua?accept=yes"

# Simple credential POST
curl --data "username=$USER&password=$PASS" "http://portal.example.com/login"
```

**Pattern B: Token Extraction → POST (CSRF-based portals)**
```bash
# Step 1: Get CSRF token from initial page
TOKEN=$(curl -s -c /tmp/cookies.txt "$PORTAL_URL" | parse_token)
# Step 2: POST with token
curl -b /tmp/cookies.txt --data "CSRFToken=$TOKEN&login=true" "$PORTAL_URL"
```

**Pattern C: WiSGri XML (FON/Telekom hotspots)**
```bash
# Step 1: Get redirected page with XML
DATA=$(curl -L http://google.com)
# Step 2: Extract LoginURL from XML
LOGIN_URL=$(echo "$DATA" | grep '<LoginURL>' | cut -d'>' -f2 | cut -d'<' -f1 | sed 's/\&amp;/\&/g')
# Step 3: POST credentials to extracted URL
RESPONSE=$(curl -L -c cookies.txt --data "UserName=$USER&Password=$PASS" "$LOGIN_URL")
# Step 4: Verify via LogoffURL
LOGOFF_URL=$(echo "$RESPONSE" | grep '<LogoffURL>' | cut -d'>' -f2 | cut -d'<' -f1)
```

**Pattern D: Multi-step JSON API (Vodafone-style)**
```bash
# Step 1: Get session SID from redirect
SID=$(curl -w "%{redirect_url}" "$CAPTIVE_URL" | extract_sid)
# Step 2: Get session token
SESSION=$(curl "$API/session?sid=$SID" | jsonfilter -e '@.session')
# Step 3: Login with session + credentials
curl --data "session=$SESSION&username=$USER&password=$PASS" "$API/login?sid=$SID"
```

### 3.3 OpenWrt Integration Points

| Method | Location | Trigger |
|--------|----------|---------|
| **Hotplug** | `/etc/hotplug.d/iface/` | Interface up/down events |
| **Cron** | `crontab -e` | Periodic (every 1-5 minutes) |
| **Travelmate** | `/etc/travelmate/*.login` | Travelmate portal detection |
| **RC.local** | `/etc/rc.local` | Boot-time only |
| **Init.d service** | `/etc/init.d/` | Daemon with PID management |

### 3.4 Tools Used

| Tool | Usage | OpenWrt Package |
|------|-------|-----------------|
| `curl` | HTTP requests (POST/GET with cookies/headers) | `curl` |
| `wget` | Alternative HTTP client (smaller footprint) | `wget` |
| `awk` | HTML/XML parsing, token extraction | built-in (BusyBox) |
| `jsonfilter` | JSON parsing on OpenWrt | built-in |
| `logger` | Syslog output | built-in |
| `nslookup` | DNS resolution checks | built-in |

---

## 4. What We Can Learn

### 4.1 From nicoh88's Profile

Although the captive portal repo was not found, nicoh88's OpenWrt expertise is confirmed by:
- A detailed gist on configuring Deutsche Telekom FTTH with OpenWrt (PPPoE + VLAN 7)
- Monitoring-focused repos (Checkmk, CrowdSec, nftables, Shorewall)
- German-language blog at loggn.de

If a captive portal script existed, it would likely have targeted **German portals** (Telekom HotSpot, Vodafone, DB WiFi) and been written for **OpenWrt hotplug integration**.

### 4.2 From the Broader Bash/Shell Landscape

**Key takeaways for our recipe compiler:**

1. **Three dominant auth patterns** cover most portals: simple POST, CSRF token exchange, and WiSGri XML redirect chains.

2. **Cookie management is critical** — most portals require session cookies from the initial redirect to be preserved through the login POST.

3. **URL encoding** — credentials often need URL encoding (`@` → `%40`). Travelmate includes a `urlencode()` helper; most gists hardcode encoded values.

4. **Exit codes matter** — Travelmate uses a convention: `0` = success, `1-254` = specific failure, `255` = generic failure. Our compiler should adopt this.

5. **SSID-based routing** — The `captive.d` pattern of naming scripts by SSID and auto-selecting based on current network is elegant for multi-portal scenarios.

6. **OpenWrt-specific constraints** — Scripts must use POSIX sh (not bash), must not assume bash-isms like `[[ ]]`, and should prefer BusyBox `wget` or `curl` depending on installed packages.

---

## 5. Attribution Notes

- All data sourced from public GitHub repositories and the GitHub API.
- The repository `nicoh88/captive-portal-auto-login-bash` was referenced as a target but **could not be found** via any search method. It may have been deleted, renamed, or may never have existed under that exact name.
- nicoh88's public profile confirms 17 repos and 2 gists, none of which are captive-portal-related.
- Alternative project analysis is based on publicly available source code and documentation.
- The Wayback Machine (archive.org) has no archived snapshots of the target URL.

---

## 6. Appendix: nicoh88's Public Repositories

| Repo | Description |
|------|-------------|
| `checkmk-agent-based-crowdsec-plugin` | CrowdSec monitoring for Checkmk |
| `checkmk-agent-based-nftables-plugin` | nftables monitoring for Checkmk |
| `checkmk-agent-based-shorewall-plugin` | Shorewall firewall monitoring for Checkmk |
| `check_time_machine_currency_afp-share` | Time Machine check for AFP shares |
| `cmk_notification_playsms` | Check_MK notification via playSMS |
| `cmk_notification_sms-lox24` | Check_MK notification via LOX24 SMS |
| `cmk_plugin_smart-standby-friendly` | HDD standby/spindown monitoring |
| `cron_fritzbox-reboot` | FRITZ!Box scheduled reboot |
| `cron_sonos-reboot` | Sonos speaker scheduled reboot |
| `crowdsec-hub` | Fork of CrowdSec scenarios/parsers |
| (7 more repos, all monitoring/utility focused) | — |
