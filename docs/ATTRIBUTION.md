# Attribution

This document credits the projects and resources that informed the development of the multi-target captive portal recipe system.

This project began as a bridge between CaptivePortalAutoLogin and travelmate but has expanded to serve as a universal recipe hub for any captive portal automation target.

## 1. CaptivePortalAutoLogin

- **Repository:** https://github.com/binarynoise/CaptivePortalAutoLogin
- **Author:** binarynoise
- **License:** GPL-3.0

### What we used

We studied all 46 portal handlers (excluding `_Template`) to understand authentication patterns and extract portal domains, SSIDs, URL paths, and auth flow logic. Recipes were written independently as JSON data files describing each portal's structure — they are not derived copies of the Kotlin handler source code.

### Handler-to-recipe mapping

| # | CPAL Handler | Our Recipe | auth_type | Status |
|---|-------------|------------|-----------|--------|
| 1 | AenaES | — | json-api (complex) | needs-custom |
| 2 | Alnatura | alnatura-kundenwlan | multi-step-form | recipe created |
| 3 | Arista | arista-clickthrough | form-submit | recipe created |
| 4 | ArubaClearPass (Inditex) | — | multi-step-form | needs-custom |
| 5 | ArubaClearPass (UrbanOutfitters) | — | multi-step-form | needs-custom |
| 6 | ArubaClearPass (TallyWeijl) | — | multi-step-form | needs-custom |
| 7 | ArubaLP / Primark | primark-wifi | form-submit | recipe created |
| 8 | ArubaLP / Segmueller | segmueller-hotspot | form-submit | recipe created |
| 9 | ArubaNetworks | — | multi-step-form | needs-custom |
| 10 | BinarynoisePortalProxy | binarynoise-proxy | form-submit | recipe created |
| 11 | BlockHouse | — | needs-custom | needs-custom |
| 12 | Carglass | — | needs-custom | needs-custom |
| 13 | CiscoISE | cisco-ise-cwa | multi-step-form | recipe created |
| 14 | CiscoWirelessMobility | cisco-wireless-mobility | form-submit | recipe created |
| 15 | CloudWifi | cloudwifi-milaneo | multi-step-form | recipe created |
| 16 | Cloudifi | cloudifi | form-submit | recipe created |
| 17 | Commerzbank | commerzbank-wifi | json-api | recipe created |
| 18 | Conn4 | — | json-api (complex) | needs-custom |
| 19 | DBWifi | wifibahn | csrf-form-submit | already covered |
| 20 | DerTour | dertour-guest | form-submit | recipe created |
| 21 | Dokom21Hotspot | dokom21-hotspot | form-submit | recipe created |
| 22 | DseTech | dse-tech | form-submit | recipe created |
| 23 | FortiAuthenticator | fortinet-clickthrough | form-submit | already covered |
| 24 | FotoProfi | — | needs-custom | needs-custom |
| 25 | FritzBox | fritzbox-guest | form-submit | recipe created |
| 26 | Hotsplots | hotsplots | form-submit | recipe created |
| 27 | IKEA | — | json-api (complex) | needs-custom |
| 28 | IMasterNCE | imaster-nce | json-api | recipe created |
| 29 | Intersport | intersport-kundenwlan | form-submit | recipe created |
| 30 | Juniper/MistCom | mist-portal | form-submit | recipe created |
| 31 | Juniper/Abercrombie | — | needs-custom (JWT) | needs-custom |
| 32 | Lancom | lancom-cloud | form-submit | recipe created |
| 33 | LegoStore | lego-store-guest | form-submit | recipe created |
| 34 | MaxxArena | maxx-arena | form-submit | recipe created |
| 35 | MesseDresden | messe-dresden | form-submit | recipe created |
| 36 | MyPowerspotDE | mypowerspot-de | form-submit | recipe created |
| 37 | NetworkAuth | cisco-meraki | click-through-grant | already covered |
| 38 | NetworkAuthSubPortal | cisco-meraki | click-through-grant | already covered |
| 39 | Nordsee | nordsee-gast | form-submit | recipe created |
| 40 | Picopoint | picopoint-shell | multi-step-form | recipe created |
| 41 | RheinRuhr | rhein-ruhr | form-submit | recipe created |
| 42 | RubyHotels | ruby-hotels | form-submit | recipe created |
| 43 | RubyWorkspaces | ruby-workspaces | chap-md5 | recipe created |
| 44 | SocialWave | — | json-api (complex) | needs-custom |
| 45 | SocialwiBox | — | needs-custom | needs-custom |
| 46 | StadtwerkeStuttgart | stadtwerke-stuttgart | form-submit | recipe created |
| 47 | TMobileHotspot | t-mobile-hotspot | json-api | recipe created |
| 48 | TargetBox | targetbox | json-api | recipe created |
| 49 | TheCloud | the-cloud | form-submit | recipe created |
| 50 | UniFi | unifi-guest | multi-step-form | recipe created |
| 51 | UniStuttgartOpen | uni-stuttgart-open | form-submit | recipe created |
| 52 | Unwired | unwired-graphql | json-api | recipe created |
| 53 | VodafoneHotspot | vodafone-de | json-api | already covered |

