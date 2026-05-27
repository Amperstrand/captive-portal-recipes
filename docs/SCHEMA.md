# Captive Portal Recipe Schema

A recipe is a JSON file that declares how to authenticate against a captive portal.
Recipes are compiled into target-specific scripts (travelmate .login, standalone shell, etc.) by `compile-recipe.sh`.

## Supported auth_type Values

| auth_type | Description | Credentials |
|-----------|-------------|-------------|
| `click-through-grant` | Extract grant URL from redirect, GET it | None |
| `form-submit` | Find form on page, POST it (with optional extra fields) | Optional username/password |
| `csrf-form-submit` | Extract CSRF token from cookies, POST form with it | Optional username/password |
| `json-api` | Call JSON endpoints (single or multi-step) | Optional username/password |
| `chap-md5` | CHAP MD5 challenge-response (MikroTik) | username + password |
| `js-redirect` | Extract JavaScript redirect URL from body, follow it | None |
| `multi-step-form` | Multi-page form flow (hotel/retail portals, 3-5 steps) | Optional username/password |
| `cookie-chain` | PHP session cookie chain: fetch page, extract cookie, POST with token | None |
| `js-parse` | Extract JS variables from HTML using POSIX ERE regex, then POST with extracted values | None |
| `multipart-post` | Multipart/form-data POST using `curl --form-string` | None |
| `multi-api` | Multi-step API calls with optional foreach loop for iteration | None |
| `jwt-sign` | HMAC-SHA256 JWT generation via openssl, then GET/POST with token | None |

## Recipe Fields

### Required

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (lowercase, hyphens) |
| `name` | string | Human-readable name |
| `travelmate_domain` | string | Primary domain for captive portal detection. Named for historical reasons; used by all compilation targets. |
| `auth_type` | string | One of the 12 types above |
| `credentials` | string | Which credentials are needed: `"none"`, `"username_password"`, `"username_only"`, `"password_only"` |
| `version` | string | Semantic version of this recipe (e.g. `"1.0.0"`). Increment on any recipe change. |
| `schema_version` | number | Recipe schema version this file conforms to. Current: `2`. |
| `sources` | array | Array of source attribution objects (at least one required). See below. |

### Source Attribution

Each recipe must declare where its portal behavior was derived from. A recipe can have multiple sources when functionality overlaps between monitored projects.

#### Source object fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project` | string | yes | Source project: `"CaptivePortalAutoLogin"`, `"captive.d"`, `"manual-research"` |
| `handler` | string | yes | Handler/class name in source project (e.g. `"BlockHouse"`, `"DBWifi"`) |
| `commit` | string | no | Git commit hash from source project. Omit for `manual-research`. |
| `license` | string | yes | License of the source project (e.g. `"GPL-3.0"`, `"BSD-3-Clause"`, `"MIT"`) |
| `note` | string | no | Context about derivation (e.g. "Simplified from 5-step flow") |

Example (dual-source recipe):
```json
"sources": [
    { "project": "CaptivePortalAutoLogin", "handler": "FritzBox", "commit": "7c597a3", "license": "GPL-3.0" },
    { "project": "captive.d", "handler": "generic_avm", "license": "BSD-3-Clause", "note": "Overlapping AVM Fritz!Box pattern" }
]
```

### Match Object (optional, recommended)

The `match` object enables auto-detection of which recipe applies to a given captive portal. A detection tool can match against SSID, domain, URL path, and response body content.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `match.ssids` | array | `[]` | WiFi SSID patterns (supports `*` wildcard, e.g. `"-REWE gratis WLAN-*"`) |
| `match.domains` | array | `[]` | Domain patterns (supports `*` wildcard suffix, e.g. `"*.conn4.com"`) |
| `match.paths` | array | `[]` | URL path prefixes (exact match, e.g. `"/ident"`) |
| `match.body_contains` | array | `[]` | Strings that must appear in the captive portal response body |
| `match.priority` | number | `50` | Higher = preferred when multiple recipes match (range 0-100) |

