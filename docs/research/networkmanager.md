# NetworkManager Captive Portal Handling

> Research document for the captive-portal-recipes project.
> Covers NetworkManager's connectivity check, dispatcher system, desktop integration,
> and existing auto-login integrations.

---

## 1. Overview

NetworkManager (NM) is the standard network management daemon on most Linux distributions. It manages Ethernet, Wi-Fi, WWAN, and VPN connections via D-Bus, exposing a rich API for both system services and user applications.

### Captive Portal Detection in NetworkManager

NetworkManager includes an **optional connectivity checking** subsystem that can detect captive portals. This is **not** an auto-login tool. NM's role is limited to:

1. **Detecting** that the network is behind a captive portal
2. **Exposing** the connectivity state on D-Bus
3. **Triggering** dispatcher scripts so external tools can react
4. **Adjusting** route metrics so connections with full connectivity are preferred

The actual portal login is left to desktop environments (GNOME, KDE, elementary), user scripts, or tools like this project.

---

## 2. Connectivity Check System

### 2.1 HTTP Probe Mechanism

NetworkManager periodically sends an HTTP GET request to a configurable URI. Based on the response, it classifies connectivity into one of five states.

**Two probe modes exist:**

| Mode | Configuration | Success Criteria |
|------|--------------|-----------------|
| **Content match** | `response="NetworkManager is online"` | HTTP 200 + body starts with configured string |
| **HTTP 204** | `response=""` (empty) | HTTP 204 No Content |

For content match mode, NM also checks for a response header `X-NetworkManager-Status: online` first.

**When a captive portal intercepts the request**, the response will not match the expected content or status code, and NM classifies the connection as `PORTAL`.

### 2.2 Configuration

The connectivity check is configured in `/etc/NetworkManager/NetworkManager.conf` or drop-in files under `/etc/NetworkManager/conf.d/`:

```ini
[connectivity]
enabled=true
uri=http://fedoraproject.org/static/hotspot.txt
response=OK
interval=300
```

**Key options:**

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Master toggle. Also requires `uri` to be set. |
| `uri` | *(unset)* | HTTP URL to probe. Must be plain HTTP (not HTTPS) for portals to intercept. |
| `response` | `"NetworkManager is online"` | Expected response body prefix. Empty string = expect HTTP 204. |
| `interval` | `300` | Seconds between checks. `0` disables. |

**Distribution defaults:**

| Distribution | URI | Response |
|---|---|---|
| Fedora | `http://fedoraproject.org/static/hotspot.txt` | `OK` |
| Debian/Ubuntu | `http://network-test.debian.org/nm` | `NetworkManager is online` |
| Arch Linux | `http://ping.archlinux.org` | *(default)* |
| GNOME (fallback) | `http://nmcheck.gnome.org` | *(default)* |

**Critical note:** The URI must use plain HTTP. If the domain has HSTS enabled, browsers will refuse to load the probe page over HTTP, breaking captive portal detection. This is a known issue with Fedora's `fedoraproject.org` probe. The workaround is to configure a custom HTTP-only endpoint.

### 2.3 Connectivity States

From the `NMConnectivityState` enum (D-Bus API):

| State | Value | Meaning |
|-------|-------|---------|
| `NM_CONNECTIVITY_UNKNOWN` | `0` | Check disabled or not yet run |
| `NM_CONNECTIVITY_NONE` | `1` | No network connection |
| `NM_CONNECTIVITY_PORTAL` | `2` | Behind a captive portal (response did not match expected) |
| `NM_CONNECTIVITY_LIMITED` | `3` | Connected to network, no Internet, no portal detected |
| `NM_CONNECTIVITY_FULL` | `4` | Full Internet access |

The distinction between `PORTAL` and `LIMITED` is important:
- **PORTAL**: The connectivity probe got a response, but it didn't match expectations (likely intercepted by portal)
- **LIMITED**: The probe failed entirely (transport error, timeout) without matching portal behavior

### 2.4 Route Metric Penalty

When connectivity checking is enabled, devices without full connectivity get a route metric penalty of **+20000**. This means if you have both WWAN and Wi-Fi connected, and Wi-Fi is behind a captive portal, WWAN traffic is preferred until the user logs into the portal.

### 2.5 Per-Device Checking

NM performs connectivity checks per device using `SO_BINDTODEVICE` to send requests on each interface independently. This requires `rp_filter` (reverse path filtering) to be set to loose mode; strict mode will reject responses from non-default interfaces.

