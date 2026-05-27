# Research: HotspotAutoLogin (Python)

> **Source**: https://github.com/denizsafak/HotspotAutoLogin  
> **License**: GPL-3.0  
> **Stars**: 25 | **Forks**: 7 | **Language**: Python (64.6%), Batchfile (35.4%)  
> **Latest Release**: v1.90 (Jan 1, 2025), 16 releases total  
> **Commits**: 152 on main branch  
> **Research Date**: 2026-05-26

---

## 1. Overview

HotspotAutoLogin is a Windows desktop application that automates web-based (captive portal) login for Wi-Fi and Ethernet networks. It continuously monitors the network connection, detects when internet access is lost, and re-authenticates using stored credentials.

**Key characteristics:**
- Single-file Python application (`HotspotAutoLogin.pyw`, ~700 lines) with embedded tkinter GUI, system tray icon (pystray), and profile selection dialog
- Config-driven: all portal definitions live in a `config.json` file with a profiles array
- Generic POST approach: one authentication method (HTTP POST with configurable payload/headers) for all portals
- Pre-built `.exe` distribution via PyInstaller for non-technical users
- Windows-primary: uses `netsh` commands for SSID detection and network adapter management
- 16 releases over the project lifetime, showing active maintenance

**Target platforms:**
- **Primary**: Windows (uses `netsh wlan show interfaces`, `netsh interface show interface`, `ipconfig /release`, `ipconfig /renew`)
- **Secondary**: macOS/Linux mentioned in README but no platform-agnostic code paths exist

---

## 2. Config/Profile System

### config.json Format

The entire system is driven by a single `config.json` containing a `profiles` array:

```json
{
    "profiles": [
        {
            "name": "Example Wi-Fi",
            "ssid": "EXAMPLE_WIFI_5G",
            "url": "https://connect.schoolwifi.com/api/portal/dynamic/authenticate",
            "internet_check_url": "8.8.8.8",
            "payload": {
                "username": "85795013@myschool.com",
                "password": "123455678"
            },
            "headers": {
                "Content-Type": "application/json;charset=UTF-8",
                "Connection": "keep-alive",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ..."
            },
            "check_every_second": 600,
            "dialog_geometry": {
                "width": 1024,
                "height": 500
            }
        },
        {
            "name": "Example ETHERNET",
            "url": "http://10.3.41.15:8002/index.php?zone=dormnet",
            "payload": "&auth_user=85795013%40myschool.com&auth_pass=123455678&redirurl=&accept=Login",
            "internet_check_url": "8.8.8.8",
            "headers": {
                "Content-Type": "application/x-www-form-urlencoded",
                "Connection": "keep-alive",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ..."
            },
            "check_every_second": 600,
            "dialog_geometry": {
                "width": 1024,
                "height": 500
            }
        }
    ]
}
```

### Profile Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Display name in profile selector UI |
| `ssid` | string | no* | Target SSID; omit for Ethernet-only profiles |
| `url` | string | yes | POST target URL for the authentication request |
| `internet_check_url` | string | yes | URL/IP used to verify internet connectivity (default: `8.8.8.8`) |
| `payload` | object or string | yes | POST body: JSON object for `application/json`, URL-encoded string for `application/x-www-form-urlencoded` |
| `headers` | object | yes | HTTP headers including `Content-Type` |
| `check_every_second` | integer | yes | Polling interval in seconds |
| `dialog_geometry` | object | yes | Log window dimensions `{width, height}` |

*`ssid` is optional for Ethernet profiles, which skip SSID matching entirely.

### Profile-to-SSID Mapping

On startup, the GUI displays all profiles in a list. The user selects one profile, and the monitoring loop begins. The system then:
1. Detects the current SSID via `netsh wlan show interfaces`
2. Compares (case-insensitive) against `profile.ssid`
3. If connected to the matching SSID (or Ethernet), checks internet availability
4. If internet is down, fires the POST request

There is no auto-detection of which profile to use based on SSID — the user must manually select. This is a significant UX gap: if a user moves between two networks, they must manually switch profiles.

### Payload Formats (Dual Mode)

The system supports two payload representations:

**JSON object mode** — when `Content-Type` is `application/json`:
```json
"payload": {
    "username": "user@example.com",
    "password": "secret"
}
```
Sent via `requests.post(url, json.dumps(payload), ...)`.