### Optional (all auth_types)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `fallback_domains` | array | `[]` | Alternative domains to try if primary fails DNS |
| `success_check` | string | `"empty_body"` | How to verify success: `"empty_body"`, `"body_contains"`, `"body_not_contains"`, `"json_field"` |
| `success_pattern` | string | `""` | Pattern for success_check (if body_contains) |
| `success_json_field` | string | `""` | JSON field path (if json_field) |
| `success_json_value` | string | `"true"` | Expected JSON field value |

### click-through-grant params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `grant_url_source` | string | `"redirect_url"` | Where to find the grant URL: `"redirect_url"` or `"body_html"` |
| `grant_url_extract` | string | `"query_param"` | How to extract: `"query_param"` or `"regex"` |
| `grant_url_param` | string | `""` | Query parameter name containing grant URL |
| `grant_url_regex` | string | `""` | Regex to extract grant URL from body |
| `continue_url` | string | `"http://google.com/"` | URL to pass as continue_url param |
| `duration` | number | `86400` | Duration in seconds |
| `grant_method` | string | `"GET"` | HTTP method for grant request |

### form-submit params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `form_page_url` | string | `"${trm_captiveurl}"` | URL to fetch the form from |
| `form_action_extract` | string | `"action_attribute"` | How to find form target |
| `form_action_regex` | string | `""` | Regex to extract form action |
| `extra_fields` | object | `{}` | Extra fields to add to POST (e.g. `{"answer": "1"}`) |
| `username_field` | string | `"username"` | Name of username form field |
| `password_field` | string | `"password"` | Name of password form field |
| `submit_method` | string | `"POST"` | Form submit method |
| `url_encode_creds` | boolean | `false` | URL-encode credentials before posting |

### csrf-form-submit params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `csrf_source` | string | `"cookie"` | Where to find CSRF token: `"cookie"` or `"body_hidden"` or `"body_regex"` |
| `csrf_page_url` | string | `""` | URL to fetch for CSRF token (empty = domain root) |
| `csrf_cookie_name` | string | `"csrf"` | Name of cookie containing CSRF token |
| `csrf_field_name` | string | `"CSRFToken"` | Name of hidden input field |
| `csrf_regex` | string | `""` | Regex to extract token from body |
| `csrf_submit_url` | string | `""` | URL to POST to (empty = same page) |
| `extra_fields` | object | `{}` | Extra fields to add |
| `submit_method` | string | `"POST"` | Form submit method |

### json-api params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `steps` | array | `[]` | Array of step objects (see below) |

#### json-api step object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Step name (for logging) |
| `method` | string | `"GET"` or `"POST"` |
| `url` | string | URL template (can use `{var}` references) |
| `data` | object | POST data (for POST method) |
| `headers` | object | Extra headers |
| `extract` | object | Variables to extract from response: `{"var": "json_path"}` |
| `extract_regex` | object | Variables to extract via regex: `{"var": {"from": "url", "regex": "..."}}` |

### chap-md5 params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `form_page_url` | string | `"${trm_captiveurl}"` | URL to fetch login page |
| `chap_detect_pattern` | string | `"hexMD5"` | Pattern in body indicating CHAP auth |
| `chap_id_extract` | string | `""` | Regex for chap ID |
| `chap_challenge_extract` | string | `""` | Regex for challenge string |
| `form_action` | string | `"/hotspot/login"` | Form action URL |
| `username_field` | string | `"username"` | Name of username field |
| `response_field` | string | `"response"` | Name of CHAP response field |
| `dst_field` | string | `"dst"` | Name of destination field |
| `dst_default` | string | `""` | Default value for dst field |