### 2.6 Checking Connectivity via nmcli

```bash
# Show current connectivity state (cached)
nmcli general status

# Force a fresh connectivity check
nmcli networking connectivity check

# Script-friendly: just the state
nmcli -t -f CONNECTIVITY general status
```

Output values: `none`, `portal`, `limited`, `full`, `unknown`.

### 2.7 D-Bus API

The `org.freedesktop.NetworkManager` D-Bus interface exposes:

- **`Connectivity` property** (`u`): The current `NMConnectivityState` value
- **`CheckConnectivity()` method**: Triggers an immediate re-check
- **`ConnectivityCheckUri` property**: The configured probe URI

---

## 3. Dispatcher System

### 3.1 Overview

`NetworkManager-dispatcher` is a D-Bus activated service that executes user-provided scripts in response to network events. Scripts are placed in `/{etc,usr/lib}/NetworkManager/dispatcher.d/` and run in alphabetical order.

**Requirements for dispatcher scripts:**
- Must be a regular executable file
- Owned by `root`
- Not writable by group or other
- Not setuid

### 3.2 Actions (Hook Points)

| Action | Description | Script Location |
|--------|-------------|----------------|
| `pre-up` | Interface connected but not fully activated. NM waits for scripts. | `dispatcher.d/pre-up.d/` |
| `up` | Interface fully activated | `dispatcher.d/` |
| `pre-down` | Interface about to be deactivated. NM waits for scripts. | `dispatcher.d/pre-down.d/` |
| `down` | Interface deactivated | `dispatcher.d/` |
| `vpn-pre-up` | VPN connected, not fully activated | `dispatcher.d/pre-up.d/` |
| `vpn-up` | VPN activated | `dispatcher.d/` |
| `vpn-pre-down` | VPN about to be deactivated | `dispatcher.d/pre-down.d/` |
| `vpn-down` | VPN deactivated | `dispatcher.d/` |
| `hostname` | System hostname updated | `dispatcher.d/` |
| `dhcp4-change` | DHCPv4 lease changed | `dispatcher.d/` |
| `dhcp6-change` | DHCPv6 lease changed | `dispatcher.d/` |
| `connectivity-change` | Network connectivity state changed | `dispatcher.d/` |
| `dns-change` | DNS configuration changed | `dispatcher.d/` |

### 3.3 Arguments

Each script receives two positional arguments:

```
$1 = interface name (e.g., "wlp3s0", "enp0s25") — empty for connectivity-change/dns-change
$2 = action (e.g., "up", "connectivity-change")
```

### 3.4 Environment Variables

The full set of environment variables available to dispatcher scripts:

#### Connection Metadata

| Variable | Description |
|----------|-------------|
| `NM_DISPATCHER_ACTION` | Action name, identical to `$2`. Since NM 1.12.0. |
| `CONNECTION_UUID` | UUID of the connection profile |
| `CONNECTION_ID` | Name (ID) of the connection profile |
| `CONNECTION_DBUS_PATH` | D-Bus path of the connection |
| `CONNECTION_FILENAME` | File path of the connection profile (e.g., `/etc/NetworkManager/system-connections/MyWiFi.nmconnection`) |
| `CONNECTION_EXTERNAL` | Whether the connection was created externally to NM |

#### Device Information

| Variable | Description |
|----------|-------------|
| `DEVICE_IFACE` | Kernel interface name (e.g., `wlp3s0`) |
| `DEVICE_IP_IFACE` | IP interface name (where IP addresses/routes are configured) |

#### IPv4 Configuration

| Variable | Description |
|----------|-------------|
| `IP4_ADDRESS_0` | Format: `"address/prefix gateway"` (gateway deprecated, use `IP4_GATEWAY`) |
| `IP4_NUM_ADDRESSES` | Number of IPv4 addresses |
| `IP4_GATEWAY` | IPv4 gateway |
| `IP4_ROUTE_0` | IPv4 route entries |
| `IP4_NUM_ROUTES` | Number of IPv4 routes |
| `IP4_NAMESERVERS` | Space-separated DNS servers |
| `IP4_DOMAINS` | Space-separated search domains |

#### IPv6 Configuration

Same pattern with `IP6_` prefix: `IP6_ADDRESS_0`, `IP6_NUM_ADDRESSES`, `IP6_GATEWAY`, `IP6_ROUTE_0`, `IP6_NUM_ROUTES`, `IP6_NAMESERVERS`, `IP6_DOMAINS`.

#### DHCP

