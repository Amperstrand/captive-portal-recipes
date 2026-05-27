# CaptivePortalAutoLogin (CPAL) — Deep Research Document

> Source: [github.com/binarynoise/CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin)
> License: GPL-3.0
> Maintainer: binarynoise
> Date: 2026-05-26

---

## 1. Overview

### Purpose

CPAL is an Android app and Linux CLI that detects captive portals and automatically authenticates (\"liberates\") the user without interaction. It runs as a foreground service monitoring network state and triggers the liberator engine when a portal is detected.

### Repository

- **URL:** `https://github.com/binarynoise/CaptivePortalAutoLogin`
- **License:** GPL-3.0 (no LICENSE file in repo, stated in documentation)
- **Language:** Kotlin (JVM, multiplatform for some modules)

### Architecture

The project is a multi-module Gradle build with these key modules:

| Module | Purpose |
|--------|---------|
| `app/` | Android application — foreground service, settings UI, GeckoView-based HAR capture, Xposed hooks |
| `liberator/` | Core engine — portal detection, handler dispatch, all 47 portal handlers |
| `api/` | Shared HAR/JSON data models (Kotlin Serialization) |
| `api/client/` | HTTP API client for submitting HAR files, reporting success/error |
| `api/server/` | Ktor-based HTTP server that receives HAR submissions, error/success reports; stores in SQLite + JsonDB |
| `linux/` | JVM CLI that monitors NetworkManager via `nmcli` and runs the liberator |
| `util/okhttp-kts/` | OkHttp extension functions (JSoup parsing, form submission, redirect following) |
| `util/rhino/` | JavaScript parser using Mozilla Rhino AST — extracts variable assignments from portal JS |
| `util/logger/` | Cross-platform logging |
| `util/fileDB/` | JSON file storage (JsonDB) and CSV storage |

### Key Source Files

| File | Path |
|------|------|
| Portal interface | `liberator/src/main/kotlin/de/binarynoise/liberator/PortalLiberator.kt` |
| Liberation engine | `liberator/src/main/kotlin/de/binarynoise/liberator/Liberator.kt` |
| Portal detection | `liberator/src/main/kotlin/de/binarynoise/liberator/PortalDetection.kt` |
| Fake data | `liberator/src/main/kotlin/de/binarynoise/liberator/FakeData.kt` |
| Rhino parser | `util/rhino/src/main/kotlin/RhinoParser.kt` |
| HAR models | `api/src/main/kotlin/json/har/` |
| API server | `api/server/src/main/kotlin/ApiServer.kt` |
| API client | `api/client/src/main/kotlin/ApiClient.kt` |
| HAR capture | `app/src/main/kotlin/.../gecko/ExtensionDelegate.kt` |
| Gecko activity | `app/src/main/kotlin/.../gecko/RecordCaptivePortalActivity.kt` |
| HAR factory | `app/src/main/kotlin/.../json/HarFactory.kt` |

---

## 2. Portal Handler Catalog

### Handler Interface

Every handler implements `PortalLiberator` with two methods:

- **`canSolve(response: Response): Boolean`** — examines the HTTP response (URL, headers, body) to determine if this handler can authenticate with the portal.
- **`solve(client: OkHttpClient, response: Response, extras: LiberatorExtras)`** — performs the authentication sequence.

Some handlers also implement `PortalRedirector` for intermediate redirect resolution.

Annotations used:
- `@SSID("ssid1", "ssid2", ...)` — documents which SSIDs use this handler; `mustMatch=true` restricts handler to matching SSIDs only
- `@Experimental` — marks incomplete/untested handlers, disabled by default
- `@Verified` — marks tested/production handlers
- `@FortiAuthenticatorSubPortal` — marks sub-handlers that run after FortiAuthenticator redirect

### Handler Table

> **48 handlers total** (47 active + 1 `_Template`). Complexity ratings:
> - **simple**: Single HTTP request, click-through
> - **medium**: 2-3 requests, form parsing, cookie handling
> - **complex**: 4+ requests, JS parsing, multi-step auth, API token exchange

| # | Handler | SSIDs | Matching Logic | Auth Method | Complexity | Our Recipe |
|---|---------|-------|----------------|-------------|------------|------------|
| 1 | **AenaES** | `AIRPORT FREE WIFI AENA` | `host == "freewifi.aena.es"` | Gigya API registration with random email, token exchange, account verification, network authorization (10+ requests) | complex | — |
| 2 | **Alnatura** | `Alnatura-Kunden-WLAN` | `host == "cppm-auth.alnatura.de"` | Multi-step form chain: followRedirect → submitOnlyForm × 3 | medium | `alnatura-kundenwlan` |
| 3 | **Arista** | `Commerzbank-Wifi2.0` | `host.endsWith(".agni.arista.io") && firstPathSegment == "portal"` | Single POST to `/portal/{orgId}/clickThrough/logon` | simple | `arista-clickthrough` |
| 4 | **Inditex** (ArubaClearPass) | `Bershka-WiFi`, `PULL&BEAR-FreeWiFi`, `Stradivarius-WiFi`, `Zara-WiFi` | `host == "wifi.inditex.com"` | Multi-step: submitOnlyForm → submitOnlyForm → performArubaLogin with extracted credentials | medium | — |
| 5 | **UrbanOutfitters** (ArubaClearPass) | `URBAN_GUEST_WIFI` | `host == "register.urbn.com"` | Same ArubaClearPass pattern | medium | — |
| 6 | **TallyWeijl** (ArubaClearPass) | `Tally's Bunny Wifi` | `host == "guestportal.tally-weijl.com"` | Same ArubaClearPass pattern | medium | — |
| 7 | **Primark** (ArubaLP) | `PRIMARK_PUBLIC` | `host == "www.primark.com"` | Single POST with fixed credentials to Aruba LP portal | simple | `primark-wifi` |
| 8 | **Segmueller** (ArubaLP) | `Segmueller-Hotspot` | `host == "hotspot.segmueller.de"` | Single POST with hardcoded user/password to Aruba captive portal | simple | `segmueller-hotspot` |
| 9 | **ArubaNetworks** | `H&M Free WiFi`, `IKEA WiFi`, `LEVIS GUEST` | `host.endsWith(".cloudguest.central.arubanetworks.com")` with path/query checks | Parse JS via Rhino for `portal_login_page_config`, accept terms, extract credentials from JSON, then Aruba login | complex | — |
| 10 | **BinarynoisePortalProxy** | — | `host == "portal.binarynoise.de" && port == 8001` | Single POST to `/login` with empty body | simple | `binarynoise-proxy` |
| 11 | **BlockHouse** | `BLOCK HOUSE WIFI` | `host == "wlan.block-house.de"` | Parse JS via Rhino for `port` and `postToUrl`, construct form POST with timestamp | complex | — |
| 12 | **Carglass** | `NEU_Carglass-Gast-Zugang` (mustMatch) | `decodedPath == "/reg.php" && hasQueryParameter("url")` | Also implements PortalRedirector: parses JS for `redirURL`; then POST form with checkbox | complex | — |
| 13 | **CiscoISE** | `SSB fuer Dich - WiFi Free` | `isRedirect && encodedPath == "/portal/gateway" && action == "cwa"` | Accept AUP via POST with token, then trigger CoA (Change of Authorization) | medium | `cisco-ise-cwa` |
| 14 | **CiscoWirelessMobility** | `media-kunden`, `saturn-kunden` | `decodedPath == "/fs/customwebauth/login.html"` with switch_url/redirect params | POST with `buttonClicked=4` to switch_url | simple | `cisco-wireless-mobility` |
| 15 | **CloudWifi** | `-free Milaneo Stuttgart` | `host == "start.cloudwifi.de"` | Find "Easy Login" form, POST, then follow secondary route (JS redirect or hotspot form) | medium | `cloudwifi-milaneo` |
| 16 | **CloudWifiRedirect** | `-free Koenigsbau Passagen`, etc. | External page loads script from `start.cloudwifi.de` | Parse JS via Rhino for deviceMac/userMac/loginUrl, then delegate to CloudWifi.solve | medium | `cloudwifi-milaneo` |
| 17 | **Cloudifi** | `Sephora Where Wifi Beats` | `host == "login.cloudi-fi.net"` | POST with `source=directregister`, then submitOnlyForm | simple | `cloudifi` |
| 18 | **Commerzbank** | `Commerzbank-Wifi` | `host == "wifiaccess.co" && path[1] == "portal"` | Three-step JSON API: init → subscribe → authenticate with extracted credentials | medium | `commerzbank-wifi` |
| 19 | **Conn4** | `-REWE gratis WLAN-`, `movenpick`, `BBHOTELSGuest`, `-Kaufland FreeWiFi-`, `ibisbudget` | `host.endsWith(".conn4.com") && firstPathSegment == "ident"` | Two branches: Scene (parse JS for wbsToken, fetch scene pages, create session, find tariff, register) or Accor (extract wbs-token cookie, API calls). Tariff selection logic with preference ordering | complex | — |
| 20 | **DBWifi** | `WIFIonICE`, `dbs4public` | `host in {login.wifionice.de, portal.wifi.bahn.de, ...}` | Three branches: CNA (JSON POST logon), SP (form POST with terms), default (CSRF token form) | medium | `wifibahn` ✓ |
| 21 | **DerTour** | `DERTOUR` (mustMatch) | `isIp && firstPathSegment == "authen"` | submitOnlyForm | simple | `dertour-guest` |
| 22 | **Dokom21Hotspot** | `DSW21-WLAN`, `Hotspot Westfalenhallen` | `host == "hotspot.dokom21.de"` with regex path match | ASP.NET: GET Login page, extract ViewState/EventValidation, POST with AGB acceptance | medium | `dokom21-hotspot` |
| 23 | **DseTech** | `DeichmannGast` | `host == "disclaimer.dse-tech.net" && !isRedirect` | submitOnlyForm (FortiAuthenticator sub-portal) | simple | `dse-tech` |
| 24 | **FortiAuthenticator** | `ITS - FREEWIFI`, `Douglas Guest` | `port == 1000 && firstPathSegment == "fgtauth"` | submitOnlyForm with `answer=1`; also has FortiAuthenticatorRedirect that parses JS `window.location` | simple | `fortinet-clickthrough` ✓ |
| 25 | **FotoProfi** | `Fotoprofi-Gast` (mustMatch) | `isIp && lastPathSegment == "index.shtml" && hasQueryParameter("redirect")` | Multipart form POST with extracted hidden fields to `/wgcgi.cgi` | complex | — |
| 26 | **FritzBox** | — | `firstPathSegment == "untrusted_guest.lua"` | Single GET to `/trustme.lua?accept=` | simple | `fritzbox-guest` |
| 27 | **Hotsplots** | `Bogestra`, `KampsHotspot`, `WIFI@DB`, etc. | `isEricssonCaptured() && (host/path matches hotsplots.de)` | submitOnlyForm, follow redirects until `isEricssonSuccess()` | simple | `hotsplots` |
| 28 | **IOB** (redirector) | `RRX Hotspot` | `host == "portal.iob.de" && hasQueryParameter("loginurl")` | Redirects to the login URL extracted from query parameter | simple | (covered by hotsplots) |
| 29 | **IKEA** | `IKEA WiFi` | `host == "yo-wifi.net" && firstPathSegment == "authen"` | Follow redirect, POST for token, parse JSON for realm/username/password, construct userid, GET with credentials | complex | — |
| 30 | **IMasterNCE** | `Cosmo-Gast` | `host == "device.imaster-nce.de" && port == 19008` | POST to `/portalauth/login` with anonymous credentials, agreed=1 | simple | `imaster-nce` |
| 31 | **Intersport** | `INTERSPORTkundenwlan` | `host == "wlan.intersport-gruppe.de" && !isRedirect` | Parse HTML for login link, GET that URL | simple | `intersport-kundenwlan` |
| 32 | **MistCom** (Juniper) | `Rossmann Kunden-WLAN` | `isMistPortalUrl(host)` — host starts with `portal.` and ends with `.mist.com` | POST to `/logon` with ap_mac, auth_method=passphrase, tos=true | simple | `mist-portal` |
| 33 | **Abercrombie** (Juniper ext.) | `@Hollister Co. Free Wi-Fi` | `host == "storewifi.abercrombie.com"` + authorize_url is mist.com | Generate JWT (HS256), GET authorize endpoint with jwt parameter | complex | — |
| 34 | **LancomCloudServiceHotspot** | `emilioadani-Spot` | `host == "hotspot.lmc.de" && firstPathSegment == "cloud-service-hotspot"` | POST empty form | simple | `lancom-cloud` |
| 35 | **LegoStore** | `LEGO Store Guest` (mustMatch) | `isIp` (any IP address) | submitOnlyForm | simple | `lego-store-guest` |
| 36 | **MaxxArena** | `MesseSpot` | `host == "hotspot.maxxarena.de"` | POST `auth=free` | simple | `maxx-arena` |
| 37 | **MesseDresden** | `Dresden` | `host == "aerolan.ibh.de" && firstPathSegment == "messe"` | Parse HTML for login link, GET that URL | simple | `messe-dresden` |
| 38 | **MyPowerspotDE** | — | `host == "login.mypowerspot.de"` | GET `/landingpage/`, then GET with `acceptTOC=1` | simple | `mypowerspot-de` |
| 39 | **NetworkAuth** | `BACK-FACTORY Besucher`, `MEET ME @ STARBUCKS`, `JD-Gast-WiFi`, `DrMartens`, `P&C Hotspot`, etc. | `host.endsWith("network-auth.com") && !isRedirect` | GET `grant` endpoint, follow redirects within network-auth.com | simple | `cisco-meraki` ✓ |
| 40 | **NetworkAuthSubPortal** | `dm Kunden WLAN`, `EDEKA free-wifi` | network-auth.com + isRedirect + redirect URL has base_grant_url with grant path | Delegates to NetworkAuth.solve | simple | `cisco-meraki` ✓ |
| 41 | **Nordsee** | `Nordsee Gast` | `host == "guests.nordsee.com"` | Parse HTML for hidden `pfsenseurl` input, POST its query params as both query and form | simple | `nordsee-gast` |
| 42 | **Picopoint** | — | `host == "gatekeeper2.picopoint.com" && lastPathSegment == "options"` | Parse HTML form (pseudo_auth_form), GET session for client_mac, POST form with custom_data_1 | medium | `picopoint-shell` |
| 43 | **PicopointRedirector** | `Shell Free WiFi` | gatekeeper2.picopoint.com + JS `window.location` assignment | Parse JS for redirect URL, follow it | simple | `picopoint-shell` |
| 44 | **RheinRuhr** | `Hotspot S-Bahn Rhein-Ruhr` | `host == "10.10.10.1" && port == 2050 && firstPathSegment == "splash.html"` | Parse HTML for tok/redir hidden inputs, GET nodogsplash_auth | simple | `rhein-ruhr` |
| 45 | **RubyHotels** | `RUBY-HOTEL` | `host == "hotspot.ruby-hotels.com"` + login URL pattern | Parse HTML for link with username param, GET that link | simple | `ruby-hotels` |
| 46 | **RubyWorkspaces** | `Ruby Workspaces` | `host == "hotspot.ruby-workspaces.com"` + login URL pattern | Parse JS for CHAP parameters (hexMD5 call with octal-encoded chapId/chapChallenge), compute MD5 hash, POST with CHAP password | complex | `ruby-workspaces` |
| 47 | **SocialWave** | `FreeWiFi 24 Autohof Mühldorf`, `FreeWiFi Burger King`, etc. | `host in {go.social-wave.com, go.meinwlan.com}` + has `res` and `auth` query params | GET hello.json from splash API, POST email registration with random email, construct auth URL (OpenWrt nodogsplash or RouterOS), GET auth URL | complex | — |
| 48 | **SocialwiBox** | — | `host == "hotspot.socialwibox.com"` | 5-step chain: POST redirect form → GET terms link → follow redirect → parse JS `redirectPost()` for URL+JSON data → POST → POST final form | complex | — |
| 49 | **StadtwerkeStuttgart** | `Solarbank-WLAN` (mustMatch) | `isIp && lastPathSegment == "macauth"` + uamport/uamip/userurl params | Construct UAM URL from query params, GET with empty credentials and agreetos=1 | simple | `stadtwerke-stuttgart` |
| 50 | **TMobileHotspot** | `Telekom_free`, `Airport-Frankfurt`, `AIRPORT-FREE-WIFI`, `Telekom`, etc. | `host == "hotspot.t-mobile.net" && decodedPath == "/wlan/redirect.do"` | POST JSON `{"rememberMe":false}` to `/wlan/rest/freeLogin` | simple | `t-mobile-hotspot` |
| 51 | **TargetBox** | `Zalando Free Wifi` | `host == "wifi.targetbox.de"` | POST JSON with gateway params to `/wifidog/skip`, GET redirectUrl | simple | `targetbox` |
| 52 | **TheCloud** | `HUGO-BOSS-WIFI`, `WiFi Darmstadt`, `mycloud`, `o2 free Wifi` | `host == "service.thecloud.eu" && isHttps` | GET `getonline`, POST to `macauthlogin/v2/registration` with terms=true | simple | `the-cloud` |
| 53 | **UniFi** | `L'Osteria`, `Henri Willig GUEST` | `encodedPath.startsWith("/guest/s/")` | GET hotspotconfig (broken JSON parser), verify auth=none, POST to `login`, follow redirect_url | medium | `unifi-guest` |
| 54 | **UniStuttgartOpen** | `uni-stuttgart-open` | `host == "guest-internet.tik.uni-stuttgart.de"` | Parse HTML for mac hidden input, POST to `/login` with accept=1 | simple | `uni-stuttgart-open` |
| 55 | **Unwired** | `VIAS Free WiFi`, `arverio_freewifi`, `DonauparkCamping`, etc. (+ regex `/WLAN@RB\\s[0-9]+/`) | `host in {wasabi-splashpage.wifi.unwired.at, wasabi.hotspot-local.unwired.at}` | GraphQL: query splashpage for ConnectWidget ID, then mutation client_connect with x-request-id header | complex | `unwired-graphql` |
| 56 | **VodafoneHotspot** | `@VodafoneWifi`, `Kunstmuseum WLAN`, etc. | `host == "hotspot.vodafone.de"` | GET `/api/v4/session`, extract loginProfile ID, POST `/api/v4/login` | medium | `vodafone-de` ✓ |

### Auth Method Distribution

| Method | Count | Handlers |
|--------|-------|----------|
| **form-submit** (single POST) | 15 | Arista, BinarynoisePortalProxy, Cloudifi, DerTour, DseTech, FritzBox, Lancom, LegoStore, MaxxArena, MyPowerspotDE, Intersport, MesseDresden, TheCloud, CiscoWirelessMobility, StadtwerkeStuttgart |
| **submitOnlyForm** (auto-extract + POST) | 7 | Alnatura, Hotsplots, Dokom21Hotspot (partial), NetworkAuth, NetworkAuthSubPortal, DseTech, LegoStore |
| **json-api** (POST/GET JSON) | 8 | Commerzbank, TMobileHotspot, TargetBox, VodafoneHotspot, IMasterNCE, DBWifi (CNA branch), MistCom, FortiAuthenticator |
| **graphql-api** | 1 | Unwired |
| **csrf-form-submit** | 1 | DBWifi (default branch) |
| **click-through-grant** | 2 | NetworkAuth, NetworkAuthSubPortal |
| **chap-md5** | 1 | RubyWorkspaces |
| **jwt-hs256** | 1 | Abercrombie |
| **multi-step-form** (3+ form steps) | 3 | ArubaClearPass variants, CloudWifi |
| **complex JS/API** | 6 | AenaES, ArubaNetworks, Conn4, IKEA, SocialWave, SocialwiBox |
| **JS parse + form** | 3 | BlockHouse, Carglass, Picopoint |
| **HTML link follow** | 3 | RubyHotels, Intersport, MesseDresden |

---

## 3. HAR Capture System

### Overview

CPAL includes a GeckoView-based traffic capture system that records all HTTP requests/responses during a portal interaction. The captured data is structured as HAR (HTTP Archive) format and submitted to the CPAL API server for analysis.

### Key Source Files

| File | Purpose |
|------|---------|
| `app/.../gecko/RecordCaptivePortalActivity.kt` | Android activity hosting GeckoView browser |
| `app/.../gecko/ExtensionDelegate.kt` | WebExtension that intercepts all traffic via browser.webRequest API |
| `app/.../json/HarFactory.kt` | Converts WebExtension events to HAR model objects |
| `api/src/main/kotlin/json/har/` | HAR data models (HAR, Log, Entry, Request, Response, etc.) |
| `api/client/src/main/kotlin/ApiClient.kt` | HTTP client for submitting HAR files to server |
| `api/server/src/main/kotlin/ApiServer.kt` | Server-side HAR storage via JsonDB |
| `api/server/src/main/kotlin/routes/stats/har.kt` | Ktor routes for browsing/downloading HAR files |

### Capture Workflow

1. **User taps "Capture portal"** in the app
2. **RecordCaptivePortalActivity** launches, receiving the `CaptivePortal` and `Network` objects from Android's connectivity framework
3. A **GeckoView** instance opens in private mode with a custom **WebExtension** (`captivePortalAutoLoginTrafficCapture@binarynoise.de`)
4. The extension is configured with:
   - `routeToApp: true` — forward all traffic events to the app
   - `stringify: false` — pass raw data
   - `blockWs: true` — block WebSocket connections
5. The **portal test URL** is loaded in the browser, which triggers the captive portal redirect
6. The user manually navigates the portal and completes authentication
7. **ExtensionDelegate** intercepts every browser.webRequest event:
   - `onBeforeRequest` → creates Request object, captures POST data
   - `onBeforeSendHeaders` / `onSendHeaders` → captures request headers
   - `onHeadersReceived` → creates Response object with status code
   - `onResponseStarted` → captures response headers
   - `onCompleted` → finalizes the entry
   - `onBeforeRedirect` → finalizes current entry, increments redirect counter
   - `onAuthRequired` → captures auth challenge
   - `onErrorOccurred` → captures error
   - `filter.onStop` → captures response body content
8. Each request/response pair is assembled into a HAR `Entry` with timing data
9. When the network validates (NET_CAPABILITY_VALIDATED), the activity detects success
10. User is prompted: **"Submit recording?"** with a warning about personal data
11. If agreed, the HAR is submitted via `Api.Har.submitHar(name, har)`

### HAR File Format

CPAL uses the standard HAR 1.2 specification (http://www.softwareishard.com/blog/har-12-spec/). The data models in `api/src/main/kotlin/json/har/` are:

- **HAR** — top-level container with `log` and optional `comment` (set to SSID)
- **Log** — `version`, `creator` (app name/version), `browser` (Gecko version), `pages`, `entries`
- **Entry** — `startedDateTime`, `request`, `response`, `cache`, `timings`
- **Request** — `method`, `url`, `httpVersion`, `cookies`, `headers`, `queryString`, `postData`
- **Response** — `status`, `statusText`, `cookies`, `headers`, `content`, `redirectURL`
- **PostData** — `mimeType`, `params` (list of PostParam), `text`
- **Content** — `size`, `mimeType`, `text`, `encoding` (base64 for binary)

Binary content detection uses a heuristic: if more than 20% of characters appear to be binary, content is Base64-encoded with `encoding: "base64"`.

### Anonymization

The capture system does **not** anonymize data. The README explicitly warns:
> "will contain all personal information you send to the portal"

Users are warned before submission:
> "Please do not share this network if you entered any kind of personal data or passwords."

### API Server

The server (Ktor-based) has these HAR-related routes:

| Route | Method | Purpose |
|-------|--------|---------|
| `har/` | GET | List all HAR files grouped by domain |
| `har/download/{id}` | GET | Download a specific HAR file |
| `har/archive/{id}` | POST | Move HAR file to archived directory |
| `har/group/{domain}/` | GET | List HAR files for a specific domain |
| `har/har-upload` | GET | Upload form page |

HAR files are stored as JSON on disk via `JsonDB` under the `har` collection. The naming convention is `{ssid} {host} {timestamp}`.

### Feedback Loop

The HAR capture feeds back into handler development:
1. Users capture portal interactions
2. HAR files show exact request/response sequences
3. Developer studies HAR to understand the auth flow
4. New handler is written matching the observed behavior
5. Success/error reporting (`Api.Liberator.Success`/`Error`) tracks which handlers work in production

---

## 4. Rhino JavaScript Parser

### Purpose

Many captive portals embed configuration data and redirect logic in JavaScript. The Rhino parser extracts variable assignments from JS without executing it, using Mozilla Rhino's AST parser.

### Key Source Files

| File | Purpose |
|------|---------|
| `util/rhino/src/main/kotlin/RhinoParser.kt` | Main parser class |
| `util/rhino/src/main/kotlin/DebugPrintVisitor.kt` | Debug AST visitor |
| `util/rhino/src/test/kotlin/RhinoParserTest.kt` | Comprehensive test suite |

### API Surface

```kotlin
class RhinoParser(debug: Boolean = false) {
    fun parseAssignments(js: String, onlyFirstOccurrence: Boolean = false): Map<String, String>
}
```

- **Input:** Raw JavaScript source code
- **Output:** `Map<String, String>` mapping variable paths to their string values
- **`onlyFirstOccurrence`**: When true, keeps only the first assignment to each variable; when false (default), later assignments overwrite earlier ones

### What It Parses

The parser handles these JavaScript constructs:

1. **Variable declarations** — `var x = 'value'`, `let a = null`
2. **Assignments** — `obj.prop = 'value'`, `a.b.c = 'nested'`
3. **Object literals** — `var config = { host: 'localhost', port: 5432 }` → extracts `config.host`, `config.port`
4. **Nested objects** — Recursive extraction of deeply nested properties
5. **Array literals** — `var a = [1, 2, 3]` → stored as raw source `[1, 2, 3]`
6. **Bracket notation** — `obj['key']`, `arr[0]`, `obj[true]`
7. **Mixed access** — `a.b[0].c[1] = 'complex'` → path `a.b.0.c.1`
8. **Function calls** — `a("test")` → stored as `a.0 = "test"`
9. **String keys with spaces** — `var a = { 'key with spaces': 'value' }` → path `a.key with spaces`

### Test Cases (from RhinoParserTest)

The test suite validates:

| Category | Example | Result |
|----------|---------|--------|
| Simple assignment | `var a = 1;` | `a → "1"` |
| String literal | `var a = 'test';` | `a → "test"` |
| Null/undefined | `let a = null;` / `var a = undefined;` | `a → "null"` / `a → "undefined"` |
| Object literal | `var a = { b: 2 };` | `a.b → "2"` |
| Nested object | `var a = { b: { c: 'test' } };` | `a.b.c → "test"` |
| Array | `var a = [1, 2, 3];` | `a → "[1, 2, 3]"` |
| Deep nesting | `config.api.endpoints.users` | Full dot-path extraction |
| Bracket access | `obj['key'] = 'value';` | `obj.key → "value"` |
| Number index | `arr[0] = 'first';` | `arr.0 → "first"` |
| Boolean index | `obj[true] = 'v';` | `obj.true → "v"` |
| Mixed | `a.b[0].c[1] = 'complex';` | `a.b.0.c.1 → "complex"` |
| Conditional expr | `var a = b \|\| {};` | `a → "b \|\| {}"` (raw source) |
| Function call | `a("test");` | `a.0 → "test"` |
| Method call | `a.b("test");` | `a.b.0 → "test"` |
| `this.prop` | `this.prop = 'this';` | `prop → "this"` |
| `window.global` | `window['global'] = 'window';` | `window.global → "window"` |
| Unsupported dynamic | `obj[func()] = 'v';` | Skipped (0 assignments) |
| Reassignment | `var a = 1; a = 2;` | With `onlyFirstOccurrence=true`: `a → "1"`; default: `a → "2"` |

### Limitations

1. **No expression evaluation** — `var a = b || {}` stores `"b || {}"`, not the evaluated value
2. **No dynamic key support** — `obj[func()]` is skipped
3. **No runtime values** — Can't resolve variable references; `var b = a` stores `"a"` not the value of `a`
4. **No function bodies** — Only captures call arguments, not function definitions
5. **Fallback to raw source** — For unsupported AST nodes, falls back to `node.toSource()`
6. **Spread properties ignored** — `{...other}` in object literals is logged but not processed

### How It Enables JS-Heavy Portal Handling

Handlers that use the Rhino parser:

| Handler | What it extracts |
|---------|------------------|
| ArubaNetworks | `portal_login_page_config` JSON object from inline script |
| BlockHouse | `port`, `postToUrl` from script |
| Carglass | `redirURL` from script |
| CloudWifi | `FX_redirect.0` (deviceMac), `FX_redirect.1` (userMac), `FX_redirect.2` (loginUrl) |
| Conn4 | `conn4.hotspot.wbsToken.token`, `_.partial.1` schedule data |
| FortiAuthenticator | `window.location` redirect URL |
| Picopoint | `window.location` redirect URL |
| RubyWorkspaces | `hexMD5(...)` call arguments (CHAP parameters) — uses regex, not Rhino |

---

## 5. Detection System

### Key Source Files

| File | Purpose |
|------|---------|
| `liberator/.../PortalDetection.kt` | Detection backend definitions |
| `liberator/.../Liberator.kt` | Detection execution flow |

### Detection Backends

CPAL defines 8 captive portal detection backends in `PortalDetection.backends`:

| Backend | HTTP URL | HTTPS URL |
|---------|----------|-----------|
| **Binarynoise** (default) | `http://am-i-captured.binarynoise.de` | (same) |
| **Google** | `http://connectivitycheck.gstatic.com/generate_204` | `https://www.google.com/generate_204` |
| **Apple** | `http://captive.apple.com/hotspot-detect.html` | — |
| **Microsoft** | `http://www.msftconnecttest.com/connecttest.txt` | — |
| **Gnome NetworkManager** | `http://nmcheck.gnome.org/check_network_status.txt` | — |
| **KDE** | `http://networkcheck.kde.org/` | — |
| **Fedora** | `http://fedoraproject.org/static/hotspot.txt` | — |
| **Arch Linux** | `http://ping.archlinux.org/` | — |

Each backend is a `PortalTestURL` containing both HTTP and HTTPS URLs.

### User Agent Spoofing

10 user agents are defined for different platforms:

| Platform | User Agent |
|----------|-----------|
| Chrome/Android | Mobile Chrome 129 on Android 10 |
| Firefox/Android | Mobile Firefox 130 on Android 14 |
| Chrome/Windows | Chrome 129 on Win10 |
| Firefox/Windows | Firefox 130 on Win10 |
| Chrome/Linux | Chrome 129 on Linux |
| Firefox/Linux | Firefox 130 on Linux |
| Chrome/iOS | Chrome iOS 129 |
| Firefox/iOS | Firefox iOS 130 |
| AOSP | AOSP browser (X11; Linux) |

Default: Chrome/Android.

### Detection Flow

The `Liberator.liberate()` method orchestrates detection:

```
1. isCaughtInPortal()
   ├── Try HTTP probe (GET to httpUrl)
   │   ├── Follow redirects (Location header, PortalRedirectors)
   │   ├── If !isSuccessful || redirected → in portal
   │   └── If successful and not redirected → not in portal
   ├── Try HTTPS probe (GET to httpsUrl)
   │   ├── If SSLException/CertPathValidatorException → still in portal
   │   │   (portal blocks HTTPS but allows HTTP through)
   │   └── If successful → not in portal
   └── Both probes redirected → in portal, return redirected response

2. If in portal → recurse(response, depth=0)
   ├── Filter handlers: exclude experimental (unless enabled), check SSID mustMatch
   ├── Call canSolve() on each handler
   ├── If solvers found → call solve() on each, return Success
   └── If no solvers → follow redirects, recurse with depth+1 (max 10)
```

### HTTP vs HTTPS Probing

The detection tries both HTTP and HTTPS:

1. **HTTP probe first** — if it goes through (200 + no redirect), we're free
2. **HTTPS probe second** — catches portals that allow HTTP but block HTTPS
3. **SSL errors = still captive** — if HTTPS throws `SSLException` or `CertPathValidatorException`, the portal is still intercepting (even though HTTP passed)
4. **Both must succeed** for "not in portal" result

### Redirect Resolution

When no handler matches, the engine follows redirects via `PortalRedirector` chain:

1. All registered `PortalRedirector` implementations are checked
2. `LocationRedirector` (built-in) follows HTTP Location headers
3. Custom redirectors (e.g., `FortiAuthenticatorRedirect`, `PicopointRedirector`) parse JS for redirect URLs
4. Maximum recursion depth: 10

### Post-Liberation Verification

After a handler claims success, the engine re-checks captive portal status (up to 3 tries with 1s delay). If still captured, returns `StillCaptured` instead of `Success`.

### Cookie Management

The `Liberator` maintains a cookie jar across all requests:
- Cookies are extracted from responses and stored
- Cookies are sent with subsequent requests based on domain matching
- This is essential for multi-step auth flows where session cookies are set by intermediate pages

---

## 6. What We Can Learn

### Auth Patterns for Our Recipe Schema

From studying CPAL's handlers, these auth patterns should be considered for our recipe JSON schema:

1. **ASP.NET ViewState extraction** (Dokom21Hotspot) — Extract `__VIEWSTATE`, `__EVENTVALIDATION`, `__VIEWSTATEGENERATOR` hidden fields before form submission. Our schema should support an `extract_hidden_fields` step.

2. **JSON API two-step** (Commerzbank) — Call API to get temporary credentials, then authenticate with those credentials. Pattern: `json-api-extract → json-api-auth`.

3. **GraphQL mutation** (Unwired) — Send GraphQL query to discover widget ID, then mutation to connect. Our schema would need `graphql_query` and `graphql_mutation` step types.

4. **CHAP-MD5** (RubyWorkspaces) — Parse JS for octal-encoded CHAP parameters, compute MD5 hash. This needs custom code but we should document the pattern.

5. **JWT generation** (Abercrombie) — HMAC-SHA256 JWT with payload including ap_mac, wlan_id, client_mac, expires. Our schema could support `jwt_auth` with configurable claims.

6. **Random email generation** (AenaES, SocialWave) — Generate UUID-based email addresses for registration. Our `fake_data` concept covers this.

7. **Multi-step form chain with redirect** (ArubaClearPass) — submitOnlyForm → followRedirect → submitOnlyForm → performArubaLogin. Our schema should support arbitrarily long step chains.

8. **JS variable extraction** (BlockHouse, ArubaNetworks) — Parse inline JavaScript for configuration variables. Our schema could include a `parse_js` step type with variable path extraction.

9. **Tariff selection logic** (Conn4) — Parse available tariffs from API response, filter by criteria (free, not paid, not EAP), sort by duration/bandwidth, try each until one works. This is complex but the filtering criteria could be expressed declaratively.

10. **Ericsson UAM status** (Hotsplots) — Check `res` query parameter for `notyet`/`failed`/`success`/`already` to determine portal state. Our detection logic could use similar patterns.

### Detection Strategies Worth Adopting

1. **Multi-backend probing** — Supporting multiple detection URLs increases compatibility across different network configurations. Our `captive-portal-recipes` could include detection URL recommendations per recipe.

2. **HTTP + HTTPS dual probe** — Testing both HTTP and HTTPS catches edge cases where portals allow one but not the other.

3. **SSL error = captive** — Treating SSL exceptions as "still in portal" is a smart heuristic.

4. **Post-auth verification with retries** — Checking 3 times after auth with 1s delays accounts for slow CoA/RADIUS reauthentication.

5. **SSID-aware handler matching** — Using SSID to pre-filter handlers before URL matching reduces false positives.

### HAR Capture Workflow Improvements

For our project, the CPAL HAR capture approach offers these ideas:

1. **Browser extension approach** — Using a web extension to intercept all traffic is more reliable than proxy-based capture.
2. **Redirect counter per request ID** — Tracking redirect chains per original request prevents confusion.
3. **Binary content detection heuristic** — The 20% binary character threshold is a practical approach.
4. **Cookie tracking across requests** — Essential for understanding multi-step auth flows.
5. **HAR naming convention** — `{ssid} {host} {timestamp}` makes it easy to organize captures.

### Reusable Handler Patterns

1. **submitOnlyForm** — Extract the first form from HTML, collect all inputs, POST. Used by ~15 handlers. Our recipes already support this via `find_form` + `submit_form`.

2. **performArubaLogin** — POST to `/cgi-bin/login` with `cmd=authenticate`, `user`, `password`. Shared by ArubaNetworks, ArubaLP (Segmueller). Could be a reusable "aruba-login" sub-template.

3. **FortiAuthenticatorSubPortal** pattern — Annotation-based marker for handlers that are sub-portals of a parent handler. Our recipes could use a `parent_portal` field.

4. **Ericsson UAM** pattern — Checking `res` query parameter for portal state. Common to Hotsplots and SocialWave. Could be a shared detection pattern.

---

## 7. What We Can Skip

### Android-Specific Features

These CPAL features are specific to the Android app and don't apply to our shell-based recipe compiler:

| Feature | Reason to skip |
|---------|---------------|
| **Foreground Service** (`ConnectivityChangeListenerService`) | Android-specific background monitoring |
| **Xposed Hooks** (5 hooks in `app/.../xposed/`) | Root-level Android framework hooks for accepting connections |
| **GeckoView Integration** | Android-only browser component |
| **WebExtension traffic capture** | Requires GeckoView runtime |
| **Android NetworkCallback** | Platform-specific network event system |
| **CaptivePortal API** (`EXTRA_CAPTIVE_PORTAL`, `reportCaptivePortalDismissed`) | Android system API |
| **Network Suggestions API** | Android Wi-Fi network suggestions |
| **Permissions management** | Android permission model |
| **Boot receiver** | Android startup behavior |
| **Notification UI** | Android status bar notifications |
| **Settings/Preferences UI** | Android preference fragments |

### Features Not Applicable to Shell-Based Approach

| Feature | Reason |
|---------|--------|
| **API server** (Ktor) | We don't need a server for HAR collection |
| **API client** (success/error reporting) | No telemetry needed |
| **JsonDB/CsvDB** | Different persistence model |
| **Onboarding flow** | Android app UX |
| **Multi-module Gradle build** | We use shell scripts + JSON |
| **OkHttp client** | We use `curl` |
| **JSoup HTML parsing** | We use `grep`/`sed` or `xmllint` |

---

## 8. Attribution Notes

- **All behavioral data** in this document is sourced from studying the CPAL codebase at [github.com/binarynoise/CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin), licensed under GPL-3.0.
- **No Kotlin code was copied** into this document or into our recipe files. We describe observed portal behavior only.
- **Recipe JSON files** in our `captive-portal-recipes/recipes/` directory are our own original descriptions of portal authentication behavior, expressed in our own schema format.
- **The handler classification** in our `handlers-classification.md` is our own analysis of which CPAL handlers can be expressed as declarative recipes versus which require custom code.
- **CPAL is a study reference**, not a dependency. Our recipe compiler does not link to, import, or execute any CPAL code.
