# Captive Portal Auto-Login Project Comparison Matrix

**Last updated:** 2026-05-26

This document is a living comparison of all known captive portal auto-login projects. It aims to help developers understand the landscape, identify gaps, and choose the right tool for their needs. Updates are welcome as new projects emerge or existing projects evolve.

---

## 1. Overview

Captive portals force users to authenticate before accessing the internet on public WiFi networks. This matrix compares projects that automate the login process across different platforms, architectures, and authentication mechanisms. Each project takes a different approach, from full-featured Android apps to shell scripts for OpenWrt routers to cross-platform daemons.

The comparison reveals clear specialization: CPAL focuses on Android with extensive portal coverage, Travelmate targets OpenWrt routers with a hook-based architecture, and captive-portal-recipes (this project) provides a declarative, cross-platform recipe system. Other projects address specific niches like single portals or detection-only use cases.

---

## 2. Project Comparison Matrix

| Feature | CPAL | Travelmate | NetworkManager | Android CPL | HotspotAutoLogin | auto-captive-portal (Rust) | captive-portal-recipes (ours) |
|---------|------|------------|----------------|-------------|------------------|----------------------------|-------------------------------|
| **Language** | Kotlin | Shell (ash/bash) | C | Java/Android | Python | Rust | Shell (bash/ash) + JSON |
| **License** | GPL-3.0 | GPL-3.0 | GPL-2.0 | Apache 2.0 | GPL-3.0 | MIT | GPL-3.0 |
| **Platform(s)** | Android 8.0+, Linux (JVM CLI) | OpenWrt | Linux desktop | Android | Windows (primary), macOS, Linux | macOS, Linux, Windows | Cross-platform (macOS, Linux, OpenWrt) |
| **Portal coverage** | 48 handlers | 4 scripts | 0 (detection only) | 0 (detection only) | User-configured | 1 (hardcoded) | 44 recipes |
| **Detection mechanism** | Multi-layer (SSID, URL, body, redirect) | HTTP check, domain extraction | HTTP 204 to connectivity URL | HTTP 204 + DNS | Ping/HTTP check | HTTP 204 + DOM parsing | Match manifest (SSID, domain, path, body) |
| **Auth methods supported** | Form POST, JSON API, CHAP, multipart, JS parsing, GraphQL, Gigya, RADIUS, session-based, redirect | Form POST, JSON API, CSRF, redirect | None (manual only) | None (manual only) | Generic POST | Single POST (form) | Form POST, JSON API, CHAP MD5, CSRF, JS redirect, multi-step form, cookie chain |
| **JS execution capability** | Yes (Rhino) | No | No | No | No | No | No |
| **Multi-step flow support** | Yes | Limited (manual scripting) | No | No | No | No | Yes (multi-step-form template) |
| **Auto-login** | Yes | Yes | No | No | Yes | Yes | Yes |
| **Auto-reconnect** | Yes (foreground service) | Yes (heartbeat) | N/A | Yes (re-auth detection) | Yes | Yes | Planned |
| **Credential storage** | Built-in DB | Environment/config | System keyring | System keyring | Config file | OS keychain | File-based (planned keychain) |
| **Test infrastructure** | 5 test files, manual handler testing | None | Unit tests | AOSP tests | None | None | 44 mock tests, CI pipeline |
| **CI/CD** | GitHub Actions (assumed) | None | GitLab CI | AOSP CI | None | None | GitHub Actions (compile, syntax, mock, deploy) |
| **Community size** | ~100+ stars | Part of OpenWrt (widely used) | System component (installed everywhere) | Part of AOSP | 25 stars, 7 forks | 1 star | TBD |
| **Dependencies** | OkHttp, Jsoup, Rhino, Room, GeckoView | curl, dnsmasq, ubus, iwinfo | glib, systemd | Android framework | Python 3, requests | Rust, scraper, keyring-rs, notify-rust, netwatcher | bash/ash, curl, awk, sed, grep, tr only |
| **Config complexity** | High (Kotlin code per portal) | Medium (shell scripts per portal) | N/A | N/A | Low (JSON profile per portal) | Low (compiled binary) | Low (JSON recipe compiled to script) |
| **OpenWrt compatible** | Yes (JVM CLI module) | Yes (native) | No | No | No | No | Yes (ash target) |
| **Cross-platform** | Partial (Android + Linux) | No (OpenWrt only) | No (Linux only) | No (Android only) | Yes (Windows/macOS/Linux) | Yes (macOS/Linux/Windows) | Yes (macOS/Linux/OpenWrt) |
| **HAR capture support** | Yes (via GeckoView) | No | No | No | No | No | Yes (separate tool) |
| **Cookie management** | Yes | Via curl | System | System | Basic (via requests) | No | Yes (via curl) |
| **GUI** | Yes (Android app) | Yes (LuCI web UI) | Yes (GNOME Settings) | Yes (WebView) | Yes (system tray) | Yes (desktop notifications) | No (CLI only) |