| Variable | Description |
|----------|-------------|
| `DHCP4_<OPTION>` | DHCPv4 options, e.g., `DHCP4_HOST_NAME=foobar` |
| `DHCP6_<OPTION>` | DHCPv6 options (same pattern) |

#### VPN

When a VPN is active, additional variables are set: `VPN_IP_IFACE`, `VPN_IP4_ADDRESS_0`, `VPN_IP4_NUM_ADDRESSES`, etc.

#### Connectivity State

| Variable | Description |
|----------|-------------|
| `CONNECTIVITY_STATE` | One of: `UNKNOWN`, `NONE`, `PORTAL`, `LIMITED`, `FULL`. **Only set for `connectivity-change` action.** |

#### User Data

Connection profile `user` data keys are encoded as `CONNECTION_USER_<ENCODED_KEY>`. Encoding rules:
- Lowercase letters become uppercase
- Uppercase letters are prefixed by their 3-digit octal representation
- Digits, underscores, and periods are unchanged
- Example: key `test.foo-Bar2` becomes `CONNECTION_USER_TEST__FOO_055_BAR2`

### 3.5 Special Subdirectories

| Directory | Purpose |
|-----------|---------|
| `dispatcher.d/pre-up.d/` | Scripts for `pre-up` and `vpn-pre-up` actions. NM blocks until these complete. |
| `dispatcher.d/pre-down.d/` | Scripts for `pre-down` and `vpn-pre-down` actions. NM blocks until these complete. |
| `dispatcher.d/no-wait.d/` | Symlink targets for scripts that should run in parallel without waiting. |

### 3.6 Execution Semantics

- Scripts run **one at a time** (sequentially, in alphabetical order)
- Run **asynchronously** from the main NM process
- Scripts are **killed if they run too long**
- Once queued, a script **always runs** even if a later event renders it obsolete
- For long-running tasks, **spawn a child process** and have the parent return immediately
- Scripts in `no-wait.d/` run in parallel without waiting for previous scripts

### 3.7 Example Dispatcher Script for Captive Portal Detection

From the Arch Wiki, a classic example that opens a browser when NM detects a portal:

```bash
#!/bin/sh
# /etc/NetworkManager/dispatcher.d/90-open_captive_portal

case "$2" in
    connectivity-change)
        if [ "$CONNECTIVITY_STATE" = "PORTAL" ]; then
            # Get logged-in user and display
            who | awk '$NF ~ /\(:[0-9]+\)/ { print $1 " " substr($NF, 2, length($NF)-2) };' | \
            while read user display; do
                export DISPLAY="$display"
                sudo -u "$user" xdg-open "http://nmcheck.gnome.org" 2>/dev/null
            done
        fi
        ;;
esac
```

### 3.8 Minimal Dispatcher Script Template

```bash
#!/bin/bash
# /etc/NetworkManager/dispatcher.d/50-captive-autologin
# Triggers on connectivity change to PORTAL state

INTERFACE="$1"
ACTION="$2"

case "$ACTION" in
    connectivity-change)
        if [ "$CONNECTIVITY_STATE" = "PORTAL" ]; then
            # Get SSID for Wi-Fi connections
            SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
            logger "Captive portal detected on $INTERFACE (SSID: $SSID)"

            # Spawn background process to handle login
            /usr/local/bin/captive-autologin "$SSID" "$INTERFACE" &
        fi
        ;;
    up)
        # Interface just came up - connectivity check will run shortly
        logger "Interface $INTERFACE is up, waiting for connectivity check"
        ;;
esac

exit 0
```

---

## 4. GNOME Integration

### 4.1 GNOME Shell Portal Helper

GNOME Shell includes a built-in captive portal helper (`gnome-shell` portal-helper component). When NetworkManager reports `Connectivity = PORTAL` on D-Bus:

1. **GNOME 3.14–3.36**: The portal helper window opens immediately
2. **GNOME 3.36+**: A notification is shown first; the portal helper opens when the user clicks it

The portal helper is a **sandboxed WebKitGTK browser** that loads `http://nmcheck.gnome.org/`. Because the connection is behind a captive portal, this request is intercepted and the portal's login page is displayed instead.

### 4.2 Security Architecture

Beginning with GNOME 3.36, the portal helper uses **WebKitGTK's sandbox** (`webkit_web_context_set_sandbox_enabled()`). This is critical because:

- The portal helper loads **arbitrary web content** from untrusted networks
- An attacker on the network could inject malicious content
- The sandbox prevents compromise of the user's system even if WebKit has vulnerabilities
- The portal helper **bypasses proxy and VPN settings** to reach the portal directly

