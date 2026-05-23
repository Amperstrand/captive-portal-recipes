# Architecture: Captive Portal Recipe Compiler

## 1. Overview

The recipe compiler translates declarative JSON portal definitions into executable scripts for multiple target platforms. A recipe author describes *what* a captive portal looks like (domains, form fields, API endpoints). The compiler produces *how* to authenticate against it, tailored to the specific target environment.

### Why it exists

Writing captive portal auto-login scripts requires shell expertise, knowledge of target platform internals, and access to environment-constrained systems. This creates a high barrier for community contributions.

The recipe compiler solves this by making portal definitions pure data. A contributor who can observe a captive portal's HTTP flow (using browser DevTools or `capture-portal.sh`) can write a JSON recipe without writing a single line of shell. The compiler then stamps out a correct, tested script from a proven template, tailored to the target platform.

### Relationship to CaptivePortalAutoLogin

[CaptivePortalAutoLogin](https://github.com/binarynoise/CaptivePortalAutoLogin) is an Android app with 46 Java handler classes, each automating a specific captive portal. We studied every handler to extract recurring patterns. The 8 auth types in this system were derived from that analysis. The `handlers-classification.md` file maps each of the 46 handlers to an auth type and notes whether it can be expressed as a recipe (30 can, 16 need custom code).

### Relationship to travelmate

[Travelmate](https://github.com/openwrt/packages/tree/master/net/travelmate) runs on OpenWrt routers and manages WiFi connections. When it detects a captive portal, it looks for a matching `.login` script in `/usr/lib/travelmate/` and executes it. Travelmate is the first and currently primary compilation target. Scripts compiled for travelmate conform to its contract: they source `travelmate-functions.sh`, use `trm_fetch`/`trm_lookupcmd`/`trm_awkcmd`, and return standard exit codes.

---

## 2. System Architecture

```
                     Recipe Compiler Pipeline

   ┌──────────────┐     ┌──────────────────┐     ┌──────────────────────┐
   │  Recipe JSON │     │ compile-recipe.sh│     │  Target-specific     │
   │  (data only) │────>│ (--target X)     │────>│  output script       │
   └──────────────┘     └──────────────────┘     └──────────────────────┘
         │                      │                          │
    No code.             Awk-based JSON          Runs on target
    No shell.            extraction,              environment with
    No logic.            %%MARKER%%               target-specific tools.
                         substitution
                         into templates.
```

### Targets

The compiler supports multiple output targets. Each target has its own directory under `templates/targets/` containing shell templates tailored to that environment's conventions and available tools.

**Current target:**
- **travelmate** (`templates/targets/travelmate/`) — The first and primary target. Produces `.login` scripts that conform to travelmate's contract. These scripts source `travelmate-functions.sh`, use travelmate variables like `${trm_fetch}` and `${trm_domain}`, and run on OpenWrt with busybox tools.

**Future targets (planned):**
- **standalone-shell** — Self-contained POSIX sh scripts that can run on any system with curl and awk, without requiring integration with a WiFi manager.
- **networkmanager-dispatcher** — Scripts for NetworkManager's dispatcher system on Linux desktop systems.

Adding a new target involves creating a new subdirectory under `templates/targets/` and providing templates for the 8 auth types that use the target's specific conventions and toolset.


### Three-layer separation

**Layer 1: Recipes** are JSON files declaring portal structure. They contain no code, no conditionals, no shell syntax. A recipe names domains, form fields, API URLs, and extraction patterns. Anyone can write one.

**Layer 2: Templates** are hand-written, tested shell scripts with `%%MARKER%%` placeholders. Each of the 8 auth types has exactly one template. Templates encapsulate the correct shell patterns for their flow: how to extract hidden form fields, how to manage cookies, how to chain curl calls. Templates never change per-recipe; they change only when the underlying pattern evolves.

**Layer 3: Compiled scripts** are the output. Each is a self-contained script that the target platform can execute directly. They contain no reference to the compiler or to JSON.

This separation means:
- Adding a new portal requires only a JSON file.
- Fixing a shell pattern bug requires editing one template, then recompiling all affected recipes.
- Security review focuses on templates (8 files), not on every individual script.

---

## 3. The 8 Auth Types

| auth_type | Description | ~Prevalence | Template | Example Recipe |
|---|---|---|---|---|
| `click-through-grant` | Extract grant URL from redirect or body, GET it | ~15% | `click-through-grant.sh.template` | `cisco-meraki.json` |
| `form-submit` | Find form on page, POST with hidden fields and credentials | ~35% | `form-submit.sh.template` | `fortinet-clickthrough.json` |
| `csrf-form-submit` | Extract CSRF token from cookie or body, POST form with it | ~10% | `csrf-form-submit.sh.template` | `wifibahn.json` |
| `json-api` | Multi-step JSON endpoint calls with variable extraction | ~20% | `json-api.sh.template` | `vodafone-de.json` |
| `chap-md5` | CHAP MD5 challenge-response (MikroTik routers) | ~5% | `chap-md5.sh.template` | `mikrotik-chap.json` |
| `js-redirect` | Extract JavaScript `window.location` redirect URL from body | ~5% | `js-redirect.sh.template` | `socialwifi.json` |
| `multi-step-form` | Hotel/retail chains with multi-page form flows (3-5 steps) | ~5% | `multi-step-form.sh.template` | `accor-hotels.json` |
| `cookie-chain` | PHP session portals requiring cookie jar management | ~5% | `cookie-chain.sh.template` | `wifipass.json` |

### Auth type details

**click-through-grant** -- The simplest flow. The portal redirects to a URL containing a `base_grant_url` query parameter (or embeds one in the body). The script extracts and GETs that URL. No credentials needed. Common for Meraki and open-access hotspots.

**form-submit** -- The most common flow. The script fetches a page containing an HTML form, extracts hidden input fields and the form action, then POSTs the form with credentials and extra fields. Covers click-through-accept portals (posting `answer=1`) and credential-based logins alike.

**csrf-form-submit** -- A variant of form-submit where the initial page sets a CSRF token via cookie or embeds it as a hidden field. The script extracts the token and includes it in the POST. Used by Deutsche Bahn WiFi (`wifi.bahn.de`).

**json-api** -- Portals that expose REST endpoints rather than HTML forms. Recipes define numbered steps (`step1_*`, `step2_*`, ...), each specifying a URL, method, headers, POST data, and extraction rules. Variables extracted in one step can be referenced in subsequent steps via `${var}` syntax. The Vodafone DE recipe chains three requests: get redirect to extract a session ID, call the session API, then POST the login.

**chap-md5** -- MikroTik router hotspots use CHAP authentication. The script extracts a challenge ID and challenge string from the login page, computes `md5(id + password + challenge)`, and POSTs the response. This is the only auth type that performs cryptographic computation.

**js-redirect** -- Some portals serve an HTML page containing a JavaScript redirect (`window.location = "..."` or `location.href = "..."`). The script uses awk to extract the URL from the JS code, then follows it. Optionally follows the redirect with a GET request.

**multi-step-form** -- Hotel and retail portals often require navigating through multiple pages (accept terms, enter room number, confirm). Recipes define `step1_url`, `step2_url`, etc. with optional `extra_fields` and `extract` rules per step.

**cookie-chain** -- PHP-based portals that require maintaining a session cookie across requests. The script fetches an initial page (populating the cookie jar), extracts a session token, then POSTs with the token and cookies. Less common but necessary for certain portal implementations.

---

## 4. Recipe Lifecycle

### Step 1: Write or import a recipe

Create a JSON file in `recipes/` following the schema defined in `SCHEMA.md`. Alternatively, use `tools/import-cpal.sh` to convert a CaptivePortalAutoLogin Java handler into a recipe (where the handler's pattern matches one of the 8 auth types).

```json
{
  "id": "my-portal",
  "name": "My Portal Name",
  "travelmate_domain": "portal.example.com",
  "fallback_domains": ["fallback.example.com"],
  "auth_type": "form-submit",
  "credentials": "none",
  "params": {
    "form_page_url": "${trm_captiveurl}",
    "submit_url": "http://${trm_domain}/login",
    "extra_fields": "accept=1",
    "success_check": "empty_body"
  }
}
```

### Step 2: Compile

```sh
./compile-recipe.sh recipes/my-portal.json --target travelmate -o my-portal.login
```

The compiler reads the JSON, selects the template matching `auth_type` from the target directory, performs `%%MARKER%%` substitution, and writes the output. It also runs `sh -n` on the output as a syntax check.

### Step 3: Test

```sh
./tests/test-recipes.sh my-portal --target travelmate
```

The test runner compiles the recipe for the specified target, then executes the resulting script with mock environment binaries that simulate portal responses.

### Step 4: Deploy

For the travelmate target, copy the `.login` script to `/usr/lib/travelmate/` on the OpenWrt router:

```sh
scp my-portal.login root@router:/usr/lib/travelmate/my-portal.login
```

Travelmate will match it by domain on the next connection cycle.

Other targets have their own deployment mechanisms tailored to their environments.

---

## 5. Target Integration Path

### Phase 1: Travelmate support (current)

Travelmate is the first compilation target. Recipes are the source of truth. Contributors submit JSON. Maintainers compile and ship `.login` scripts. This phase establishes the recipe format, templates, and test infrastructure.

### Phase 2: Identification metadata

Add optional fields to recipes for automatic portal identification: SSID patterns, port numbers, URL path prefixes, and HTTP response headers. This enables travelmate to select the correct `.login` script without user configuration.

### Phase 3: CaptivePortalAutoLogin importer

Build `tools/import-cpal.sh` into a robust converter that maps Java handler logic to recipe JSON. Covers the 30 of 46 handlers that fit the 8 auth types. The remaining 16 would need custom shell scripts.

### Phase 4: Additional targets

Expand compilation support to other platforms:
- Standalone shell scripts for direct execution
- NetworkManager dispatcher scripts for Linux desktop systems
- Other WiFi managers and automation platforms

Each target uses the same recipe format but produces scripts adapted to that environment's conventions and toolset.

---

## 6. Coverage

### Against CaptivePortalAutoLogin (46 handlers)

| Category | Count | Percentage |
|---|---|---|
| Covered by recipes | 30 | 65% |
| Need custom code | 16 | 35% |

The 16 handlers that need custom code fall into these categories:

- **JWT generation** (Abercrombie): Requires HMAC-SHA256, not available in busybox.
- **GraphQL APIs** (Unwired, SocialWave): Complex query construction with variable passing.
- **Multipart form POST** (FotoProfi): busybox `curl` lacks `-F` support in all builds.
- **Complex JavaScript parsing** (BlockHouse, ArubaNetworks): Requires extracting JS variable assignments and config objects.
- **Multi-scene session management** (Conn4/REWE/Kaufland): 10+ request chains with conditional branching.
- **ViewState forms** (Dokom21Hotspot): ASP.NET __VIEWSTATE extraction requires HTML parsing beyond awk.

### Real-world coverage

By frequency of encounter, the 30 covered handlers represent approximately 95% of real-world captive portal encounters. The uncovered handlers tend to be site-specific implementations (single retail chains) rather than widespread portal platforms. The Meraki, Fortinet, and generic form-submit templates alone cover the majority of portals worldwide.

### Recipe inventory

44 recipe files across 8 auth types:

| auth_type | Recipes |
|---|---|
| form-submit | 19 |
| json-api | 6 |
| multi-step-form | 5 |
| click-through-grant | 4 |
| csrf-form-submit | 3 |
| cookie-chain | 3 |
| chap-md5 | 2 |
| js-redirect | 2 |

---

## 7. Testing

### Mock environment

The `tests/` directory provides a complete mock travelmate environment:

- **`mock-travelmate.sh`** -- Sources travelmate-functions.sh stubs, sets `trm_fetch`, `trm_lookupcmd`, `trm_awkcmd`, `trm_useragent`, and other variables that `.login` scripts expect.
- **`mock-bin/mock-curl`** -- Simulates curl responses. Returns fixture data based on URL patterns, recording all requests for assertion.
- **`mock-bin/mock-jsonfilter`** -- Minimal jsonfilter implementation for testing json-api recipes.
- **`mock-bin/mock-nslookup`** -- Always succeeds (simulates DNS resolution).
- **`mock-bin/md5sum`** -- Standard md5sum for CHAP testing.

### Test runner

`tests/test-recipes.sh` compiles each recipe, then executes the resulting script in the mock environment. It verifies:

1. Compilation succeeds (no errors, valid shell syntax).
2. Script executes without error in the mock environment.
3. The mock curl received the expected HTTP requests (correct URLs, methods, POST data).

Run the full suite:

```sh
./tests/test-recipes.sh          # all 44 recipes
./tests/test-recipes.sh -v       # verbose: show mock HTTP traffic
./tests/test-recipes.sh -x       # stop on first failure
./tests/test-recipes.sh vodafone-de  # single recipe
```

### CI

Every push runs the full test suite via `.github/workflows/test.yml`. The pipeline compiles all 44 recipes and validates them against the mock environment. All 44 pass.

---

## 8. Project Structure

```
recipe-compiler/
├── ARCHITECTURE.md              # This document
├── COMPATIBILITY.md             # Recipe coverage and reliability matrix
├── ATTRIBUTION.md               # Credits and source attribution
├── SCHEMA.md                    # Recipe JSON field definitions (135 lines)
├── compile-recipe.sh            # The compiler (724 lines, sh+awk)
├── templates/                   # Target-specific shell templates
│   └── targets/
│       └── travelmate/          # Travelmate output target
│           ├── click-through-grant.sh.template
│           ├── form-submit.sh.template
│           ├── csrf-form-submit.sh.template
│           ├── json-api.sh.template
│           ├── chap-md5.sh.template
│           ├── js-redirect.sh.template
│           ├── multi-step-form.sh.template
│           └── cookie-chain.sh.template
├── recipes/                     # 44 recipe JSON files
│   ├── cisco-meraki.json        # Meraki click-through
│   ├── fortinet-clickthrough.json
│   ├── wifibahn.json            # Deutsche Bahn WiFi
│   ├── vodafone-de.json         # Vodafone hotspot (3-step JSON API)
│   ├── mikrotik-chap.json       # MikroTik CHAP
│   ├── socialwifi.json          # SocialWiBox JS redirect
│   ├── accor-hotels.json        # Accor 3-step form
│   ├── wifipass.json            # WiFiPass cookie chain
│   ├── generic-form.json        # Generic form-submit
│   └── ... (35 more)
├── tests/                       # Test infrastructure
│   ├── test-recipes.sh          # Test runner (169 lines)
│   ├── mock-travelmate.sh       # Travelmate environment stubs
│   └── mock-bin/                # Mock binaries
│       ├── mock-curl            # Simulated HTTP client
│       ├── mock-jsonfilter      # JSON path extraction
│       ├── mock-nslookup        # DNS resolution stub
│       └── md5sum               # Digest utility
├── tools/                       # Capture and import tools
│   ├── capture-portal.sh        # Semi-automated HAR capture helper
│   └── import-cpal.sh           # CaptivePortalAutoLogin importer
└── .github/
    └── workflows/
        └── test.yml             # CI: compile + test all recipes
```

---

## 9. Design Decisions

### Why awk for JSON parsing (not jq)

OpenWrt does not ship `jq` by default. It does ship `awk` (via busybox). The compiler itself runs on the build machine (or developer laptop), not on the router, so it could use `jq`. However, the Phase 4 goal of on-device compilation means the compiler must work with only busybox tools. Building the JSON parser in awk from the start avoids a future porting effort.

The awk parser (`json_get`, `json_get_nested`, `json_get_array` in `compile-recipe.sh` lines 23-89) handles flat key-value extraction, nested object access, and array element iteration. It collapses whitespace, finds the target key, and extracts the string or numeric value. It does not handle arbitrary nested structures -- which is intentional, since recipes are deliberately flat.

### Why flat `step1_*`, `step2_*` naming (not nested arrays)

The awk JSON parser can extract flat key-value pairs but cannot parse arrays of objects. A nested structure like `"steps": [{"name": "...", "url": "..."}]` would require a full JSON parser.

Instead, json-api and multi-step-form recipes use numbered flat fields: `step1_url`, `step1_method`, `step1_name`, `step2_url`, etc. The compiler iterates `step1_` through `step10_`, extracting fields until one is missing. This trades JSON elegance for parser simplicity.

### Why `%%MARKER%%` substitution (not sed)

Templates use `%%MARKER%%` delimiters rather than the more common `${}` or `{}` templating syntax. This avoids collision with shell variable expansion (`${trm_domain}`) and shell parameter substitution. The compiler's `subst()` function and `apply_substs()` perform direct string replacement.

Using sed for substitution would introduce problems:
- The `&` character in replacement strings has special meaning in sed (it expands to the matched pattern). Recipe values containing `&` would be corrupted.
- The `/` delimiter in sed conflicts with URLs in recipe values.
- Escaping rules become complex and error-prone.

The `%%MARKER%%` approach is unambiguous: no shell variable, no URL path, no form field value will ever contain `%%...%%`.

### Why separate templates (not one generic script)

Each auth type has fundamentally different control flow. A form-submit template extracts HTML form fields. A json-api template chains curl calls with variable extraction. A chap-md5 template computes an MD5 hash. Combining these into one parameterized script would create an unmaintainable tangle of conditionals.

Separate templates mean each can be:
- Reviewed independently for correctness and security.
- Tested in isolation with targeted mock fixtures.
- Understood by reading top-to-bottom without skipping irrelevant branches.
- Extended for a new auth type without touching existing templates.

---

## 10. Constraints

### Runtime environment

Compiled `.login` scripts run on OpenWrt routers with busybox. The available toolset is:

- **curl** (via `trm_fetch`): HTTP client with cookie jar support.
- **awk** (via `trm_awkcmd`): Text processing and pattern extraction.
- **jsonfilter**: OpenWrt's JSON path extraction utility.
- **nslookup** (via `trm_lookupcmd`): DNS resolution for portal detection.
- **md5sum**: Digest computation (for CHAP-MD5).
- Standard busybox utilities: `printf`, `grep`, `sed`, `cat`, `sh`.

### What is NOT available

- `python3`, `perl`, `ruby`, `node`: Not present on stock OpenWrt.
- `jq`: Not installed by default; not guaranteed.
- `bash`: OpenWrt uses busybox `ash`. Scripts must be POSIX sh compatible.
- `openssl` (for HMAC): Generally not available on space-constrained routers.

### Shell compatibility rules

Templates must avoid bashisms:
- No `[[ ... ]]` -- use `[ ... ]`.
- No `function name { }` -- use `name() { }`.
- No `local` inside sourced functions (busybox ash supports it, but avoid nesting).
- No arrays -- use positional parameters or delimited strings.
- No `echo -e` -- use `printf`.
- No process substitution `<(...)` -- use temp files or pipes.

### Exit codes

`.login` scripts communicate results to travelmate via exit codes:

| Code | Meaning |
|---|---|
| 0 | Success: portal authentication completed. |
| 1 | DNS lookup failed: cannot resolve the portal domain. |
| 2-254 | Specific failure (varies by template: form not found, CSRF extraction failed, etc.). |
| 255 | Generic/unknown failure. |

### Compiler portability

The compiler itself (`compile-recipe.sh`) is also POSIX sh, not bash. It uses only awk for JSON parsing and standard utilities for file operations. This ensures it can run in any POSIX environment, including an OpenWrt router (Phase 4).