**String mode** — when `Content-Type` is `application/x-www-form-urlencoded`:
```json
"payload": "&auth_user=user%40example.com&auth_pass=secret&redirurl=&accept=Login"
```
Sent as a raw string body. The user must URL-encode the values manually.

### Internet Connectivity Check Per Profile

Each profile specifies its own `internet_check_url`. The check function:
```python
def is_internet_available():
    # Tries https:// then http:// for the given URL/IP
    # Returns True if any request gets HTTP 200
    # Returns False on any exception
```

The default `8.8.8.8` is a plain IP — the function prepends `https://` and `http://` schemes. This is a simplistic check that fails for portals where `8.8.8.8` is reachable before authentication (the README warns about this).

### Multi-Profile Support

Multiple profiles are stored in a flat array. The profile selector UI shows all profiles with:
- Listbox for selection
- Detail panel showing JSON dump of selected profile
- "Add new" button with a form wizard
- "Remove" button with confirmation dialog
- "Run" button to start monitoring with the selected profile

---

## 3. Detection and Monitoring

### Captive Portal Detection

The application does **not** detect captive portals in the traditional sense (HTTP redirect detection, canonical URL probing). Instead, it uses a binary internet-available check:

1. Attempt to GET `internet_check_url` (e.g., `https://8.8.8.8`)
2. If HTTP 200 → internet is available
3. If any error → internet is "down", attempt re-login

This approach has known limitations:
- `8.8.8.8` may respond before portal auth on some networks
- No distinction between "captive portal" and "actual network outage"
- SSL certificate errors are suppressed (`verify=False`)

### Polling Interval Mechanism

The monitoring loop runs in the main thread (after GUI closes):

```
while running and errorcount < 10:
    check SSID match
    if internet available:
        sleep(check_every_second)    # e.g., 600 seconds
    elif request was recently successful:
        sleep(60)                     # give network time to stabilize
    else:
        sleep(5) → send POST         # quick retry
```

Adaptive timing:
- **Normal**: `check_every_second` (default 600s = 10 minutes)
- **Post-success**: 15 seconds (verify internet came back)
- **Post-success, no internet**: 60 seconds (network stabilization)
- **Login attempt**: 5 seconds delay before POST
- **Error**: 3 seconds between retries
- **SSID detection failure**: 60 seconds (location services issue)

### SSID Detection (Windows)

Uses `netsh wlan show interfaces` via subprocess:
```python
output = subprocess.check_output(["netsh", "wlan", "show", "interfaces"], ...)
match = re.search(r"^\s*SSID\s*:\s*(.+)$", output, re.MULTILINE)
```

**Windows Location Services requirement**: Recent Windows updates restrict third-party apps from accessing Wi-Fi names unless location services are enabled. The README links to Microsoft's [Changes to API behavior for Wi-Fi access and location](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wi-fi-access-location-changes).

### Ethernet Detection

Checks `netsh interface show interface` for connected Ethernet adapters. Ethernet profiles skip SSID matching. If both Wi-Fi and Ethernet are connected, the script disconnects Wi-Fi via `netsh wlan disconnect`.

### Re-login on Disconnect

If the POST succeeds but internet remains unavailable after 3 retries (60s each), the script re-enters the login cycle. For Ethernet, it attempts `ipconfig /release` + `ipconfig /renew` to reset the adapter. The error counter caps at 10 consecutive failures before the loop exits.

---

## 4. Authentication Approach

### Generic POST with Configurable Payload/Headers

The entire authentication is a single HTTP POST:

```python
def send_request():
    session = requests.Session()
    response = session.post(url, json.dumps(payload), headers=headers,
                            allow_redirects=True, verify=False, timeout=10)
    response.raise_for_status()
    return response
```

Key observations:
- **Always POST**: No GET-based flows, no form extraction, no token handling
- **SSL verification disabled**: `verify=False` + `InsecureRequestWarning` suppressed
- **JSON-serialized payload**: `json.dumps(payload)` is used regardless of Content-Type — this means for form-encoded payloads stored as strings, the string is sent as-is (which works because a raw string is already URL-encoded)
- **Follows redirects**: `allow_redirects=True`
- **10-second timeout**: Fixed, not configurable per profile
- **No response validation**: Success is determined only by `response.ok` (2xx status). The actual response body is never checked.

### Form-Encoded vs JSON Content Types

