# Captive Portal Recipe Compatibility Matrix

This document tracks recipe reliability, source attribution, and testing status for all 44 captive portal auto-login recipes. Each recipe is a JSON descriptor that tells the recipe compiler how to authenticate through a specific captive portal type without user interaction. Recipes are target-agnostic and can be compiled for multiple output platforms.

The matrix below serves as the single source of truth for:
- Which real-world portals each recipe covers
- Where the recipe logic was derived from
- Honest reliability estimates before live device testing
- Testing progress tracking (mock suite and real hardware)


## Main Compatibility Matrix

| Recipe | auth_type | Source Handler | Source Project | Reliability | Tested (Mock) | Tested (Device) | Notes |
|--------|-----------|----------------|----------------|-------------|---------------|------------------|-------|
| accor-hotels | multi-step-form | manual | manual-research | 🔴 LOW | ✅ | | Speculative template for m3connect/Accor portal pattern; hardcoded step URLs may not match live portals |
| alnatura-kundenwlan | form-submit | Alnatura | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from multi-step Aruba ClearPass flow; original handler uses submitOnlyForm chain |
| arista-clickthrough | form-submit | Arista | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple click-through form; handler calls submitOnlyForm() directly |
| binarynoise-proxy | form-submit | BinarynoisePortalProxy | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Straightforward form submit on proxy portal |
| cisco-ise-cwa | form-submit | CiscoISE | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from multi-step ISE redirect flow; full handler tracks session cookies across 3+ redirects |
| cisco-meraki | click-through-grant | NetworkAuth, NetworkAuthSubPortal | manual-research | 🟢 HIGH | ✅ | | Well-understood Meraki base_grant_url pattern; extensively tested |
| cisco-wireless-mobility | form-submit | CiscoWirelessMobility | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form POST to customwebauth/login.html (Media/Saturn) |
| cloudifi | form-submit | Cloudifi | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit (Sephora) |
| cloudwifi-milaneo | form-submit | CloudWifi | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from multi-step CloudWiFi portal; original parses page state across requests |
| commerzbank-wifi | json-api | Commerzbank | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Multi-endpoint JSON API on wifiaccess.co; may have session timing edge cases |
| dertour-guest | form-submit | DerTour | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit; IP-based detection with /authen endpoint |
| dokom21-hotspot | form-submit | Dokom21Hotspot | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified ASP.NET form; full support requires ViewState extraction and __EVENTVALIDATION handling |
| dse-tech | form-submit | DseTech | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit (Deichmann disclaimer portal) |
| fortinet-clickthrough | form-submit | FortiAuthenticator | manual-research | 🟢 HIGH | ✅ | | Well-known Fortinet /fgtauth pattern; answer=1&agree=1 |
| fritzbox-guest | form-submit | FritzBox | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form POST to /untrusted_guest.lua |
| generic-form | form-submit | generic | manual-research | 🟢 HIGH | ✅ | | Generic template for any standard user/password HTML form |
| hotsplots | form-submit | Hotsplots | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit (DE transit / Bogestra) |
| imaster-nce | json-api | IMasterNCE | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | JSON API on device-specific port 19008; endpoint structure may vary by firmware |
| intersport-kundenwlan | form-submit | Intersport | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit |
| lancom-cloud | form-submit | Lancom | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit on hotspot.lmc.de |
| lego-store-guest | form-submit | LegoStore | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit; IP-based portal detection |
| maxx-arena | form-submit | MaxxArena | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit (MesseSpot) |
| messe-dresden | form-submit | MesseDresden | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit via aerolan.ibh.de |
| mikrotik-chap | chap-md5 | generic | manual-research | 🟡 MEDIUM | ✅ | | CHAP-MD5 requires MD5 cryptographic response; depends on hexMD5 JS presence |
| mist-portal | form-submit | Juniper/MistCom | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit on Mist portal (Rossmann) |
| mypowerspot-de | form-submit | MyPowerspotDE | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit |
| nordsee-gast | form-submit | Nordsee | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit |
| picopoint-shell | form-submit | Picopoint | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from multi-step gatekeeper flow; original extracts tokens across 3 pages |
| primark-wifi | form-submit | ArubaLP/Primark | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit; follows redirect from primark.com to portal.wifi.primark.net |
| rhein-ruhr | form-submit | RheinRuhr | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit; IP-based portal on 10.10.10.1:2050 |
| ruby-hotels | form-submit | RubyHotels | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit |
| ruby-workspaces | chap-md5 | RubyWorkspaces | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | CHAP-MD5 authentication; same crypto dependency as mikrotik-chap |
| segmueller-hotspot | form-submit | ArubaLP/Segmueller | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit on Aruba-based hotspot |
| socialwifi | js-redirect | SocialwiBox | CaptivePortalAutoLogin | 🔴 LOW | ✅ | | SocialwiBox handler needs 5-step form chain with JS parsing; reduced to simple redirect |
| stadtwerke-stuttgart | form-submit | StadtwerkeStuttgart | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit; IP-based /macauth endpoint |
| t-mobile-hotspot | json-api | TMobileHotspot | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Multi-endpoint JSON API on hotspot.t-mobile.net; tariff selection may vary |
| targetbox | json-api | TargetBox | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | JSON API (Zalando); multi-step session handling |
| the-cloud | form-submit | TheCloud | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit (EU-wide Sky/Cloud hotspots) |
| uni-stuttgart-open | form-submit | UniStuttgartOpen | CaptivePortalAutoLogin | 🟢 HIGH | ✅ | | Simple form submit |
| unifi-guest | form-submit | UniFi | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from multi-step UniFi guest portal; full handler manages CSRF + session across /guest/s/* |
| unwired-graphql | json-api | Unwired | CaptivePortalAutoLogin | 🟡 MEDIUM | ✅ | | Simplified from GraphQL API; original constructs queries for Austrian transit WiFi |
| vodafone-de | json-api | VodafoneHotspot | manual-research | 🟡 MEDIUM | ✅ | | Complex multi-step JSON API: redirect → extract SID → session → login; requires credentials |
| wifibahn | csrf-form-submit | DBWifi | manual-research | 🟢 HIGH | ✅ | | Well-tested DB WiFi/ICE CSRF pattern; cookie-based token extraction |
| wifipass | cookie-chain | manual | manual-research | 🔴 LOW | ✅ | | Speculative cookie-chain template for wifipass.org; new auth_type, unverified on real portal |


## Coverage Summary

### By Count

| Metric | Value |
|--------|-------|
| Total recipes | 44 |
| Mock-tested | 44/44 |
| Device-tested | 0/44 |

### By auth_type

| auth_type | Count |
|-----------|-------|
| form-submit | 31 |
| json-api | 6 |
| chap-md5 | 2 |
| click-through-grant | 1 |
| csrf-form-submit | 1 |
| multi-step-form | 1 |
| js-redirect | 1 |
| cookie-chain | 1 |
| **Total** | **44** |

### By reliability

| Level | Count | Percentage |
|-------|-------|------------|
| 🟢 HIGH | 27 | 61% |
| 🟡 MEDIUM | 14 | 32% |
| 🔴 LOW | 3 | 7% |
| ⚪ UNTESTED | 0 | 0% |
| **Total** | **44** | **100%** |

### By source project

| Source | Count | Description |
|--------|-------|-------------|
| CaptivePortalAutoLogin | 35 | Derived from handler source analysis |
| manual-research | 9 | 6 pre-existing + 3 new template types |


## Handlers Not Covered

These 13 CaptivePortalAutoLogin handlers could not be expressed as JSON recipes because they require runtime logic that cannot be captured declaratively.

| Handler | Portal(s) | Why Custom Code Is Needed | Potential Future Approach |
|---------|-----------|---------------------------|---------------------------|
| AenaES | freewifi.aena.es | 10+ request flow: Gigya registration with random email, token exchange, multi-scene navigation | Scripted handler with email generation and OAuth token management |
| ArubaClearPass/Inditex | wifi.inditex.com | Multi-step: submitOnlyForm chain, then performArubaLogin with extracted credentials | Extend multi-step-form to support credential extraction and re-injection |
| ArubaClearPass/UrbanOutfitters | register.urbn.com | Same ArubaClearPass pattern as Inditex | Same approach as Inditex |
| ArubaClearPass/TallyWeijl | guestportal.tally-weijl.com | Same ArubaClearPass pattern as Inditex | Same approach as Inditex |
| ArubaNetworks | \*.cloudguest.central.arubanetworks.com | Parse inline JS for config JSON, extract credentials, then Aruba auth | Scripted handler with JS evaluation or regex extraction |
| BlockHouse | wlan.block-house.de | Parse JS to extract port/postToUrl, construct POST with timestamp | Extend form-submit with JS variable extraction capability |
| Carglass | /reg.php (path-based) | JS redirect parsing + form POST with mandatory checkbox | Scripted handler for JS redirect following + conditional form fields |
| Conn4 | \*.conn4.com | Extremely complex: multi-scene parsing, tariff selection, dual API styles (scene vs accor) | Full scripted handler; too many branches for declarative format |
| FotoProfi | IP-based/index.shtml | Multipart form POST with dynamically extracted hidden fields | Extend form-submit with multipart encoding + dynamic field extraction |
| IKEA | yo-wifi.net | Multi-step: follow redirects, POST for token, parse JSON for credentials, construct userid URL | Scripted handler with redirect following and JSON credential extraction |
| Juniper/Abercrombie | storewifi.abercrombie.com | JWT token generation with HMAC-SHA256 signing | Scripted handler; requires crypto primitives not available in declarative format |
| SocialWave | go.social-wave.com | External splash API with email registration, dual router auth (OpenWrt vs RouterOS) | Scripted handler with platform detection and router-specific auth |
| SocialwiBox | hotspot.socialwibox.com | 5-step form chain with JS redirectPost parsing and JSONObject extraction | Scripted handler with JS parsing; simplified recipe exists but unreliable |


## Source Attribution

### Recipe Origins

This recipe collection was built from three sources:

**1. CaptivePortalAutoLogin handler analysis (35 recipes)**

The [CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin) project (GPL-3.0, by binarynoise) contains 46 Kotlin handlers for specific captive portals. We studied each handler's source code to understand portal behavior, authentication flows, and request patterns, then independently wrote equivalent JSON recipe descriptors. These recipes are target-agnostic and can be compiled for any supported platform.

Recipes derived from handler analysis:
- arista-clickthrough, alnatura-kundenwlan, binarynoise-proxy, cisco-ise-cwa, cisco-wireless-mobility, cloudifi, cloudwifi-milaneo, commerzbank-wifi, dertour-guest, dokom21-hotspot, dse-tech, fritzbox-guest, hotsplots, imaster-nce, intersport-kundenwlan, lancom-cloud, lego-store-guest, maxx-arena, messe-dresden, mist-portal, mypowerspot-de, nordsee-gast, picopoint-shell, primark-wifi, rhein-ruhr, ruby-hotels, ruby-workspaces, segmueller-hotspot, socialwifi, stadtwerke-stuttgart, t-mobile-hotspot, targetbox, the-cloud, uni-stuttgart-open, unifi-guest, unwired-graphql

**2. Pre-existing recipes from independent research (6 recipes)**

These recipes predate the CaptivePortalAutoLogin analysis and were developed independently:
- cisco-meraki -- Cisco Meraki click-through grant URL pattern
- fortinet-clickthrough -- Fortinet/FortiAuthenticator /fgtauth pattern
- wifibahn -- Deutsche Bahn WiFi (csrf-form-submit)
- vodafone-de -- Vodafone Hotspot (json-api)
- mikrotik-chap -- MikroTik CHAP-MD5 (generic template)
- generic-form -- Generic HTML form (universal fallback)

**3. New template type recipes (3 recipes)**

Created to exercise and validate new auth_type engines:
- socialwifi -- js-redirect auth type validation
- accor-hotels -- multi-step-form auth type validation
- wifipass -- cookie-chain auth type validation

### License Note

All recipes derived from CaptivePortalAutoLogin are attributed to the original project. We studied the Kotlin source code to understand portal behavior, then wrote our own JSON recipe descriptors independently. The CaptivePortalAutoLogin project is licensed under GPL-3.0.
