# Android CaptivePortalLogin: Detection and Sign-In System

> Research document for the captive-portal-recipes project.
> Sources: AOSP source code, Android developer documentation, public analysis.

---

## 1. Overview

**CaptivePortalLogin** is the system application in Android responsible for presenting captive portal sign-in pages to users. It ships as part of the Android Open Source Project (AOSP) and is present on virtually every Android device sold worldwide, making it the most widely deployed captive portal handler in existence.

- **Source:** [`platform/packages/modules/CaptivePortalLogin`](https://android.googlesource.com/platform/packages/modules/CaptivePortalLogin/) on Google Git
- **License:** Apache 2.0
- **Package:** `com.android.captiveportallogin`
- **Main class:** `CaptivePortalLoginActivity` (an `Activity`)
- **Part of Android since:** Android 4.2 (API 17), with the `CaptivePortalTracker` introduced in Android 4.0 (API 14)
- **Moved to Project Mainline module:** Android 10 (Q), allowing updates via Google Play System Updates

The app is deliberately minimal. It does one thing: display a WebView (or Custom Tab) so the user can interact with the captive portal. It does not auto-login. It does not store credentials. It does not script portal interactions. Its entire job is to provide a controlled browser surface where the user can manually sign in, then detect when the portal has been dismissed.

---

## 2. Detection Flow

Android's captive portal detection is a multi-layered system involving several components working together. The core detection logic lives in `NetworkMonitor` (a state machine within the connectivity stack), not in CaptivePortalLogin itself.

### 2.1 The HTTP 204 Probe

The primary detection mechanism is the **HTTP 204 probe**. Android makes a GET request to a known URL that is expected to return HTTP 204 (No Content). The logic is simple:

- **204 response** = internet is reachable, no captive portal.
- **3xx redirect** = captive portal detected (the redirect points to the portal page).
- **200 response with body** = captive portal detected (the portal serves its own page directly).
- **200 response with `Content-Length: 0`** = treated as 204 (broken transparent proxy, not a portal).
- **Timeout or connection failure** = inconclusive.

The default probe URLs are:

| Probe Type | URL |
|---|---|
| HTTP | `http://connectivitycheck.gstatic.com/generate_204` |
| HTTPS | `https://www.google.com/generate_204` |
| HTTP Fallback | `http://www.google.com/gen_204` |
| Additional Fallback | `http://play.googleapis.com/generate_204` |

The probe endpoint (`/generate_204`) is specifically designed to return a bare 204 response with no body. Google operates these endpoints specifically for Android connectivity checking.

### 2.2 Probe Execution Sequence

The `NetworkMonitor.isCaptivePortal()` method orchestrates detection:

1. **DNS probe** -- Resolve the probe hostname. If DNS fails, the network is broken.
2. **If PAC (Proxy Auto-Config) is configured** -- Fetch the PAC script instead of the HTTP probe. A 200 response to the PAC URL is interpreted as success.
3. **If HTTPS probing is enabled** (default since Android 7):
   - Send HTTPS and HTTP probes **in parallel** (`sendParallelHttpProbes`).
   - Use a `CountDownLatch(2)` to wait for both.
   - Short-circuit logic: if HTTPS succeeds (204), network is valid immediately. If HTTP detects a portal (redirect), report portal immediately.
   - If HTTPS fails (SSL error, timeout) and HTTP is inconclusive, fall through to fallback probes.
4. **If HTTPS probing is disabled** (or disabled after user dismissed portal):
   - Send only the HTTP probe (`sendDnsAndHttpProbes`).
5. **Fallback probes** -- If primary probes are inconclusive, try fallback URLs one at a time (rotated across attempts). If a `CaptivePortalProbeSpec` is configured, use regex-based matching instead of the simple 204 check.
6. **Result classification:**
   - `SUCCESS_CODE` (204) = network validated
   - `PORTAL_CODE` (3xx redirect, or 200 with body) = captive portal detected
   - `FAILED` = inconclusive (all probes failed or timed out)

### 2.3 CaptivePortalProbeSpec: Configurable Detection

Android 9+ supports configurable probe specifications via `CaptivePortalProbeSpec`. The format is:

```
URL@@/@@statusCodeRegex@@/@@locationHeaderRegex
```

Multiple specs are separated by `@@,@@`. This allows OEMs and carriers to customize detection without modifying code. The spec uses regex matching on the HTTP status code and Location header to determine portal vs. non-portal, rather than the hardcoded 204 check.

The `isDismissed()` method in CaptivePortalLoginActivity shows the dual logic:

```java
private static boolean isDismissed(
    int httpResponseCode, String locationHeader, CaptivePortalProbeSpec probeSpec) {
    return (probeSpec != null)
        ? probeSpec.getResult(httpResponseCode, locationHeader).isSuccessful()
        : (httpResponseCode == 204);
}
```

### 2.4 DNS-Based Detection

`NetworkMonitor` also performs DNS resolution as part of `sendDnsAndHttpProbes`. The DNS probe resolves the probe hostname and logs the resolved addresses. While DNS failure alone does not indicate a captive portal (it indicates a broken network), DNS hijacking -- where all queries resolve to the portal's IP -- is detected indirectly because the HTTP probe to that IP will not return 204.

### 2.5 NetworkMonitor State Machine

`NetworkMonitor` is a `StateMachine` (Android's `Handler`-based state machine) with these key states:

| State | Meaning |
|---|---|
| `DefaultState` | Base state, handles cleanup messages |
| `ValidatedState` | Network passed all probes, internet available |
| `MaybeNotifyState` | Base for states that may show notifications |
| `CaptivePortalState` | Portal detected, notification shown to user |
| `ProbingState` | Actively probing the network |
| `EvaluatingPrivateDnsState` | Checking private DNS |

When a captive portal is detected, the state machine transitions to `CaptivePortalState`, which:
1. Sends `EVENT_NETWORK_TESTED` with `NETWORK_TEST_RESULT_INVALID`.
2. Creates a `PendingIntent` that launches `CaptivePortalLoginActivity`.
3. Posts a "Sign in to network" notification via `EVENT_PROVISIONING_NOTIFICATION`.
4. Schedules periodic rechecks (`CMD_CAPTIVE_PORTAL_RECHECK`).

### 2.6 NetworkCapabilities and NET_CAPABILITY_CAPTIVE_PORTAL

The connectivity framework exposes portal state through `NetworkCapabilities`:

```java
public static final int NET_CAPABILITY_CAPTIVE_PORTAL = 17;
```

This capability is **mutable** and **connectivity-managed** -- it changes as detection results come in. Apps can monitor it via `NetworkCallback.onCapabilitiesChanged()`:

```java
NetworkCallback callback = new NetworkCallback() {
    @Override
    public void onCapabilitiesChanged(Network network, NetworkCapabilities nc) {
        if (nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)) {
            // This network has a captive portal
        }
    }
};
```

Related capabilities:
- `NET_CAPABILITY_INTERNET` -- Network is configured to reach the internet (but may not actually have connectivity).
- `NET_CAPABILITY_VALIDATED` -- Network was actually validated (probes succeeded).
- `NET_CAPABILITY_CAPTIVE_PORTAL` -- Network has a captive portal.

A captive portal network has `NET_CAPABILITY_INTERNET` but lacks `NET_CAPABILITY_VALIDATED` and has `NET_CAPABILITY_CAPTIVE_PORTAL`. It is **not** selected as the default network when another validated network (e.g., mobile data) is available.

### 2.7 CaptivePortal Binder Object

When launching the sign-in activity, the system passes a `CaptivePortal` binder object as an intent extra. This object has three key methods:

| Method | Meaning |
|---|---|
| `reportCaptivePortalDismissed()` | User successfully signed in; re-validate the network. |
| `ignoreNetwork()` | User declined to sign in; don't use this network, prefer others. |
| `useNetwork()` | User wants to use this network as-is despite the portal. |

A fourth method, `reevaluateNetwork()` (system API), requests immediate re-probing without user action.

---

## 3. User Experience Flow

The complete flow from WiFi connection to portal sign-in:

### 3.1 Step-by-Step Sequence

```
WiFi associates + DHCP completes
        |
        v
NetworkMonitor starts validation
        |
        v
DNS probe resolves connectivitycheck.gstatic.com
        |
        v
HTTP/HTTPS probes sent in parallel
        |
   +----+----+
   |         |
   v         v
  204      3xx/200
   |         |
   v         v
Validated  CaptivePortalState
   |         |
   v         v
Network    "Sign in to network"
becomes    notification posted
default      |
             v (user taps notification)
        ACTION_CAPTIVE_PORTAL_SIGN_IN intent
             |
             v
        CaptivePortalLoginActivity launches
             |
             v
        WebView loads portal URL
        (or Custom Tab on Android 12+)
             |
             v (user interacts with portal)
        onPageStarted/onPageFinished callbacks
             |
             v
        testForCaptivePortal() in background:
        HTTP GET to /generate_204
             |
        +----+----+
        |         |
        v         v
       204      not-204
        |         |
        v         v
   reportCaptive-  keep waiting,
   PortalDismissed user keeps interacting
        |
        v
   NetworkMonitor re-validates
        |
        v
   Network becomes validated
```

### 3.2 The Sign-In Notification

When a captive portal is detected, the system posts a notification with:
- **Title:** "Sign in to [network name]" (for WiFi) or "Sign in to network" (for cellular)
- **Action:** Tapping the notification sends `CMD_LAUNCH_CAPTIVE_PORTAL_APP` to NetworkMonitor, which fires the `ACTION_CAPTIVE_PORTAL_SIGN_IN` intent targeting `CaptivePortalLoginActivity`.

The notification can be configured via `Settings.Global.CAPTIVE_PORTAL_MODE`:
- `0` (IGNORE): Don't detect captive portals.
- `1` (PROMPT): Show notification (default).
- `2` (AVOID): Immediately disconnect from networks with captive portals.

### 3.3 WebView-Based Display

`CaptivePortalLoginActivity` renders the portal in an embedded `WebView` (or a Custom Tab on Android 12+). Key implementation details:

**Process binding:** The activity binds its process to the specific network that has the captive portal using `ConnectivityManager.bindProcessToNetwork(mNetwork)`. This ensures WebView traffic goes through the captive network, not through mobile data or another validated WiFi network.

**WebView initialization:**
```java
webSettings.setJavaScriptEnabled(true);
webSettings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
webSettings.setUseWideViewPort(true);
webSettings.setLoadWithOverviewMode(true);
webSettings.setSupportZoom(true);
webSettings.setBuiltInZoomControls(true);
```

**First-page proxy trick:** The WebView initially loads the `/generate_204` URL (which the portal intercepts, redirecting to the actual login page). After the first page finishes loading, the activity calls `setWebViewProxy()` to apply network-specific proxy settings, then loads the real URL. This two-step process ensures the WebView picks up proxy configuration from the captive network.

**URL handling:** The `MyWebViewClient` overrides `shouldOverrideUrlLoading` to intercept non-HTTP URLs:
- `tel:` links launch the dialer.
- `sms:` links launch the SMS app.
- `http:` and `https:` URLs load within the WebView.
- Other schemes launch external apps.

### 3.4 Custom Tabs (Android 12+)

Modern versions of CaptivePortalLogin support using Chrome Custom Tabs instead of the embedded WebView. This provides a more familiar browser experience:

- The feature is gated by `CAPTIVE_PORTAL_CUSTOM_TABS` flag.
- On Android 12+ (API 31+), if a Custom Tabs provider is available, it is used instead of WebView.
- The VPN bypass logic ensures the Custom Tabs provider can access the captive network even when a VPN is active.

### 3.5 Dismissal Detection

After the user interacts with the portal in the WebView, the activity continuously re-checks for portal dismissal. The `testForCaptivePortal()` method:

1. Runs on a background thread.
2. Waits 1 second (to give the portal time to open).
3. Makes an HTTP GET to `/generate_204` with `setInstanceFollowRedirects(false)`.
4. If the response is **204**, calls `done(Result.DISMISSED)` which invokes `mCaptivePortal.reportCaptivePortalDismissed()`.
5. The `MyWebViewClient` calls `testForCaptivePortal()` on both `onPageStarted` and `onPageFinished` callbacks.

This means the portal is detected as dismissed automatically as the user navigates through it, without requiring the user to explicitly confirm.

### 3.6 Network Loss Handling

The activity registers a `NetworkCallback` that monitors the captive network. If the network is lost (`onLost`), the activity finishes with `Result.UNWANTED` (calls `ignoreNetwork()`). This prevents the sign-in UI from persisting after the WiFi disconnects.

---

## 4. Evolution Across Android Versions

### 4.1 Android 4.0--4.3 (API 14--18): CaptivePortalTracker

The original implementation used `CaptivePortalTracker`, a `StateMachine` that:

- Used a single server: `clients3.google.com`.
- Made one HTTP GET to `http://<server>/generate_204`.
- If the response was not 204, considered it a captive portal.
- Showed a notification with `PendingIntent` to open the portal URL in a browser.
- Used a delayed check: waited 10 seconds after network connection before probing.

Key limitations:
- No HTTPS probing.
- No parallel probes.
- No configurable probe URLs.
- Detection was a simple binary: 204 or not-204.

### 4.2 Android 4.4--5.0 (API 19--21): CaptivePortalLoginActivity

The `CaptivePortalLoginActivity` was introduced as a dedicated system app, replacing the previous approach of opening the browser. Key changes:

- Dedicated WebView-based activity instead of browser intent.
- `NET_CAPABILITY_CAPTIVE_PORTAL` (value 17) added in API 21.
- `CaptivePortal` binder object introduced for communicating sign-in results back to the system.
- Server changed from `clients3.google.com` to `connectivitycheck.gstatic.com`.
- The `CaptivePortalTracker` still drove detection; `NetworkMonitor` was introduced alongside it.

### 4.3 Android 5.1--6.0 (API 22--23): NetworkMonitor Takes Over

`NetworkMonitor` gradually replaced `CaptivePortalTracker` as the primary detection engine:

- Introduced configurable probe URLs via `Settings.Global`:
  - `captive_portal_server`
  - `captive_portal_http_url`
  - `captive_portal_https_url`
  - `captive_portal_fallback_url`
- Detection moved from `CaptivePortalTracker.isCaptivePortal()` to `NetworkMonitor.isCaptivePortal()`.
- Added DNS probing alongside HTTP probing (`sendDnsAndHttpProbes`).

### 4.4 Android 7.0 (API 24): HTTPS Dual Probe

This was the most significant change to captive portal detection. Android 7 introduced **parallel HTTPS + HTTP probing**:

- `sendParallelHttpProbes()` sends both probes simultaneously using two threads.
- HTTPS probe: `https://www.google.com/generate_204`
- HTTP probe: `http://connectivitycheck.gstatic.com/generate_204`
- Short-circuit logic: if HTTPS returns 204, network is valid immediately. If HTTP finds a portal, report it immediately.
- If HTTPS fails (SSL error) and HTTP is inconclusive, result is `FAILED`.

**Why this matters:** The HTTPS probe serves as a "positive signal." If HTTPS works, the network is definitely not captive (portals cannot serve valid SSL certificates for google.com). This prevents false positives from transparent HTTP proxies that modify or block the HTTP probe but pass HTTPS through cleanly.

**The pathological case** (documented in source comments):
1. HTTP probe sees a captive portal. HTTPS probe fails or times out.
2. User opens the app and logs into the captive portal.
3. HTTP starts returning 204, but HTTPS still fails (network might block HTTPS for other reasons).
4. Result: network never validates, and the user can no longer reach "Use this network as is" because the app is gone.

To mitigate this, once the user has acted on a portal notification, HTTPS probing is disabled (`mUseHttps = false`) for that network.

### 4.5 Android 7.1--8.0 (API 25--26): Fallback URLs and Probe Specs

- Introduced multiple fallback URLs (`captive_portal_other_fallback_urls`) that rotate across rechecks.
- `CaptivePortalProbeSpec` introduced for configurable regex-based detection.
- User-Agent string set to mimic Chrome (`Mozilla/5.0 ... Chrome/60.0.3112.32 Safari/537.36`).
- `OneAddressPerFamilyNetwork` wrapper limits DNS resolution to one IPv4 and one IPv6 address, preventing multi-address hosts from causing long timeouts.

### 4.6 Android 9 (API 28): Modularization

- `CaptivePortalLogin` moved from `frameworks/base/packages/CaptivePortalLogin` to `platform/packages/modules/CaptivePortalLogin` as a standalone module.
- `NetworkMonitor` moved to the NetworkStack module (`packages/NetworkStack`).
- This enabled updates via Google Play System Updates (Project Mainline / APEX modules).
- URL configuration became resource-driven (`config_captive_portal_http_url`, `config_captive_portal_https_url`) in addition to settings.

### 4.7 Android 10 (API 29): Project Mainline

- CaptivePortalLogin fully integrated as a Mainline module.
- `CaptivePortalData` class introduced for RFC 7710bis metadata (session info, venue URLs, byte limits, expiry).
- `CaptivePortal.getCaptivePortalServerUrl()` deprecated in favor of module-managed URLs.

### 4.8 Android 11 (API 30): Captive Portal API (RFC 7710bis)

Android 11 added support for the **Captive Portal API** per RFC 7710bis:

- **DHCP Option 114:** During DHCP handshake, the access point can advertise a captive portal API URL.
- The device fetches the API URL immediately after connecting.
- The API response includes: `captive` (boolean), `user-portal-url`, `venue-info-url`, `can-extend-session`, `seconds-remaining`, `bytes-remaining`.
- If the API is not available or doesn't advertise a portal, the system falls back to HTTP/HTTPS probes.

This was the first time Android could receive a **positive signal** from the network itself that a portal exists, rather than relying solely on negative inference (the 204 not being returned).

### 4.9 Android 12--13 (API 31--33): Custom Tabs

- CaptivePortalLogin gained support for Chrome Custom Tabs as an alternative to WebView.
- Custom Tabs provide a more native browser experience (shared cookies, autofill, password managers).
- VPN bypass logic ensures Custom Tabs can reach the captive network.

### 4.10 Android 14+ (API 34+): Continued Refinements

- Captive portal detection remains fundamentally the same (HTTP 204 probe + HTTPS parallel probe).
- Settings for captive portal mode are exposed in the Settings UI: "Detect captive portals" / "Don't detect captive portals."
- The probe URLs are configurable via `settings put global captive_portal_http_url` and `settings put global captive_portal_https_url` (with ADB or device owner).

### Version Summary Table

| Android Version | API | Key Change |
|---|---|---|
| 4.0--4.3 | 14--18 | `CaptivePortalTracker`, single HTTP probe to `clients3.google.com` |
| 4.4--5.0 | 19--21 | `CaptivePortalLoginActivity` WebView, `NET_CAPABILITY_CAPTIVE_PORTAL` |
| 5.1--6.0 | 22--23 | `NetworkMonitor`, configurable URLs, DNS probing |
| 7.0 | 24 | Parallel HTTPS + HTTP dual probe |
| 7.1--8.0 | 25--26 | Fallback URLs, `CaptivePortalProbeSpec`, User-Agent spoofing |
| 9 | 28 | Modularization (NetworkStack module) |
| 10 | 29 | Project Mainline, `CaptivePortalData` (RFC 7710bis) |
| 11 | 30 | DHCP Option 114, Captive Portal API |
| 12--13 | 31--33 | Custom Tabs support |
| 14+ | 34+ | Continued refinements, same core mechanism |

---

## 5. No Auto-Login Capability

### 5.1 Why Android Doesn't Auto-Login

Android's CaptivePortalLogin is intentionally a **manual sign-in tool**. It does not and will not auto-login. The reasons are:

1. **Security:** Automatically submitting forms with credentials to an arbitrary, untrusted web page is fundamentally dangerous. The captive portal could be malicious (an "evil twin" access point) designed to harvest credentials. Making the user visually verify the portal page provides a minimal trust anchor.

2. **Diversity of portals:** Every captive portal has a unique flow. Some require clicking "Accept." Some require entering a room number. Some require email, social media login, SMS verification, or payment. There is no universal "auto-login" protocol. Even the Captive Portal API (RFC 7710bis) only tells the device *that* there's a portal, not *how* to authenticate.

3. **Legal liability:** Many captive portals require accepting terms of service. Automatically clicking "I agree" on behalf of the user has legal implications. The user must consent.

4. **Privacy:** Auto-login would require storing credentials (hotel room numbers, email addresses, portal passwords) on the device, creating an attractive target for attackers.

5. **User expectation:** Users expect to see and interact with captive portals. Silently authenticating in the background would confuse users and break the trust model of "I connect to WiFi, I see what I'm agreeing to."

### 5.2 The WebView Isolation Model

CaptivePortalLogin runs as a **system process** with a specific security model:

- The WebView is bound to the captive network via `bindProcessToNetwork()`. This means all WebView traffic goes through the untrusted WiFi, not through mobile data or VPN.
- The activity runs in its own process (the `com.android.captiveportallogin` process), isolated from other apps.
- JavaScript is enabled (many portals require it), but the WebView does not share cookies, cache, or storage with the user's browser.
- The activity finishes as soon as the portal is dismissed, clearing its state.

This isolation is critical: the potentially malicious captive portal page runs in a sandboxed environment with no access to the user's browsing data, cookies from other sites, or credentials from other apps.

### 5.3 Comparison: CPAL (CaptivePortalAutoLogin) Does Auto-Login

[CaptivePortalAutoLogin (CPAL)](https://github.com/binarynoise/CaptivePortalAutoLogin) is an open-source Android app that does what CaptivePortalLogin deliberately does not: it automatically logs into known captive portals.

CPAL's approach:
- Contains 46+ handler classes, each knowing how to interact with a specific portal (Meraki, Fortinet, Deutsche Bahn, etc.).
- Detects captive portals the same way Android does (via `ConnectivityManager` callbacks monitoring `NET_CAPABILITY_CAPTIVE_PORTAL`).
- When a portal is detected, matches it against its handler library and executes the appropriate authentication flow automatically.
- Handles form extraction, CSRF tokens, JSON API calls, cookie chains, and even CHAP-MD5 authentication.

CPAL works because it has **per-portal handlers**: code that knows the exact HTTP requests needed for each specific portal. This is the same approach our recipe system uses, but expressed as Kotlin code rather than JSON.

**Key difference:** CPAL trusts the portal because it knows *which* portal it is (by domain matching). If the domain matches a known handler, CPAL runs the automation. If the domain is unknown, it falls back to the system's CaptivePortalLogin. This is a reasonable trade-off: a portal pretending to be `wifi.bahn.de` can't fool CPAL into sending Deutsche Bahn credentials unless it actually is `wifi.bahn.de`.

---

## 6. What We Can Learn

### 6.1 HTTP 204 Probe as Lightweight Detection

The HTTP 204 probe is the gold standard for captive portal detection:
- **Single request, single response code to check.** No HTML parsing, no JavaScript execution, no redirect following.
- **Universally understood.** Every HTTP server, proxy, and captive portal walled garden handles GET requests.
- **Fast.** A 204 response has no body to download. The entire detection round-trip is one packet exchange.
- **Reliable.** Real Google infrastructure reliably returns 204. Anything else is a portal or a broken network.

For our standalone target, we should implement the same detection: `curl -s -o /dev/null -w "%{http_code}" http://connectivitycheck.gstatic.com/generate_204` and check for 204.

### 6.2 Dual HTTP/HTTPS Checking for Reliability

Android 7's parallel HTTPS + HTTP probing solves real problems:
- **HTTPS as positive signal:** If HTTPS works, the network is definitely not captive (SSL certificate validation prevents MITM).
- **HTTP as fallback:** Some networks block HTTPS but allow HTTP. The HTTP probe catches these.
- **Short-circuit design:** Don't wait for both probes; report results as soon as one gives a conclusive answer.

For our standalone scripts, a simpler approach works: check HTTP first. If HTTP returns 204, we're done. If HTTP returns non-204, check HTTPS. If HTTPS returns 204, the HTTP failure was likely a transparent proxy, not a portal. If both fail, it's a portal.

### 6.3 The Notification UX Pattern

Android's UX is worth studying:
1. **Don't interrupt:** Show a notification, don't open the browser automatically.
2. **Let the user decide:** The user taps the notification when ready.
3. **Detect dismissal automatically:** Poll `/generate_204` in the background while the user interacts with the portal. Close automatically when 204 is received.
4. **Provide escape hatches:** "Don't use this network" and "Use as-is" options.

### 6.4 Network Capability Flags for Portal State

The `NET_CAPABILITY_CAPTIVE_PORTAL` flag (value 17) is a clean API design:
- Apps don't need to implement their own detection.
- They register a `NetworkCallback` and get updates when the capability changes.
- The flag is mutable and updated in real-time as detection proceeds.

For our standalone scripts, we don't have this luxury (we're running in shell, not Java). But the concept -- a simple boolean "is this network captive?" -- should guide our design.

### 6.5 Fallback and Resilience

Android's multi-layer fallback system is instructive:
1. Primary: HTTPS + HTTP parallel probe.
2. Fallback URL 1: `http://www.google.com/gen_204`.
3. Fallback URL 2: `http://play.googleapis.com/generate_204`.
4. Configurable probe specs with regex matching.

Each layer catches cases the previous layer missed. This is relevant for our recipe system: we should support multiple detection mechanisms (not just the Google 204 endpoint) and fall through gracefully.

---

## 7. Integration Path for Our Project

### 7.1 Detection: Our Standalone Target vs. Android

| Aspect | Android | Our Standalone Target |
|---|---|---|
| Detection method | HTTP 204 probe to Google + parallel HTTPS | HTTP 204 probe to Google (curl) |
| Trigger | System network events | Cron or WiFi event hook |
| State management | NetworkMonitor state machine (Java) | Simple shell script with exit codes |
| Sign-in | WebView (manual) | Automated via recipe scripts |
| Fallback probes | Multiple URLs, configurable specs | Single URL (extensible) |

Our standalone target should implement the same HTTP 204 detection that Android uses:

```sh
detect_captive_portal() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "http://connectivitycheck.gstatic.com/generate_204")
    [ "$code" = "204" ] && return 1  # not captive
    [ "$code" = "000" ] && return 2  # no connectivity
    return 0  # captive portal detected
}
```

### 7.2 Complementary Roles

Android's detection and our recipe system solve different problems:

- **Android** detects that *a* portal exists and helps the user sign in manually.
- **Our recipes** detect *which* portal exists and sign in automatically.

They're complementary: Android handles detection, we handle automation. A fully integrated system would use Android's `NET_CAPABILITY_CAPTIVE_PORTAL` as the trigger and our recipes as the response (which is exactly what CPAL does on Android).

### 7.3 Our Match Manifest vs. Android's URL-Based Detection

| Aspect | Android | Our Recipe System |
|---|---|---|
| Detection | URL response code (204 vs. non-204) | Domain matching in recipe JSON |
| Identification | None (just knows *a* portal exists) | `travelmate_domain` + `fallback_domains` in recipes |
| Authentication | Manual (user in WebView) | Automated per-recipe scripts |
| Coverage | Universal (detects all portals) | Specific (handles known portals) |
| Failure mode | User must sign in manually | Script fails, user must sign in manually |

Our `travelmate_domain` field serves the same role as Android's redirect URL: it identifies *which* portal the user is behind. Our match manifest (domains, URL patterns, response headers) could be enriched with the same information Android uses (HTTP response code, redirect Location header) for more robust matching.

### 7.4 Practical Integration Points

1. **Detection reuse:** Our standalone scripts should use the same `/generate_204` endpoint Android uses. This is battle-tested across billions of devices.

2. **Android intent hooking:** An Android app could register to receive `ConnectivityManager.ACTION_CAPTIVE_PORTAL_SIGN_IN` and use our recipe logic instead of CaptivePortalLogin's WebView. This is what CPAL does.

3. **Probe spec alignment:** Our recipes could include `CaptivePortalProbeSpec`-style regex patterns for portals that don't use the standard 204 mechanism. Some portals return 200 with specific content; our recipes already handle this via `success_check` fields.

---

## 8. Attribution Notes

### Source Material

- **AOSP source code:** Licensed under Apache 2.0. Source files referenced:
  - [`CaptivePortalLoginActivity.java`](https://android.googlesource.com/platform/packages/modules/CaptivePortalLogin/+/refs/heads/master/src/com/android/captiveportallogin/CaptivePortalLoginActivity.java) -- Main sign-in activity.
  - [`NetworkMonitor.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/packages/NetworkStack/src/com/android/server/connectivity/NetworkMonitor.java) -- Detection state machine.
  - [`CaptivePortalTracker.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/core/java/android/net/CaptivePortalTracker.java) -- Legacy detection (pre-Android 7).
  - [`CaptivePortal.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/core/java/android/net/CaptivePortal.java) -- Binder API for sign-in results.
  - [`CaptivePortalProbeSpec.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/core/java/android/net/captiveportal/CaptivePortalProbeSpec.java) -- Configurable detection specs.
  - [`NetworkCapabilities.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/packages/Connectivity/framework/src/android/net/NetworkCapabilities.java) -- Capability flags.
  - [`CaptivePortalData.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/packages/Connectivity/framework/src/android/net/CaptivePortalData.java) -- RFC 7710bis metadata.
  - [`NetworkStackUtils.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/master/packages/NetworkStack/src/android/net/util/NetworkStackUtils.java) -- Settings constants.

- **Android developer documentation:**
  - [Captive portal API support (Android 11)](https://developer.android.com/about/versions/11/features/captive-portal)
  - [NetworkCapabilities API reference](https://developer.android.com/reference/android/net/NetworkCapabilities)
  - [CaptivePortal API reference](https://developer.android.com/reference/android/net/CaptivePortal)

- **Third-party analysis:**
  - [Bypassing captive portal detection on Android 10 (Neil's blog)](https://neilzone.co.uk/2022/08/bypassing-captive-portal-detection-on-android-10/)
  - [libwebsockets captive portal detection README](https://android.googlesource.com/platform/external/libwebsockets.git/+/refs/heads/main/READMEs/README.captive-portal-detection.md)

### License

AOSP source code is licensed under the Apache License 2.0. This research document describes the system's behavior based on publicly available source code and documentation. No AOSP code is reproduced verbatim; all code snippets are paraphrased descriptions of the logic for educational purposes.

---

## Appendix A: Key Settings.Global Values

| Setting | Default | Purpose |
|---|---|---|
| `captive_portal_mode` | 1 (PROMPT) | 0=ignore, 1=prompt, 2=avoid |
| `captive_portal_http_url` | `http://connectivitycheck.gstatic.com/generate_204` | HTTP probe URL |
| `captive_portal_https_url` | `https://www.google.com/generate_204` | HTTPS probe URL |
| `captive_portal_fallback_url` | `http://www.google.com/gen_204` | Fallback probe URL |
| `captive_portal_other_fallback_urls` | `http://play.googleapis.com/generate_204` | Additional fallback URLs (comma-separated) |
| `captive_portal_fallback_probe_specs` | (none) | Regex-based probe specifications |
| `captive_portal_use_https` | 1 (enabled) | Whether to use HTTPS probing |
| `captive_portal_user_agent` | (none, uses default) | Custom User-Agent for probes |
| `captive_portal_detection_enabled` | 1 (enabled) | Master switch for portal detection |

These can be read/set via ADB:
```sh
adb shell settings get global captive_portal_mode
adb shell settings put global captive_portal_mode 0  # disable detection
```

## Appendix B: Key Intent Extras

When the system launches `CaptivePortalLoginActivity`, it passes these extras:

| Extra | Type | Content |
|---|---|---|
| `ConnectivityManager.EXTRA_NETWORK` | `Network` | The captive network object |
| `ConnectivityManager.EXTRA_CAPTIVE_PORTAL` | `CaptivePortal` | Binder for reporting results |
| `ConnectivityManager.EXTRA_CAPTIVE_PORTAL_URL` | `String` | The URL that triggered portal detection (redirect target) |
| `ConnectivityManager.EXTRA_CAPTIVE_PORTAL_USER_AGENT` | `String` | User-Agent to use for probes |
| `EXTRA_CAPTIVE_PORTAL_PROBE_SPEC` | `String` | Encoded `CaptivePortalProbeSpec` (if configured) |