---

## 3. Portal Coverage Overlap

| Portal/SSID | CPAL | Travelmate | Our Recipes | HotspotAutoLogin | Notes |
|-------------|------|------------|-------------|------------------|-------|
| DB Bahn / WIFIonICE | Yes | Yes | Yes | No | Most widely covered portal |
| Telekom DE | Yes | Yes | Yes | No | Multiple portal types |
| Vodafone DE | Yes | Yes | Yes | No | Multiple portal types |
| Cisco Meraki | Yes | No | Yes | No | NetworkAuth handler in CPAL covers Meraki |
| MikroTik | Yes | No | Yes | No | CHAP handler in CPAL (Ruby Hotels) |
| UniFi | Yes | No | Yes | No | UniFi handler in CPAL (experimental) |
| Fortinet | Yes | No | Yes | No | FortiAuthenticator handler in CPAL |
| Aruba | Yes | No | Yes | No | ArubaClearPass + ArubaNetworks + ArubaLP in CPAL |
| Nordsee | Yes | No | Yes | No | German retail chain |
| IKEA | Yes | No | Yes | No | Multiple country variants |
| LEGO Store | Yes | No | Yes | No | German stores |
| Starbucks | Yes | No | No | No | Region-specific |
| REWE | Yes | No | Yes | No | German grocery chain |
| Kaufland | Yes | No | Yes | No | German retail |
| Primark | Yes | No | Yes | No | German retail |
| Douglas | Yes | No | Yes | No | German retail |
| H&M | Yes | No | No | No | German retail |
| dm | Yes | No | No | No | German drugstore |
| EDEKA | Yes | No | No | No | German grocery chain |
| Shell | Yes | No | No | No | Gas station WiFi |
| Generic form portals | Yes | Yes (template) | Yes | Yes | User-extensible |
| Generic JSON API portals | Yes | No | Yes | Yes | User-extensible |
| Click-through portals | Yes | No | Yes | No | No authentication required |
| University SSO | No | No | Yes | No | Microsoft/SAML-based |
| Hotels (generic) | Yes | No | Yes | No | Various chains |

**Key observations:**
- German retail portals have the best coverage, reflecting the German origins of CPAL and this project
- DB Bahn/WIFIonICE is the most battle-tested portal, covered by all three major auto-login projects
- Generic templates (form, JSON, click-through) enable coverage of hundreds of unlisted portals
- No project comprehensively covers US/UK/Australian retail chains

---

## 4. Authentication Capability Matrix

| Auth Method | CPAL | Travelmate | Our Recipes | HotspotAutoLogin | Notes |
|-------------|------|------------|-------------|------------------|-------|
| Simple form POST | Yes | Yes | Yes | Yes | Most common |
| CSRF form | Yes | Yes | Yes | No | Requires token extraction |
| JSON API | Yes | Yes | Yes | Yes | Modern portals |
| CHAP/MD5 | Yes | No | Yes | No | Legacy portals |
| JS parsing | Yes | No | No | No | Requires Rhino/V8 |
| GraphQL | Yes | No | No | No | Rare, modern |
| JWT | No | No | No | No | Not yet supported |
| Multipart | Yes | No | No | No | File uploads |
| Cookie chain | Yes | No | Yes | No | Multi-step cookie persistence |
| Multi-step forms | Yes | Limited | Yes | No | 2+ step authentication |
| Redirect follow | Yes | Yes | Yes | No | Automatic redirect handling |
| SSO/SAML | No | No | Partial | No | Microsoft SSO covered |
| RADIUS | Yes | No | No | No | Backend integration |
| Gigya API | Yes | No | No | No | Third-party auth provider |

**Key observations:**
- CPAL has the most comprehensive auth method support, thanks to JS execution (Rhino)
- Our recipes cover the most common auth methods without requiring JS execution
- CSRF handling is present in three projects, indicating it's a common portal requirement
- JWT and GraphQL are emerging auth methods not yet widely supported

---

## 5. Gap Analysis

The following capabilities are NOT well addressed by any existing project:

### JavaScript-heavy Portals
- **Problem:** Modern portals often use complex client-side JavaScript for authentication, dynamic form generation, and token calculation
- **Current state:** CPAL has Rhino integration but it's experimental and not well-tested. Shell-based solutions (Travelmate, captive-portal-recipes) cannot execute JavaScript
- **Impact:** Airlines, modern hotels, and enterprise portals may be impossible to automate without browser automation