### 4.3 GNOME Settings

GNOME Settings (formerly GNOME Control Center) shows the Wi-Fi connection as having "Limited connectivity" when NM reports the `PORTAL` state. The "Sign In" button triggers the portal helper.

### 4.4 Epiphany (GNOME Web)

Epiphany also monitors connectivity via `GNetworkMonitor`. When `connectivity == G_NETWORK_CONNECTIVITY_PORTAL`, it automatically loads `http://nmcheck.gnome.org/` in the active window.

### 4.5 Other Desktop Environments

| Desktop | Portal Handler |
|---------|---------------|
| GNOME | Built-in `gnome-shell` portal-helper (WebKitGTK sandbox) |
| KDE Plasma | `plasma-nm` detects portal, opens `http://networkcheck.kde.org/` in browser |
| elementary OS | `capnet-assist` (WebKitGTK, Vala) |
| None / Minimal | Manual: dispatcher scripts or CLI tools |

---

## 5. Existing Auto-Login Integrations

### 5.1 Seme4eg/captive-portal-sh

A NetworkManager dispatcher script that automatically detects and opens captive portal URLs.

- **URL**: https://github.com/Seme4eg/captive-portal-sh
- **Mechanism**: Installs as `/etc/NetworkManager/dispatcher.d/90-open_captive_portal`
- **Target**: Wayland users without a desktop environment handling portals
- **Approach**: Listens for `connectivity-change` events, determines the portal URL, opens it in the default browser
- **Limitation**: Opens the portal in a browser for manual login — does not auto-authenticate

### 5.2 makefu/prison-break

A Python-based auto-login tool for specific German captive portals (Deutsche Bahn WIFIonICE, Hotsplots, Stuttgart S-Bahn).

- **URL**: https://github.com/makefu/prison-break
- **Mechanism**: Installs as NM dispatcher script, uses plugin system per network
- **Integration**: NixOS `networking.networkmanager.dispatcherScripts`, or manual install to `dispatcher.d/99prison-break`
- **Key design**: Uses `CONNECTION_FILENAME` to match networks, plugin system per portal type
- **Logs**: Detailed journal output showing plugin matching, redirect following, and login success

```
Apr 04 16:39:09 x nm-dispatcher: INFO:cli:CONNECTION_FILENAME set, checking if any plugin matches
Apr 04 16:39:09 x nm-dispatcher: INFO:hotsplots:Unsecured wifi, might be hotsplots!
Apr 04 16:39:11 x nm-dispatcher: INFO:hotsplots:Got Redirected and follow http://192.168.44.1:80/logon?...
Apr 04 16:39:12 x nm-dispatcher: INFO:cli:prisonbreak.plugins.hotsplots successful!
```

### 5.3 lukas0173/Wifi-Captive-Portal-Auto-Authentication

University Wi-Fi auto-login targeting Microsoft SSO-based captive portals.

- **URL**: https://github.com/lukas0173/Wifi-Captive-Portal-Auto-Authentication
- **Language**: Python + Shell
- **Mechanism**: Uses NM dispatcher to handle the `captcha-pending` / portal detection events, then runs Python SSO authentication
- **Design**: Built for university Wi-Fi, uses `uv` package manager, spawns from NM dispatcher context

### 5.4 janisstreib/captive.d

A collection of shell/Python scripts for captive portal logins, organized by SSID.

- **URL**: https://github.com/janisstreib/captive.d
- **Mechanism**: Main dispatcher script checks connectivity with `curl`, looks up SSID-matched login script
- **Key pattern**: SSID-based script dispatch — scripts named by SSID in `captive.d/` subdirectory
- **Auto-reconnect**: Optional VPN connection after successful login