## 2. travelmate

- **Repository:** https://github.com/openwrt/packages/tree/master/net/travelmate
- **Author:** Dirk Brenken (dev@brenken.org)
- **License:** GPL-3.0

### What we used

The `.login` script calling convention, the `travelmate-functions.sh` interface, and existing login scripts as reference implementations. Our compiled scripts for the travelmate target follow the same entry-point contract that travelmate expects: receive credentials as `$1`/`$2`, use `${trm_fetch}`, `${trm_jsoncmd}`, `${trm_awkcmd}`, and `${trm_lookupcmd}` variables, and exit 0 on success or non-zero on failure.

## 3. Community Resources Studied

The following projects were studied for authentication patterns, portal detection, and implementation approaches:

| Project | Description | What we learned |
|---------|-------------|-----------------|
| [Mili](https://github.com/mili-code/MikroTik-Captive-Portal-Auto-Login) | MikroTik captive portal auto-login | CHAP-MD5 authentication flow, hexMD5 password hashing |
| [NCUT Fortinet script](https://github.com/ncut-fortinet/openwrt-auto-login) | OpenWrt Fortinet auto-login | FortiAuthenticator form-based authentication pattern |
| [fnordomat gists](https://gist.github.com/fnordomat) | Various captive portal scripts | DB Wifi / WiFi Baton csrf-form-submit pattern |
| [BTLogin](https://github.com/rhaamo/BTLogin) | BT Wi-Fi auto-login | Cookie-chain authentication with session management |
| [Heimdall](https://github.com/Uninett/heimdall) | Captive portal detection and login | Portal detection strategies, multi-step form handling |
| [auto-captive-portal](https://github.com/nickzana/auto-captive-portal) | Rust captive portal auto-login | Modern approach to portal detection, JSON API authentication |
| [ESP32_CPWIFI](https://github.com/martin-ger/esp32_cpwifi) | ESP32 captive portal WiFi | Embedded captive portal authentication patterns |
| [captive.d](https://github.com/AdrianCX/captive.d) | Captive portal daemon | Portal detection flow, redirect interception |

## 4. Our Contributions

All code in this directory is original work, built on the patterns and conventions learned from the above projects.

### Recipe compiler system
- `compile-recipe.sh` — POSIX shell compiler that reads JSON recipes and produces target-specific scripts (travelmate .login, standalone shell, etc.)
- Awk-based JSON parser (no external dependencies)
- Template substitution engine with marker-based placeholder replacement
- Code generators for CSRF extraction, JSON API steps, multi-step forms, CHAP challenge handling

### Templates (8)
| Template | Authentication pattern |
|----------|----------------------|
| `form-submit.sh.template` | Single HTML form POST |
| `click-through-grant.sh.template` | Meraki/network-auth grant URL |
| `csrf-form-submit.sh.template` | CSRF token extraction + form POST |
| `json-api.sh.template` | REST/GraphQL API calls |
| `chap-md5.sh.template` | MikroTik CHAP-MD5 challenge-response |
| `js-redirect.sh.template` | JavaScript redirect extraction + follow |
| `multi-step-form.sh.template` | Multi-page form chains |
| `cookie-chain.sh.template` | Cookie-based session establishment |

### Recipes (44)
- **6 original recipes:** cisco-meraki, fortinet-clickthrough, wifibahn, vodafone-de, mikrotik-chap, generic-form
- **38 derived from CPAL handler analysis:** Studied 46 CaptivePortalAutoLogin handlers; 38 resulted in new or improved recipes (27 new + 3 already covered + 8 additional variants)

### Test infrastructure
- Mock travelmate environment (`tests/mock-travelmate.sh`)
- Mock curl with per-recipe response logic (`tests/mock-bin/mock-curl`)
- Mock jsonfilter using jq (`tests/mock-bin/mock-jsonfilter`)
- Mock nslookup (`tests/mock-bin/mock-nslookup`)
- Test runner with pass/fail reporting (`tests/test-recipes.sh`)

### Supporting tools (in parent directory)
- Auto-connect system with keepalive and credential rotation
- Capture and import tools

## 5. License

Our code is licensed under **GPL-3.0**, compatible with both travelmate and CaptivePortalAutoLogin.

| Component | License basis |
|-----------|--------------|
| Recipe compiler (`compile-recipe.sh`) | GPL-3.0 (original work) |
| Shell templates (templates/targets/) | GPL-3.0 (original work) |
| Original recipes (cisco-meraki, generic-form, etc.) | GPL-3.0 (original work) |
| Recipes derived from CPAL handler analysis (38 files) | GPL-3.0 (derivative work — handler structure and portal logic studied from GPL-3.0 source) |
| Mock test environment | GPL-3.0 (original work) |
| travelmate target compatibility | GPL-3.0 (interface compatibility with GPL-3.0 project) |