### CAPTCHA Solving
- **Problem:** Many portals now require CAPTCHA challenges (text, image selection, invisible reCAPTCHA)
- **Current state:** NO project handles CAPTCHAs. All rely on portals that offer CAPTCHA-free alternatives (e.g., registered accounts)
- **Impact:** High-security networks (airports, corporate offices) are out of scope

### Multi-scene API Flows
- **Problem:** Some portals require coordinating multiple API calls with complex state management (e.g., CPAL's Conn4 handler)
- **Current state:** Only CPAL handles these, and only via custom Kotlin code per portal
- **Impact:** Advanced authentication flows require custom development

### Auto-detection + Auto-login in One Tool
- **Problem:** Most tools either detect portals OR log in, not both seamlessly
- **Current state:** NetworkManager and Android CPL detect but don't auto-login. Auto-login tools require manual SSID configuration
- **Impact:** Users must manually configure each network, reducing usability

### Cross-platform + OpenWrt Support
- **Problem:** No single tool supports both desktop OS (macOS, Windows) and OpenWrt routers
- **Current state:** CPAL supports Android and Linux (JVM). Travelmate is OpenWrt-only. HotspotAutoLogin is Windows-centric. Our recipes support Linux/macOS and target OpenWrt, but need runtime adaptation
- **Impact:** Users maintain multiple tools for different devices

### Re-authentication for Time-limited Sessions
- **Problem:** Many portals require re-login after 24 hours or bandwidth limits
- **Current state:** CPAL has auto-reconnect via foreground service. Others have limited or no support
- **Impact:** Users must manually re-authenticate daily on long trips

### Password Management Integration
- **Problem:** Storing WiFi credentials securely across devices
- **Current state:** auto-captive-portal uses OS keychain. Others use files, databases, or system keyring. No cross-device sync
- **Impact:** Credential management is fragmented and often insecure

---

## 6. Unique Capabilities per Project

### CPAL (CaptivePortalAutoLogin)
- **Only project with JavaScript execution:** Rhino integration enables handling of portals that require client-side token calculation or dynamic form manipulation
- **HAR capture workflow:** Users can capture live portal interactions via GeckoView and contribute new handlers, making it community-friendly
- **Xposed integration:** Prevents Android system from blocking supported SSIDs, ensuring seamless experience
- **API server for portal submissions:** Crowdsourced portal database with community contribution workflow
- **Foreground service with auto-reconnect:** Keeps authentication alive across network changes

### Travelmate
- **Router-centric architecture:** Designed for OpenWrt, provides whole-network captive portal handling
- **Multiple simultaneous uplinks:** Can manage multiple internet connections with automatic failover
- **VPN hook integration:** Can disable/enable VPN during portal authentication (feature requested by community)
- **LuCI web UI:** User-friendly interface for router-based configuration
- **Per-uplink login scripts:** Different authentication methods for different networks
- **Heartbeat monitoring:** Detects portal failures and re-authenticates

### NetworkManager
- **System-level integration:** Part of the base Linux desktop experience, installed on millions of systems
- **Connectivity checking infrastructure:** Provides reliable detection used by other tools
- **GNOME integration:** Seamless notification and Settings integration
- **Configurable connectivity URL:** Can be adapted for enterprise environments

### Android CaptivePortalLogin
- **System app status:** Deep integration with Android framework
- **Background re-auth detection:** Automatically detects when portal requires re-login
- **Network scoring:** Prioritizes networks based on portal status
- **WebView isolation:** Runs portal in isolated environment for security

### HotspotAutoLogin
- **System tray GUI:** Windows-native user experience
- **Pre-built .exe distribution:** Easy installation for non-technical users
- **Multi-profile support:** Different configurations for different networks
- **Configurable check interval:** User-adjustable polling frequency

### auto-captive-portal (Rust)
- **Cross-platform credential storage:** Uses native OS keychain (Keychain/Secret Service/Credential Manager)
- **Hybrid monitoring:** Combines real-time network events with adaptive polling for efficiency
- **Exponential backoff:** Intelligent retry strategy to avoid portal rate limiting
- **Desktop notifications:** Native system notifications for status changes
- **Cross-platform installer:** Single binary for all major desktop platforms

### captive-portal-recipes (this project)
- **Declarative recipe system:** JSON recipes define portal behavior, compiled to target scripts
- **Multi-target compilation:** Single recipe generates scripts for bash (Linux/macOS) and ash (OpenWrt)
- **Match manifest for auto-detection:** SSID, domain, path, and body-based automatic portal detection
- **Mock test environment:** 44 mock tests ensure recipe correctness without live portal access
- **HAR capture tooling:** Browser extension for capturing portal interactions
- **CPAL importer:** Can migrate CPAL handlers to recipe format
- **GitHub Pages distribution:** Compiled recipes served as static site for easy inclusion
- **CI pipeline:** Automated testing and deployment ensures recipe quality
- **No runtime dependencies:** Only bash/ash, curl, and core utilities required
- **Template-based extensibility:** 8 auth templates cover hundreds of portal variants

---

## 7. Where Our Project Fits

### Position in the Landscape

captive-portal-recipes fills a unique gap between the complexity of CPAL and the simplicity of Travelmate:

- **More portable than CPAL:** Shell-based recipes run anywhere with bash/ash, no JVM or Android required
- **More automated than Travelmate:** Declarative recipes with auto-detection, no manual shell scripting per portal
- **More general than auto-captive-portal:** Template system supports 44+ portals vs. 1 hardcoded
- **More testable than HotspotAutoLogin:** Mock test infrastructure ensures recipe correctness

### Overlap with CPAL

- **Shared German focus:** Both projects heavily cover German retail and transport portals (REWE, IKEA, DB Bahn, etc.)
- **Complementary technologies:** CPAL's Rhino-based JS handling could supplement our shell-based templates for complex portals
- **Import capability:** Our CPAL importer can migrate handlers, reducing duplication
- **Different strengths:** CPAL excels at JS-heavy portals; our project excels at deployment flexibility and OpenWrt integration

### Relationship to Travelmate

- **Target compatibility:** Our ash-compiled recipes are designed to work as Travelmate .login scripts
- **Hook vs. engine:** Travelmate provides the hook architecture (detection, scheduling, VPN hooks); we provide the login script engine
- **Synergy:** Travelmate users can drop our compiled .login files into /etc/travelmate/ for instant portal coverage
- **Extending Travelmate:** Our 44 recipes could become the default travelmate login scripts, vastly increasing its out-of-the-box coverage

### Target Use Cases

Our project is ideal for:
- **OpenWrt router users:** Drop compiled .login files into Travelmate for automatic whole-network auth
- **Linux/macOS users:** Run bash-compiled scripts via cron or NetworkManager dispatcher
- **Developers:** Write recipes in declarative JSON, not shell or Kotlin
- **System administrators:** Distribute recipes as packages or GitHub Pages for enterprise fleets
- **Privacy-conscious users:** No telemetry, no cloud services, full local control

### Future Roadmap Integration

Potential areas where our project could leverage others:
- **CPAL integration:** Use CPAL as a backend for JS-heavy portals, triggered by our detection layer
- **Travelmate integration:** Official package for OpenWrt, included as default login scripts
- **NetworkManager integration:** Dispatcher script that runs our bash recipes on auth-pending events
- **Browser extension:** Auto-download recipes based on detected SSID

### What Makes Us Different

1. **Declarative over imperative:** Recipes describe what the portal does, not how to interact with it
2. **Multi-target compilation:** Single source of truth for bash and ash environments
3. **Testability first:** Mock tests for every recipe, CI pipeline for quality assurance
4. **No runtime dependencies:** Works on minimal systems without Python, Node.js, or JVM
5. **Auto-detection built-in:** Match manifest enables automatic recipe selection without manual SSID configuration
6. **Extensibility through templates:** 8 auth templates cover hundreds of portal variants without custom code
7. **Community distribution model:** GitHub Pages enables zero-config inclusion by other projects

---

## Appendix: Projects Excluded from Comparison

The following projects were reviewed but excluded due to narrow scope:

- **Wifi-Captive-Portal-Auto-Authentication:** Python script for a single university's Microsoft SSO portal. Too niche for comparison.
- **wifi-portal-login:** PowerShell script for a single hotel (Hotel Rio Karlsruhe). Extremely narrow use case.

These projects demonstrate that captive portal automation is often done ad-hoc for specific environments, reinforcing the need for a general-purpose solution.

---

## Contributing

This comparison is maintained as living documentation. To suggest updates:
1. Open an issue with new project information
2. Submit a pull request with corrections or additions
3. Provide sources (GitHub links, documentation, etc.) for any claims

---

## References

- CPAL: https://github.com/binarynoise/CaptivePortalAutoLogin
- Travelmate: https://github.com/openwrt/packages/tree/master/net/travelmate
- NetworkManager: https://gitlab.freedesktop.org/NetworkManager/NetworkManager
- Android CaptivePortalLogin: https://android.googlesource.com/platform/packages/apps/CaptivePortalLogin
- HotspotAutoLogin: https://github.com/denizsafak/HotspotAutoLogin
- auto-captive-portal: https://github.com/AmanSikarwar/auto-captive-portal
- captive-portal-recipes: https://github.com/Amperstrand/captive-portal-recipes