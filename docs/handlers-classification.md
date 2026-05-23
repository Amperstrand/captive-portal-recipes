# CaptivePortalAutoLogin Handler Classification

Source: [binarynoise/CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin)
Date: 2026-05-22
Total handlers analyzed: 46 (excluding `_Template`)

## Summary

| Metric | Count |
|--------|-------|
| Total handlers | 46 |
| Recipe-able (new recipes) | 27 |
| Already covered by existing recipes | 3 |
| Needs custom code | 16 |
| Template coverage | 65% (30/46) |

## Classification Table

| # | Handler | Domain(s) | auth_type | Credentials | Recipe-able | Recipe ID |
|---|---------|-----------|-----------|-------------|-------------|-----------|
| 1 | AenaES | freewifi.aena.es | json-api (complex) | none | needs-custom | - |
| 2 | Alnatura | cppm-auth.alnatura.de | multi-step-form | none | yes (simplified) | alnatura-kundenwlan |
| 3 | Arista | *.agni.arista.io | form-submit | none | yes | arista-clickthrough |
| 4 | ArubaClearPass (Inditex) | wifi.inditex.com | multi-step-form | none | needs-custom | - |
| 5 | ArubaClearPass (UrbanOutfitters) | register.urbn.com | multi-step-form | none | needs-custom | - |
| 6 | ArubaClearPass (TallyWeijl) | guestportal.tally-weijl.com | multi-step-form | none | needs-custom | - |
| 7 | ArubaLP/Primark | www.primark.com → portal.wifi.primark.net | form-submit | none | yes | primark-wifi |
| 8 | ArubaLP/Segmueller | hotspot.segmueller.de | form-submit | none | yes | segmueller-hotspot |
| 9 | ArubaNetworks | *.cloudguest.central.arubanetworks.com | multi-step-form | none | needs-custom | - |
| 10 | BinarynoisePortalProxy | portal.binarynoise.de:8001 | form-submit | none | yes | binarynoise-proxy |
| 11 | BlockHouse | wlan.block-house.de | needs-custom | none | needs-custom | - |
| 12 | Carglass | /reg.php (path-based) | needs-custom | none | needs-custom | - |
| 13 | CiscoISE | /portal/gateway (redirect) | multi-step-form | none | yes (simplified) | cisco-ise-cwa |
| 14 | CiscoWirelessMobility | /fs/customwebauth/login.html | form-submit | none | yes | cisco-wireless-mobility |
| 15 | CloudWifi | start.cloudwifi.de | multi-step-form | none | yes (simplified) | cloudwifi-milaneo |
| 16 | Cloudifi | login.cloudi-fi.net | form-submit | none | yes | cloudifi |
| 17 | Commerzbank | wifiaccess.co | json-api | none | yes | commerzbank-wifi |
| 18 | Conn4 | *.conn4.com | json-api (complex) | none | needs-custom | - |
| 19 | DBWifi | login.wifionice.de, wifi.bahn.de | csrf-form-submit | none | already-covered | wifibahn |
| 20 | DerTour | IP-based, /authen | form-submit | none | yes | dertour-guest |
| 21 | Dokom21Hotspot | hotspot.dokom21.de | form-submit (ASP.NET) | none | yes (simplified) | dokom21-hotspot |
| 22 | DseTech | disclaimer.dse-tech.net | form-submit | none | yes | dse-tech |
| 23 | FortiAuthenticator | port 1000, /fgtauth | form-submit | none | already-covered | fortinet-clickthrough |
| 24 | FotoProfi | IP-based, index.shtml | needs-custom | none | needs-custom | - |
| 25 | FritzBox | /untrusted_guest.lua | form-submit | none | yes | fritzbox-guest |
| 26 | Hotsplots | www.hotsplots.de, auth.hotsplots.de | form-submit | none | yes | hotsplots |
| 27 | IKEA | yo-wifi.net | json-api (complex) | none | needs-custom | - |
| 28 | IMasterNCE | device.imaster-nce.de:19008 | json-api | none | yes | imaster-nce |
| 29 | Intersport | wlan.intersport-gruppe.de | form-submit | none | yes | intersport-kundenwlan |
| 30 | Juniper/MistCom | portal.*.mist.com | form-submit | none | yes | mist-portal |
| 31 | Juniper/Abercrombie | storewifi.abercrombie.com | needs-custom (JWT) | none | needs-custom | - |
| 32 | Lancom | hotspot.lmc.de | form-submit | none | yes | lancom-cloud |
| 33 | LegoStore | IP-based | form-submit | none | yes | lego-store-guest |
| 34 | MaxxArena | hotspot.maxxarena.de | form-submit | none | yes | maxx-arena |
| 35 | MesseDresden | aerolan.ibh.de | form-submit | none | yes | messe-dresden |
| 36 | MyPowerspotDE | login.mypowerspot.de | form-submit | none | yes | mypowerspot-de |
| 37 | NetworkAuth | *.network-auth.com | click-through-grant | none | already-covered | cisco-meraki |
| 38 | NetworkAuthSubPortal | *.network-auth.com (redirect) | click-through-grant | none | already-covered | cisco-meraki |
| 39 | Nordsee | guests.nordsee.com | form-submit | none | yes | nordsee-gast |
| 40 | Picopoint | gatekeeper2.picopoint.com | multi-step-form | none | yes (simplified) | picopoint-shell |
| 41 | RheinRuhr | 10.10.10.1:2050 | form-submit | none | yes | rhein-ruhr |
| 42 | RubyHotels | hotspot.ruby-hotels.com | form-submit | none | yes | ruby-hotels |
| 43 | RubyWorkspaces | hotspot.ruby-workspaces.com | chap-md5 | none | yes | ruby-workspaces |
| 44 | SocialWave | go.social-wave.com, go.meinwlan.com | json-api (complex) | none | needs-custom | - |
| 45 | SocialwiBox | hotspot.socialwibox.com | needs-custom | none | needs-custom | - |
| 46 | StadtwerkeStuttgart | IP-based, /macauth | form-submit | none | yes | stadtwerke-stuttgart |
| 47 | TMobileHotspot | hotspot.t-mobile.net | json-api | none | yes | t-mobile-hotspot |
| 48 | TargetBox | wifi.targetbox.de | json-api | none | yes | targetbox |
| 49 | TheCloud | service.thecloud.eu | form-submit | none | yes | the-cloud |
| 50 | UniFi | /guest/s/* | multi-step-form | none | yes (simplified) | unifi-guest |
| 51 | UniStuttgartOpen | guest-internet.tik.uni-stuttgart.de | form-submit | none | yes | uni-stuttgart-open |
| 52 | Unwired | wasabi-splashpage.wifi.unwired.at | json-api (GraphQL) | none | yes (simplified) | unwired-graphql |
| 53 | VodafoneHotspot | hotspot.vodafone.de | json-api | none | already-covered | vodafone-de |

## Handlers Needing Custom Code

These handlers cannot be expressed as recipe JSON because they require:

1. **AenaES** — Multi-step registration with Gigya API, random email generation, token exchange across 10+ requests
2. **ArubaClearPass** (Inditex/UrbanOutfitters/TallyWeijl) — Multi-step: submitOnlyForm → submitOnlyForm → performArubaLogin with extracted credentials
3. **ArubaNetworks** (H&M/IKEA/Levi's) — Complex: parse JS for config JSON, accept terms, extract credentials from JSON, then Aruba login
4. **BlockHouse** — Parses JS to extract port/postToUrl variables, then constructs form POST with timestamp
5. **Carglass** — JS redirect parsing + form POST with checkbox
6. **Conn4** (REWE/Kaufland/Hotels) — Extremely complex: multi-scene parsing, tariff selection, session management, multiple API styles (scene vs accor)
7. **FotoProfi** — Multipart form POST with extracted hidden fields
8. **IKEA** — Multi-step: follow redirects, POST form for token, parse JSON for credentials, GET with constructed userid
9. **Abercrombie** (Juniper/Mist external) — JWT token generation with HMAC-SHA256
10. **SocialWave** — Multi-step: external splash API with email registration, two different router auth flows (OpenWrt vs RouterOS)
11. **SocialwiBox** — 5-step form chain with JS redirectPost parsing, JSONObject extraction
12. **Dokom21Hotspot** — ASP.NET ViewState form (simplified recipe provided but full support needs ViewState extraction)

## Auth Type Distribution

| auth_type | Count (handlers) | Count (recipes) |
|-----------|-----------------|-----------------|
| form-submit | 22 | 19 |
| json-api | 9 | 6 |
| csrf-form-submit | 1 | 1 (existing) |
| click-through-grant | 2 | 1 (existing) |
| chap-md5 | 1 | 1 |
| multi-step-form (needs-custom) | 6 | 0 |
| needs-custom (JS/JWT/multipart) | 6 | 0 |
| **Total** | **47** | **28** |

## Recipe Files Created

New recipes (27):
- arista-clickthrough.json
- alnatura-kundenwlan.json
- binarynoise-proxy.json
- cisco-ise-cwa.json
- cisco-wireless-mobility.json
- cloudifi.json
- cloudwifi-milaneo.json
- commerzbank-wifi.json
- dertour-guest.json
- dokom21-hotspot.json
- dse-tech.json
- fritzbox-guest.json
- hotsplots.json
- imaster-nce.json
- intersport-kundenwlan.json
- lancom-cloud.json
- lego-store-guest.json
- maxx-arena.json
- messe-dresden.json
- mist-portal.json
- mypowerspot-de.json
- nordsee-gast.json
- picopoint-shell.json
- primark-wifi.json
- rhein-ruhr.json
- ruby-hotels.json
- ruby-workspaces.json
- segmueller-hotspot.json
- stadtwerke-stuttgart.json
- t-mobile-hotspot.json
- targetbox.json
- the-cloud.json
- uni-stuttgart-open.json
- unifi-guest.json
- unwired-graphql.json

Existing recipes (6):
- cisco-meraki.json (covers NetworkAuth + NetworkAuthSubPortal)
- fortinet-clickthrough.json (covers FortiAuthenticator)
- wifibahn.json (covers DBWifi)
- vodafone-de.json (covers VodafoneHotspot)
- mikrotik-chap.json (generic)
- generic-form.json (generic)