### js-redirect params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `js_extract_patterns` | string | built-in | Custom awk code to extract redirect URL from body (default: matches `window.location`, `location.href`, `location.replace`, `location =`) |
| `follow_redirect` | string | `"true"` | Whether to GET the extracted redirect URL (`"true"` or `"false"`) |

### multi-step-form params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `stepN_url` | string | (required) | Page URL for step N (steps are numbered 1, 2, 3...) |
| `stepN_name` | string | `"step N"` | Step description |
| `stepN_extra_fields` | string | `""` | Additional POST fields for step N (URL-encoded, e.g. `"room=101&adults=1"`) |
| `stepN_extract` | string | `""` | Variables to extract from response for next step (`"var:awk_code"`, comma-separated) |

### cookie-chain params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `init_url` | string | `"${trm_captiveurl}"` | First page to fetch (sets cookies in jar) |
| `cookie_extract_pattern` | string | `"NR>3{print $NF}"` | Awk pattern to extract session token from cookie jar |
| `submit_url` | string | `"http://${trm_domain}"` | URL to POST to with cookies and token |
| `post_data` | string | `"accept=1"` | POST data template (can reference `${session_token}`) |
| `extra_headers` | string | `""` | Additional headers (e.g. `"X-Requested-With: XMLHttpRequest"`) |

### js-parse params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `js_page_url` | string | `"${trm_captiveurl}"` | URL to fetch page containing JS |
| `js_extractN_var` | string | (required) | Shell variable name for Nth extraction |
| `js_extractN_pattern` | string | (required) | POSIX ERE regex with capture group |
| `js_extractN_default` | string | `""` | Default value if extraction fails (empty = required, exits with error) |
| `submit_url` | string | `"http://${trm_domain}"` | URL for final POST (can reference extracted vars) |
| `submit_method` | string | `"POST"` | GET or POST |
| `submit_data` | string | `""` | POST body template |
| `submit_content_type` | string | `"application/x-www-form-urlencoded"` | Content-Type header |
| `submit_extra_headers` | string | `""` | Additional headers |

### multipart-post params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `form_page_url` | string | `"${trm_captiveurl}"` | URL to fetch form page |
| `submit_url` | string | `"http://${trm_domain}"` | URL to POST multipart form to |
| `fieldN_name` | string | (required) | Form field name for Nth field |
| `fieldN_value` | string | `""` | Static value for field N |
| `fieldN_source` | string | `"static"` | Field source: `static`, `hidden`, or `extract` |
| `fieldN_extract` | string | `""` | Regex for extracting hidden field value (if source=hidden) |
| `fieldN_pattern` | string | `""` | Regex for extracting value from page (if source=extract) |

### multi-api params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `steps` | array | `[]` | Array of step objects (see below) |

#### multi-api step object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Step name (for logging) |
| `type` | string | Step type: `fetch`, `redirect`, or `foreach` |
| `method` | string | `"GET"` or `"POST"` (for fetch type) |
| `url` | string | URL template (can use `{var}` references) |
| `data` | object | POST data (for POST method, fetch type) |
| `headers` | object | Extra headers |
| `extract` | object | Variables to extract from response: `{"var": "json_path"}` |
| `extract_regex` | object | Variables to extract via regex: `{"var": {"from": "url", "regex": "..."}}` |
| `foreach_in` | string | Variable containing newline-separated list (for foreach type) |
| `foreach_as` | string | Loop variable name (default: `"item"`) |
| `foreach_until_success` | string | Break on first success (default: `"true"`) |

### jwt-sign params

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `jwt_header` | string | `'{"alg":"HS256","typ":"JWT"}'` | JWT header JSON |
| `jwt_payload` | string | (required) | JWT payload JSON template |
| `jwt_secret` | string | (required) | HMAC-SHA256 secret key |
| `jwt_query_param` | string | `"jwt"` | Query parameter name for JWT |
| `request_url` | string | (required) | URL to send JWT to |
| `request_method` | string | `"GET"` | GET or POST |