The two modes are distinguished solely by the `Content-Type` header:

| Content-Type | Payload Format | How It's Sent |
|-------------|---------------|---------------|
| `application/json;charset=UTF-8` | JSON object `{"key": "val"}` | `json.dumps(payload)` → valid JSON body |
| `application/x-www-form-urlencoded` | URL-encoded string `"&key=val&..."` | `json.dumps(payload)` → string wrapped in quotes (sends the string directly) |

**Important caveat**: For form-encoded mode, the payload is a raw string, not a dict. The `json.dumps()` call on a string wraps it in quotes, but since the server reads the raw body after URL-decoding, this works in practice because the extra quotes are ignored by most form parsers.

### Browser DevTools Capture Workflow

The README provides a clear workflow for users to configure new portals:

1. Open the captive portal login page in browser
2. Open Developer Tools (F12 or Ctrl+Shift+I)
3. Go to **Network** tab
4. **Trigger the POST request** (try logging in with an incorrect password)
5. Find the POST request in the network log
6. Copy the **Payload** tab values → paste into `"payload"` field
7. Copy the **Request URL** from Headers tab → paste into `"url"` field
8. Set `"internet_check_url"` (default `8.8.8.8`, change if reachable before login)
9. Set `"ssid"` to the network name

This is a practical approach for technical users but has gaps:
- No guidance on copying headers
- No guidance on handling CSRF tokens or cookies
- The "try with wrong password" tip is clever — it reveals the POST without actually authenticating

### Limitations of the Generic POST Approach

The README acknowledges: *"The script relies on the assumption that the web portal uses basic authentication. If the portal uses a more complex login mechanism, additional adjustments may be necessary."*

Specific limitations observed from source code and issues:

1. **No form extraction**: Cannot fetch a login page, parse hidden fields (CSRF tokens, session IDs), and include them in the POST
2. **No cookie management**: No cookie jar — session cookies from a GET request can't be forwarded to the POST
3. **No multi-step flows**: Hotel/retail portals requiring 3-5 sequential page submissions are unsupported
4. **No CHAP/MD5**: Encrypted authentication (MikroTik, etc.) is not supported
5. **No JavaScript handling**: Portals that use JS-generated tokens or redirects can't be handled
6. **No dynamic variables**: Cannot inject own IP, MAC, or other runtime values into URLs (Issue #6 requests this)
7. **No response validation**: Can't distinguish "login accepted" from "login rejected" — only HTTP status code is checked
8. **No GET-based auth**: Click-through portals that require following a redirect URL are not supported

---

## 5. UX and Distribution

### System Tray GUI

After profile selection, the main window closes and the application minimizes to a system tray icon:
- Right-click menu: "Show Log" and "Exit"
- "Show Log" opens a tkinter window with timestamped log messages
- Log messages are color-coded (green for success, red for errors)
- Log window shows a "Successful Logins" counter
- Log entries also written to `log.txt` file

### Pre-Built .exe Distribution

- Released via GitHub Releases (16 versions)
- Built with PyInstaller
- Single `HotspotAutoLogin.exe` file — no Python installation required
- The README prominently links to the latest release download

### Profile Management UI

The "Add new" profile wizard provides:
- Name field (auto-generates unique names like "New profile 2")
- SSID dropdown populated by scanning available Wi-Fi networks
- Ethernet checkbox (disables SSID field)
- Request URL field
- Internet check URL field (defaults to `8.8.8.8`)
- Payload text area (accepts JSON or raw string)
- Headers text area (JSON, pre-filled with default headers)
- Check interval field (defaults to 600)
- Dialog geometry (width/height for log window)
- Validation: checks for empty fields, valid URL, valid JSON headers, duplicate profile names

### Profile Selection Flow

1. On launch, a tkinter window shows the profile list
2. User selects a profile and clicks "Run"
3. The selection window closes
4. System tray icon appears
5. Monitoring loop starts for the selected profile
6. User cannot switch profiles without restarting the application

---

## 6. What We Can Learn

### 6.1 Config JSON Profile Format (Comparison to Our Recipe JSON)

**Their format:**
```json
{
    "name": "Example Wi-Fi",
    "ssid": "EXAMPLE_WIFI_5G",
    "url": "https://connect.schoolwifi.com/api/portal/dynamic/authenticate",
    "payload": {"username": "...", "password": "..."},
    "headers": {"Content-Type": "application/json;charset=UTF-8"},
    "internet_check_url": "8.8.8.8",
    "check_every_second": 600
}
```

**Our format:**
```json
{
    "id": "cisco-meraki",
    "name": "Cisco Meraki Click-Through",
    "travelmate_domain": "eu.network-auth.com",
    "auth_type": "click-through-grant",
    "credentials": "none",
    "match": {
        "ssids": ["BACK-FACTORY Besucher"],
        "domains": ["*.network-auth.com"],
        "paths": [],
        "body_contains": [],
        "priority": 80
    },
    "params": {
        "grant_url_source": "redirect_url",
        "grant_url_extract": "query_param",
        "grant_url_param": "base_grant_url"
    }
}
```

**Key differences:**

| Aspect | HotspotAutoLogin | Our Recipes |
|--------|-----------------|-------------|
| Auth types | Single generic POST | 8 typed auth strategies |
| SSID matching | Exact, single SSID per profile | Wildcard patterns, multiple SSIDs |
| Domain matching | None | Wildcard domain patterns |
| Payload | User copies raw payload | Structured params per auth_type |
| Headers | User specifies all headers | System manages most headers |
| Success detection | HTTP status only | Multiple strategies (empty_body, body_contains, json_field) |
| Multi-step | Not supported | multi-step-form, json-api steps |
| CSRF/Cookies | Not supported | csrf-form-submit, cookie-chain |
| Variables | None | `{var}` extraction between steps |
| User config | Users store credentials in config | Recipes are credential-free templates |

**What we can adopt:**
- Their `internet_check_url` concept — per-profile connectivity check endpoint is a good idea
- Their `dialog_geometry` — storing UI preferences in config is user-friendly
- Their flat profile array is simpler for non-technical users than our file-per-recipe approach

### 6.2 Browser DevTools Capture Workflow

Their workflow is well-documented and user-friendly:
1. Open DevTools → Network tab
2. Try login with wrong password (captures POST without authenticating)
3. Copy payload and URL from the captured request

**What we can learn:**
- The "wrong password" trick is a clever capture technique our `tools/capture-portal.sh` should document
- Visual screenshots in the README showing exactly where to click are very effective
- The animated GIF demo (howto.gif) in their examples is excellent for onboarding

### 6.3 Multi-Profile Management

Their approach: single `config.json` with a `profiles` array, GUI for add/remove.

**Trade-offs:**
- Pro: Simple for end users — one file to manage
- Pro: GUI eliminates JSON editing errors
- Con: Can't share profiles between users (credentials are embedded)
- Con: No community-contributable profile library

**Our approach (file-per-recipe) is better for:**
- Community contribution (PR a single file)
- Credential separation (templates, not instances)
- Type-specific validation
- Compilation to different targets

**Their approach is better for:**
- Non-technical users who want a working solution immediately
- Desktop users who don't care about sharing configurations
- Quick iteration on a single machine

### 6.4 GUI Approach for Non-Technical Users

The profile management UI is the strongest feature:
- "Add new" wizard with field-level validation
- Wi-Fi scanning for SSID dropdown
- Auto-detection of current SSID
- Pre-filled defaults for headers, check interval, etc.

**What we can consider:**
- A similar "Add new recipe" wizard in a web UI or CLI tool
- Pre-filled defaults based on portal type detection
- Auto-populating SSID from current connection

### 6.5 Distribution Model

**Their approach**: Single `.exe` via GitHub Releases (PyInstaller)
**Our approach**: Source-based with a compiler, generating target-specific scripts

**Observations:**
- Their `.exe` approach reaches non-technical users immediately
- Our compiler approach is more flexible (multiple targets) but requires setup
- A web-based recipe compiler (upload JSON → download .login) could bridge the gap
- The `.exe` bundling approach works because they have a single runtime (Python); our multi-target approach needs a different distribution strategy

---

## 7. What We Can Skip

### Windows-Specific Code
- `netsh wlan show interfaces` — Windows-only SSID detection
- `netsh interface show interface` — Windows-only Ethernet detection
- `ipconfig /release` / `ipconfig /renew` — Windows-only network reset
- `subprocess.CREATE_NO_WINDOW` and `STARTUPINFO` flags
- `os.startfile()` for opening config.json

### Python GUI Implementation Details
- tkinter profile selection dialog (~200 lines of layout code)
- tkinter "Add new" wizard (~200 lines)
- tkinter log viewer window
- pystray system tray icon setup
- PIL icon loading

### System Tray Code
- `pystray` menu construction
- Log dialog show/hide/withdraw lifecycle
- Window geometry persistence

### What is worth noting but not adopting:
- SSL verification disabled globally (`verify=False`, warning suppression)
- DNS resolver override (`dns.resolver.override_system_resolver`)
- Single-threaded monitoring loop (blocks main thread after GUI closes)
- `json.dumps(payload)` for all payload types (string or object)

---

## 8. Community Feedback (Issues)

### Issue #6: Allow passing own IP/MAC in URL (rklec, Feb 2026)

**Request**: Support placeholders like `{ip}`, `{mac}`, `{uamip}` in URLs for Hotsplots/DB WifiOnICE portals that require device and router identifiers in query parameters.

**Example URL**: `https://www.hotsplots.de/auth/login.php?res=already&uamip=192.168.44.1&mac=EC-**-**-46&ip=192.168.45.19&nasid=colibri-00c0***99`

**Relevance to us**: Our `hotsplots.json` recipe handles this portal type via `form-submit` with `form_page_url: "${trm_captiveurl}"` — the URL is captured from the redirect, which already contains the IP/MAC parameters. This is a case where our redirect-based approach is more robust than their static-URL approach.

### Issue #5: Config help for Turkish government Wi-Fi (YasefDogan, Mar 2025)

**Problem**: User configured `Content-Type: application/json` for a form-encoded portal (`j_spring_security_check`). The payload was a JSON object but should have been a URL-encoded string. Also had DNS resolution failures because the portal domain wasn't resolvable before authentication.

**Root cause**: The generic POST approach doesn't guide users to match the Content-Type to the portal's expected format. Our typed `auth_type` system avoids this — `form-submit` automatically uses the correct encoding.

**Log pattern**: "Request was successful" but "still no internet connection" — the POST returned 2xx but didn't actually authenticate because the Content-Type/payload format was wrong. This is exactly the failure mode our `success_check` mechanisms are designed to detect.

**Relevance to us**: Validates our design of typed auth strategies with built-in success validation, versus their "fire and hope" POST approach.

---

## 9. Summary of Key Takeaways

### Patterns Worth Studying
1. **Config-driven profiles**: Simple JSON format that non-technical users can understand
2. **Browser DevTools capture workflow**: Well-documented with screenshots and animated GIF
3. **"Wrong password" capture trick**: Clean way to capture the POST without authenticating
4. **Profile management GUI**: Add/remove/edit wizard with validation
5. **Pre-built binary distribution**: Reaches users who won't install Python
6. **Per-profile connectivity check URL**: Different portals may need different check endpoints

### Anti-Patterns to Avoid
1. **Single auth method**: Only generic POST — no CSRF, no form extraction, no multi-step
2. **No response validation**: Only checks HTTP status, not response content
3. **No auto-profile selection**: User must manually pick the right profile
4. **Credentials in config file**: Plain text, not shareable
5. **SSL verification disabled**: Security risk, suppresses certificate warnings
6. **Platform-lockin**: Windows-only SSID detection and network management
7. **No cookie/session management**: Cannot handle portals requiring session cookies

### Direct Comparisons

**HotspotAutoLogin handles** (that we should note):
- School/enterprise portals with simple JSON POST auth
- Ethernet-connected captive portals (no SSID needed)
- Automatic network adapter reset on persistent failure

**Our recipes handle** (that HotspotAutoLogin cannot):
- Click-through portals (Meraki, Arista, Fortinet)
- CSRF-protected forms (wifionice/DB, many enterprise portals)
- CHAP-MD5 authentication (MikroTik)
- Multi-step hotel/retail flows
- Cookie-chain PHP session portals
- JavaScript redirect extraction
- JSON API with variable extraction between steps

---

## 10. Attribution Notes

- Data sourced from the public GitHub repository: https://github.com/denizsafak/HotspotAutoLogin
- Code patterns and config.json examples are from the repository's `main/` directory
- Issue content is from public GitHub issues #5 and #6
- We study architectural patterns and design decisions; no code is copied
- HotspotAutoLogin is licensed under GPL-3.0, compatible with our project license