```bash
# Example dispatcher integration
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

### 5.5 binarynoise/CaptivePortalAutoLogin

Cross-platform (Android + Linux) auto-login with NM integration.

- **URL**: https://github.com/binarynoise/CaptivePortalAutoLogin
- **Language**: Kotlin
- **Linux integration**: Listens to NetworkManager via `nmcli`, runs liberator when connectivity changes to `portal`
- **Modes**: One-shot (`--oneshot`) or continuous monitoring (`--service`)
- **Design**: Per-portal handlers with HAR capture for adding new portals

### 5.6 ashish-yadav11/iiserlogin, didek/pjwstk_autologin, FedericoPonzi/sapienza-wifi-login

University-specific auto-login scripts that install as NM dispatcher scripts:

| Project | Target | Language |
|---------|--------|----------|
| `iiserlogin` | IISER captive portal | Shell + Python |
| `pjwstk_autologin` | PJATK university network | Python |
| `sapienza-wifi-login` | Sapienza university Wi-Fi | Python |

Common pattern: NM dispatcher script triggers a login script on matching SSID/connection.

### 5.7 leggiero's DNS-switching Dispatcher

A dispatcher script that changes DNS servers after connecting to public Wi-Fi (to allow captive portals that need their own DNS to work), then switches back to secure DNS after login.

- **URL**: https://gist.github.com/leggiero/251c565bad119870136a3949a34b48fe
- **Triggers on**: `up` and `connectivity-change` with `FULL` state
- **Key insight**: Public Wi-Fi portals may require using the portal's DNS to resolve the login page

### 5.8 aashish-thapa/wlctl

A Rust TUI Wi-Fi manager that integrates with NM's captive portal detection.

- **Mechanism**: `PortalWatcher` polls NM D-Bus connectivity state, auto-opens browser on portal detection
- **Features**: Per-session SSID ignore list, `wlctl portal` one-shot subcommand, configurable auto-open
- **NM integration**: Uses `get_connectivity_state()` and `get_connectivity_check_uri()` async methods

---

## 6. What We Can Learn

### 6.1 Dispatcher Script Format

NM dispatcher scripts follow a simple contract that our standalone target could mirror:

```
Script receives: interface_name + action
Environment provides: connection metadata, IP config, connectivity state
Script returns: exit 0 on success
Constraints: run as root, one at a time, must not run too long
```

Our standalone target could adopt the same convention: a script in a known directory, triggered by an event, receiving context via arguments and environment.

### 6.2 Connectivity Check Mechanism

The HTTP 204 / content-match probe is simple and effective:

1. **GET** a known HTTP URL
2. **Compare** response (status code or body prefix)
3. **Classify**: match = full connectivity, no match = portal, error = limited

Our standalone target needs this same detection capability. The key insight is that the probe URL must be **plain HTTP** — HTTPS probes cannot be intercepted by captive portals.

### 6.3 State Machine

NM's five-state connectivity model (`UNKNOWN → NONE → PORTAL/LIMITED/FULL`) is a good reference for our own portal detection state machine. The transition from `PORTAL` to `FULL` after login is the critical path.

### 6.4 Environment Variables for Context

The rich environment provided to dispatcher scripts (SSID, IP addresses, gateway, DNS servers, connection UUID) gives scripts everything they need to identify the network and select the right login strategy. Our compiled bash scripts should have access to similar context.

### 6.5 SSID-Based Dispatch Pattern

Multiple projects (captive.d, prison-break, iiserlogin) use SSID-based dispatch: identify the network by SSID, then run the matching login script. This is exactly what our recipe compiler's match manifest does.

### 6.6 Background Process Pattern

Because dispatcher scripts are killed if they run too long, auto-login scripts must spawn background processes for any non-trivial work. This is important for our compiled scripts — the dispatcher entry point should trigger the login in a background process.

---

## 7. Integration Path for Our Project

### 7.1 Triggering Our Compiled Scripts via NM Dispatcher

Our compiled bash scripts can be triggered by NM's dispatcher when a portal is detected:

```bash
#!/bin/bash
# /etc/NetworkManager/dispatcher.d/50-captive-portal-recipes

case "$2" in
    connectivity-change)
        if [ "$CONNECTIVITY_STATE" = "PORTAL" ]; then
            # Get network context
            SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
            GATEWAY="$IP4_GATEWAY"

            # Run our compiled auto-login script in background
            /usr/local/lib/captive-portal-recipes/autologin \
                --ssid "$SSID" \
                --interface "$DEVICE_IFACE" \
                --gateway "$GATEWAY" \
                --connection-uuid "$CONNECTION_UUID" &
        fi
        ;;
esac
```

### 7.2 What Our Standalone Target Needs

For systems **without** NetworkManager, our standalone target needs its own portal detection:

1. **HTTP probe**: `curl -s -o /dev/null -w "%{http_code}" http://<probe-url>/` — expect 204 or specific content
2. **State tracking**: Remember connectivity state, detect transitions to portal
3. **Network identification**: Get SSID via `iwgetid -r` or `wpa_cli status`
4. **Match dispatch**: Select the right compiled recipe based on SSID/network fingerprint
5. **Login execution**: Run the matched recipe's curl sequence
6. **Verification**: Re-probe to confirm `FULL` connectivity after login attempt

### 7.3 How NM Complements Our Match Manifest

| NM Provides | Our Recipe Provides |
|-------------|-------------------|
| Portal detection (connectivity check) | Portal login (curl sequence) |
| State transitions (PORTAL → FULL) | Network matching (SSID, gateway, redirect URL) |
| Dispatcher hooks (when to act) | Authentication logic (credentials, tokens, POST data) |
| Network context (SSID, IP, gateway) | Step-by-step login flows (compiled recipes) |
| Route metric management | Session keepalive (acknowledgment URLs) |

### 7.4 Installation Layout

Proposed layout for NM dispatcher integration:

```
/etc/NetworkManager/
├── dispatcher.d/
│   └── 50-captive-portal-recipes          # Entry point (triggers on connectivity-change)
├── conf.d/
│   └── 20-connectivity-custom.conf        # Optional: custom connectivity check URL
```

```
/usr/local/lib/captive-portal-recipes/
├── autologin                              # Main script (selects and runs recipe)
├── recipes/
│   ├── starbucks-wifi.sh                  # Compiled recipe
│   ├── hotel-default.sh                   # Compiled recipe
│   └── ...
└── config
    ├── match-manifest.json                # SSID/pattern → recipe mapping
    └── credentials.enc                    # Encrypted credentials
```

### 7.5 D-Bus Monitoring Alternative

Instead of dispatcher scripts, our tool could monitor NM's D-Bus directly:

```bash
# Watch for connectivity changes via dbus-monitor
dbus-monitor --system "type='signal',interface='org.freedesktop.NetworkManager',member='PropertiesChanged'"
```

Or via `nmcli` in polling mode:

```bash
while true; do
    STATE=$(nmcli -t -f CONNECTIVITY general status | cut -d: -f2)
    if [ "$STATE" = "portal" ]; then
        /usr/local/lib/captive-portal-recipes/autologin
    fi
    sleep 5
done
```

---

## 8. Attribution Notes

- **NetworkManager** is developed by Red Hat and the freedesktop.org community, licensed under **GPL-2.0** (client libraries LGPL-2.1). Source: https://networkmanager.dev/
- **NetworkManager documentation**: https://networkmanager.dev/docs/api/1.52.0/
- **Dispatcher man page**: `NetworkManager-dispatcher(8)` — available at https://man.archlinux.org/man/NetworkManager-dispatcher.8
- **Configuration man page**: `NetworkManager.conf(5)` — https://networkmanager.dev/docs/api/1.52.0/NetworkManager.conf.html
- **D-Bus API**: https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/gdbus-org.freedesktop.NetworkManager.html
- **nmcli man page**: https://networkmanager.dev/docs/api/1.40/nmcli.html
- **GNOME Shell portal helper**: Source code in `js/ui/status/network.js` and `js/portalHelper/` in the gnome-shell repository (GPL-2.0)
- **WebKitGTK sandbox**: https://blogs.gnome.org/mcatanzaro/2020/03/31/sandboxing-webkitgtk-apps/
- **ArchWiki NetworkManager article**: https://wiki.archlinux.org/title/NetworkManager
- **Connectivity check source**: https://github.com/heftig/NetworkManager/blob/master/src/nm-connectivity.c

### Third-party projects referenced:

| Project | License | URL |
|---------|---------|-----|
| captive-portal-sh | - | https://github.com/Seme4eg/captive-portal-sh |
| prison-break | - | https://github.com/makefu/prison-break |
| Wifi-Captive-Portal-Auto-Authentication | - | https://github.com/lukas0173/Wifi-Captive-Portal-Auto-Authentication |
| captive.d | - | https://github.com/janisstreib/captive.d |
| CaptivePortalAutoLogin | - | https://github.com/binarynoise/CaptivePortalAutoLogin |
| capnet-assist | GPL-3.0 | https://github.com/elementary/capnet-assist |
| nmutils | - | https://github.com/sshambar/nmutils |
| networkmanager-helpers | - | https://github.com/lora/networkmanager-helpers |
| iiserlogin | - | https://github.com/ashish-yadav11/iiserlogin |
| pjwstk_autologin | - | https://codeberg.org/didek/pjwstk_autologin |
| sapienza-wifi-login | - | https://github.com/FedericoPonzi/sapienza-wifi-login |

Data sourced from public documentation, source code, manual pages, and project repositories. All information current as of the research date.
