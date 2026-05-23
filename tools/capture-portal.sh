#!/bin/bash
# capture-portal.sh - Semi-automated captive portal capture & recipe generation
# Records HTTP redirect chain + auth flow, anonymizes, outputs draft recipe JSON.
# Works on macOS (bash). Portable to OpenWrt (busybox ash) where possible.
# No python3, no perl, no jq. Uses: bash/ash, curl, awk, sed, grep, tr.

set -euo pipefail 2>/dev/null || set -eo pipefail

# ---- Constants ----
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="${SCRIPT_DIR}/captures/${TIMESTAMP}"
COOKIE_JAR=""
VERBOSE=0
MANUAL_MODE=0
FORCE_AUTH_TYPE=""
CLI_USER=""
CLI_PASS=""
CLI_VOUCHER=""
NO_ANONYMIZE=0
RECIPE_ONLY=0

# Captured state
PORTAL_DOMAIN=""
PORTAL_URL=""
REDIRECT_CHAIN=""
DETECTED_AUTH_TYPE=""
HOP_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- Utility Functions ----

log()   { printf "${CYAN}[*]${NC} %s\n" "$*" >&2; }
ok()    { printf "${GREEN}[+]${NC} %s\n" "$*" >&2; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*" >&2; }
err()   { printf "${RED}[-]${NC} %s\n" "$*" >&2; }
phase() { printf "\n${MAGENTA}=== Phase %s: %s ===${NC}\n" "$1" "$2" >&2; }
dbg()   { [ "$VERBOSE" -eq 1 ] && printf "${BLUE}[D]${NC} %s\n" "$*" >&2 || true; }

die() {
    err "$*"
    exit 1
}

url_decode() {
    printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')"
}

url_encode() {
    printf '%s' "$1" | tr -d '\n' | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/\&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/\*/%2a/g; s/+/%2b/g; s/,/%2c/g; s/\//%2f/g; s/:/%3a/g; s/;/%3b/g; s/</%3c/g; s/=/%3d/g; s/>/%3e/g; s/?/%3f/g; s/@/%40/g; s/\[/%5b/g; s/\\/%5c/g; s/\]/%5d/g; s/{/%7b/g; s/|/%7c/g; s/}/%7d/g'
}

extract_query_param() {
    local url="$1"
    local param="$2"
    echo "$url" | sed -n "s/.*[?&]${param}=\([^&#]*\).*/\1/p" | head -1
}

extract_domain() {
    local url="$1"
    echo "$url" | sed 's|^https\?://||;s|/.*||;s|:.*||'
}

extract_path() {
    local url="$1"
    echo "$url" | sed 's|^https\?://[^/]*||'
}

# Portable MD5
md5_hash() {
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$1" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$1" | md5
    else
        printf '%s' "$1" | openssl md5 | awk '{print $NF}'
    fi
}

# JSON generation helpers (no jq)
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//'
}

json_str() {
    # Output a JSON string value (with quotes)
    local val
    val="$(json_escape "$1")"
    printf '"%s"' "$val"
}

json_obj_start() { printf "{"; }
json_obj_end() { printf "}"; }
json_arr_start() { printf "["; }
json_arr_end() { printf "]"; }

# ---- Cleanup ----

cleanup() {
    dbg "Cleanup: removing temp files"
    if [ -n "${COOKIE_JAR:-}" ] && [ -f "${COOKIE_JAR}" ]; then
        # Keep the final cookie jar in output
        if [ -d "${OUTPUT_DIR}" ]; then
            cp "${COOKIE_JAR}" "${OUTPUT_DIR}/cookies.txt" 2>/dev/null || true
        fi
        rm -f "${COOKIE_JAR}"
    fi
    # Remove empty output dir
    if [ -d "${OUTPUT_DIR}" ] && [ -z "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]; then
        rmdir "${OUTPUT_DIR}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ---- CLI ----

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Semi-automated captive portal capture tool.
Records the HTTP interaction, anonymizes it, and generates a recipe JSON.

Options:
  --output DIR        Output directory for captures (default: ./captures/<timestamp>)
  --manual            Manual capture mode (user authenticates, we record)
  --auth-type TYPE    Force specific auth_type (skip auto-detection)
  --user USER         Username for authentication
  --pass PASS         Password for authentication
  --voucher CODE      Voucher code
  --no-anonymize      Skip anonymization (for private/local testing only)
  --recipe-only       Only generate recipe JSON, skip full capture
  --verbose           Verbose output
  --help              Show this help

Supported auth_type values:
  click-through-grant, form-submit, csrf-form-submit, json-api,
  chap-md5, js-redirect, multi-step-form, cookie-chain

Output files per capture:
  captures/<timestamp>/
  ├── detection.log         Captive portal detection results
  ├── redirect-chain.txt    Full redirect chain with headers
  ├── headers/              Response headers per hop
  ├── bodies/               Response bodies per hop
  ├── cookies.txt           Cookie jar
  ├── auth-flow.txt         Recorded authentication requests/responses
  ├── anonymized.har        Anonymized HAR-like JSON log
  ├── recipe-draft.json     Generated draft recipe
  └── capture-summary.txt   Human-readable summary

Examples:
  # Auto-detect and capture
  $(basename "$0")

  # Manual mode - authenticate in browser while we record
  $(basename "$0") --manual

  # With credentials
  $(basename "$0") --user guest --pass welcome

  # Force auth type and custom output dir
  $(basename "$0") --auth-type csrf-form-submit --output ./my-capture
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        --manual)     MANUAL_MODE=1; shift ;;
        --auth-type)  FORCE_AUTH_TYPE="$2"; shift 2 ;;
        --user)       CLI_USER="$2"; shift 2 ;;
        --pass)       CLI_PASS="$2"; shift 2 ;;
        --voucher)    CLI_VOUCHER="$2"; shift 2 ;;
        --no-anonymize) NO_ANONYMIZE=1; shift ;;
        --recipe-only)  RECIPE_ONLY=1; shift ;;
        --verbose)    VERBOSE=1; shift ;;
        --help|-h)    show_help; exit 0 ;;
        *)            die "Unknown option: $1. Use --help." ;;
    esac
done

# ---- Init Output ----

init_output() {
    mkdir -p "${OUTPUT_DIR}/headers" "${OUTPUT_DIR}/bodies"
    COOKIE_JAR="${OUTPUT_DIR}/.cookiejar.tmp"
    touch "${COOKIE_JAR}"
    dbg "Output directory: ${OUTPUT_DIR}"
}

# ---- Network Info ----

get_network_info() {
    local info=""

    # Timestamp
    info="timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)"

    # Gateway
    local gw=""
    if command -v ip >/dev/null 2>&1; then
        gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
    elif command -v netstat >/dev/null 2>&1; then
        gw=$(netstat -rn 2>/dev/null | grep default | awk '{print $2}' | head -1)
    elif command -v route >/dev/null 2>&1; then
        gw=$(route -n get default 2>/dev/null | grep gateway | awk '{print $2}' | head -1)
    fi
    info="${info}\ngateway=${gw}"

    # Local IP
    local local_ip=""
    if command -v ip >/dev/null 2>&1; then
        local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    elif command -v ifconfig >/dev/null 2>&1; then
        local_ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
    fi
    info="${info}\nlocal_ip=${local_ip}"

    # SSID (macOS / OpenWrt)
    local ssid=""
    if command -v networksetup >/dev/null 2>&1; then
        # macOS
        local wifi_dev=""
        wifi_dev=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{found=1} found && /Device/{print $2; exit}')
        if [ -n "$wifi_dev" ]; then
            ssid=$(networksetup -getairportnetwork "$wifi_dev" 2>/dev/null | sed 's/Current Wi-Fi Network: //' || true)
        fi
    elif command -v iwinfo >/dev/null 2>&1; then
        # OpenWrt
        ssid=$(iwinfo wlan0 info 2>/dev/null | grep "ESSID" | awk -F'"' '{print $2}' || true)
    elif command -v iwgetid >/dev/null 2>&1; then
        ssid=$(iwgetid -r 2>/dev/null || true)
    fi
    info="${info}\nssid=${ssid}"

    # DNS
    local dns=""
    if command -v scutil >/dev/null 2>&1; then
        dns=$(scutil --dns 2>/dev/null | grep "nameserver\[0\]" | head -1 | awk '{print $3}' || true)
    elif [ -f /etc/resolv.conf ]; then
        dns=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}' || true)
    fi
    info="${info}\ndns=${dns}"

    echo -e "$info"
}

# ---- Phase 1: Detection ----

phase1_detection() {
    phase "1" "Detection"

    local net_info
    net_info="$(get_network_info)"
    {
        echo "=== Captive Portal Detection ==="
        echo "$net_info"
        echo ""
    } > "${OUTPUT_DIR}/detection.log"

    log "Checking for captive portal..."

    # Probe captive.apple.com
    local http_code=""
    local effective_url=""
    local redirect_url=""
    local apple_body=""

    # First: no-follow to catch redirect
    dbg "Probing http://captive.apple.com (no follow)..."
    local probe_headers=""
    probe_headers=$(curl -sv --max-time 10 -o "${OUTPUT_DIR}/bodies/hop0.html" \
        -w "\n---CURL_INFO---\nhttp_code=%{http_code}\nredirect_url=%{redirect_url}\nurl_effective=%{url_effective}\n" \
        http://captive.apple.com 2>&1) || true

    http_code=$(echo "$probe_headers" | grep "^http_code=" | tail -1 | sed 's/http_code=//')
    redirect_url=$(echo "$probe_headers" | grep "^redirect_url=" | tail -1 | sed 's/redirect_url=//')
    effective_url=$(echo "$probe_headers" | grep "^url_effective=" | tail -1 | sed 's/url_effective=//')

    # Save hop0 headers
    echo "$probe_headers" | grep -E "^< |^> " > "${OUTPUT_DIR}/headers/hop0.txt" 2>/dev/null || true

    apple_body=$(cat "${OUTPUT_DIR}/bodies/hop0.html" 2>/dev/null || true)

    {
        echo "captive.apple.com status: ${http_code}"
        echo "redirect_url: ${redirect_url}"
        echo "url_effective: ${effective_url}"
    } >> "${OUTPUT_DIR}/detection.log"

    if [ "$http_code" = "200" ] && echo "$apple_body" | grep -q "Success"; then
        ok "Already connected to the internet (captive.apple.com returned Success)"
        echo "result=internet_connected" >> "${OUTPUT_DIR}/detection.log"
        return 0
    fi

    # Captive portal detected
    warn "Captive portal detected! (HTTP ${http_code})"

    if [ -n "$redirect_url" ]; then
        PORTAL_URL="$redirect_url"
    elif [ -n "$effective_url" ] && [ "$effective_url" != "http://captive.apple.com" ]; then
        PORTAL_URL="$effective_url"
    else
        # Try to extract from body
        PORTAL_URL=$(echo "$apple_body" | sed -n 's/.*location\.href.*=.*['\''"]\(http[^'\''"]*\)['\''"].*/\1/p' | head -1)
    fi

    if [ -n "$PORTAL_URL" ]; then
        PORTAL_DOMAIN=$(extract_domain "$PORTAL_URL")
        ok "Portal domain: ${PORTAL_DOMAIN}"
        ok "Portal URL: ${PORTAL_URL}"
    else
        warn "Could not determine portal URL from redirect"
        # Try alternate probe
        local gstatic_code=""
        gstatic_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connectivitycheck.gstatic.com/generate_204 2>/dev/null) || true
        if [ "$gstatic_code" != "204" ]; then
            warn "gstatic also returned non-204 (${gstatic_code}) - captive portal confirmed"
        fi
    fi

    echo "portal_domain=${PORTAL_DOMAIN}" >> "${OUTPUT_DIR}/detection.log"
    echo "portal_url=${PORTAL_URL}" >> "${OUTPUT_DIR}/detection.log"
    echo "result=captive_portal" >> "${OUTPUT_DIR}/detection.log"

    log "Detection log: ${OUTPUT_DIR}/detection.log"
    return 1
}

# ---- Phase 2: Capture Redirect Chain ----

phase2_redirect_chain() {
    phase "2" "Capture Redirect Chain"

    log "Following redirect chain from captive.apple.com..."

    {
        echo "=== Redirect Chain ==="
        echo "Starting URL: http://captive.apple.com"
        echo ""
    } > "${OUTPUT_DIR}/redirect-chain.txt"

    # Use curl -v -L to follow all redirects, saving each hop
    # We capture the full verbose output and split into hops
    local raw_trace=""
    raw_trace=$(curl -svL --max-time 30 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -o "${OUTPUT_DIR}/bodies/final.html" \
        -w "\n---CURL_INFO---\nhttp_code=%{http_code}\nurl_effective=%{url_effective}\nnum_redirects=%{num_redirects}\n" \
        http://captive.apple.com 2>&1) || true

    # Save full trace
    echo "$raw_trace" > "${OUTPUT_DIR}/.raw_trace.tmp"

    # Parse redirect chain from verbose output
    # Each redirect shows: > GET/POST, < HTTP status, < Location:
    local hop_num=1
    local current_url="http://captive.apple.com"
    local in_redirect=0

    # Extract each hop
    echo "$raw_trace" | awk -v outdir="${OUTPUT_DIR}" '
    BEGIN { hop=0; capturing=0; header_file=""; body_file="" }
    /^(---CURL_INFO---)/ { capturing=0; next }
    /^> (GET|POST|PUT|HEAD|DELETE|PATCH) / {
        capturing=1
        hop++
        header_file = outdir "/headers/hop" hop ".txt"
        body_file = outdir "/bodies/hop" hop ".html"
        printf "HOP %d: %s\n", hop, $0 > "/dev/stderr"
    }
    /^< HTTP\// {
        if (capturing) {
            print $0 > header_file
        }
    }
    /^< [A-Za-z-]+:/ {
        if (capturing) {
            print $0 > header_file
        }
    }
    /^< Location:/ {
        if (capturing) {
            print "REDIRECT: " $0 > "/dev/stderr"
        }
    }
    /^< $/ {
        if (capturing) {
            capturing=0
        }
    }
    ' 2>/dev/null || true

    # Count hops from raw trace
    HOP_COUNT=$(echo "$raw_trace" | grep -c "^> GET\|^> POST" 2>/dev/null || echo "1")
    if [ "$HOP_COUNT" -eq 0 ]; then
        HOP_COUNT=1
    fi

    # Extract Location headers for chain
    local locations=""
    locations=$(echo "$raw_trace" | grep -i "^< Location:" | sed 's/^< Location: //' || true)

    # Build redirect chain log
    {
        echo "Total hops: ${HOP_COUNT}"
        echo ""
        echo "--- Location headers ---"
        if [ -n "$locations" ]; then
            echo "$locations" | nl -ba -v1
        else
            echo "(no Location headers found)"
        fi
        echo ""
        echo "--- Set-Cookie headers ---"
        echo "$raw_trace" | grep -i "^< Set-Cookie:" | sed 's/^< Set-Cookie: //' || echo "(no cookies set)"
        echo ""
        echo "--- Final effective URL ---"
        echo "$raw_trace" | grep "^url_effective=" | tail -1 | sed 's/url_effective=//'
    } >> "${OUTPUT_DIR}/redirect-chain.txt"

    # Extract final URL
    local final_url=""
    final_url=$(echo "$raw_trace" | grep "^url_effective=" | tail -1 | sed 's/url_effective=//')

    if [ -n "$final_url" ] && [ -n "$final_url" ] && [ "$final_url" != "http://captive.apple.com" ]; then
        PORTAL_URL="$final_url"
        PORTAL_DOMAIN=$(extract_domain "$PORTAL_URL")
    fi

    # Re-fetch each hop individually for clean body captures
    local redirect_urls=""
    redirect_urls=$(echo "$locations" | tr -d '\r')

    # Save initial hop body (already captured as hop0.html)
    local hop_idx=1
    if [ -n "$redirect_urls" ]; then
        echo "$redirect_urls" | while IFS= read -r loc_url; do
            [ -z "$loc_url" ] && continue
            loc_url=$(echo "$loc_url" | tr -d '\r' | sed 's/^ *//')
            dbg "Fetching hop ${hop_idx}: ${loc_url}"
            curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
                -o "${OUTPUT_DIR}/bodies/hop${hop_idx}.html" \
                "${loc_url}" 2>"${OUTPUT_DIR}/headers/hop${hop_idx}.txt" || true
            hop_idx=$((hop_idx + 1))
        done
    fi

    ok "Redirect chain captured (${HOP_COUNT} hops)"
    log "Chain log: ${OUTPUT_DIR}/redirect-chain.txt"
}

# ---- Phase 3: Interactive Auth Flow Recording ----

phase3_auth_flow() {
    phase "3" "Auth Flow Recording"

    if [ "$MANUAL_MODE" -eq 1 ]; then
        auth_flow_manual
    else
        auth_flow_automatic
    fi
}

auth_flow_manual() {
    log "MANUAL MODE: User will authenticate, tool records the flow"
    echo ""
    warn "========================================================="
    warn "  Please authenticate in your browser or phone now."
    warn "  The tool will monitor the portal URL for changes."
    warn "========================================================="
    echo ""

    {
        echo "=== Auth Flow (Manual Mode) ==="
        echo "Start: $(date)"
        echo "Portal URL: ${PORTAL_URL}"
        echo ""
    } > "${OUTPUT_DIR}/auth-flow.txt"

    # Record initial state
    log "Recording initial portal page..."
    local initial_body=""
    initial_body=$(curl -sL --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -o "${OUTPUT_DIR}/bodies/auth-initial.html" \
        -w "http_code=%{http_code}\nurl_effective=%{url_effective}\n" \
        "${PORTAL_URL}" 2>/dev/null) || true

    echo "--- Initial fetch ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "$initial_body" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Analyze the initial page for forms / endpoints
    local body_content=""
    body_content=$(cat "${OUTPUT_DIR}/bodies/auth-initial.html" 2>/dev/null || true)
    detect_auth_type "$body_content"

    # Prompt user to authenticate
    log "Waiting for user to authenticate..."
    log "Press ENTER when you have completed authentication in your browser..."
    read -r dummy

    # Record post-auth state
    log "Recording post-authentication state..."
    local post_body=""
    post_body=$(curl -sL --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -o "${OUTPUT_DIR}/bodies/auth-post.html" \
        -w "http_code=%{http_code}\nurl_effective=%{url_effective}\n" \
        "${PORTAL_URL}" 2>/dev/null) || true

    echo "--- Post-auth fetch ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "$post_body" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Try the grant URL if detected
    if [ -n "$PORTAL_URL" ]; then
        local base_grant=""
        base_grant=$(extract_query_param "$PORTAL_URL" "base_grant_url")
        if [ -n "$base_grant" ]; then
            log "Detected base_grant_url - fetching..."
            local grant_result=""
            grant_result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
                -o "${OUTPUT_DIR}/bodies/grant-response.html" \
                "${base_grant}?continue_url=http://captive.apple.com" 2>&1) || true
            echo "--- Grant URL fetch ---" >> "${OUTPUT_DIR}/auth-flow.txt"
            echo "$grant_result" >> "${OUTPUT_DIR}/auth-flow.txt"
        fi
    fi

    # Check connectivity
    local check_code=""
    check_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://captive.apple.com 2>/dev/null) || true
    echo "--- Internet check ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "captive.apple.com: HTTP ${check_code}" >> "${OUTPUT_DIR}/auth-flow.txt"

    if [ "$check_code" = "200" ]; then
        ok "Internet appears to be connected after auth"
    else
        warn "Internet still not available (HTTP ${check_code})"
    fi

    echo "End: $(date)" >> "${OUTPUT_DIR}/auth-flow.txt"
}

auth_flow_automatic() {
    log "AUTOMATED PROBE: Analyzing portal authentication..."

    {
        echo "=== Auth Flow (Automated) ==="
        echo "Start: $(date)"
        echo "Portal URL: ${PORTAL_URL}"
        echo ""
    } > "${OUTPUT_DIR}/auth-flow.txt"

    # Fetch the portal/splash page
    local portal_body=""
    local portal_headers=""

    if [ -n "$PORTAL_URL" ]; then
        dbg "Fetching portal page: ${PORTAL_URL}"
        portal_headers=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
            -o "${OUTPUT_DIR}/bodies/portal-page.html" \
            -w "\nhttp_code=%{http_code}\nurl_effective=%{url_effective}\n" \
            "${PORTAL_URL}" 2>&1) || true
        portal_body=$(cat "${OUTPUT_DIR}/bodies/portal-page.html" 2>/dev/null || true)
    else
        # Use hop0 body
        portal_body=$(cat "${OUTPUT_DIR}/bodies/hop0.html" 2>/dev/null || true)
    fi

    if [ -z "$portal_body" ]; then
        warn "Empty portal page - cannot analyze"
        echo "result=empty_body" >> "${OUTPUT_DIR}/auth-flow.txt"
        return 1
    fi

    # Detect auth type
    detect_auth_type "$portal_body"

    # Record analysis
    echo "--- Portal page analysis ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Detected auth_type: ${DETECTED_AUTH_TYPE}" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Extract features
    local form_action=""
    form_action=$(echo "$portal_body" | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//' || true)
    echo "form_action: ${form_action}" >> "${OUTPUT_DIR}/auth-flow.txt"

    local form_method=""
    form_method=$(echo "$portal_body" | grep -oi 'method="[^"]*"' | head -1 | sed 's/method="//;s/"$//' || true)
    echo "form_method: ${form_method}" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Hidden fields
    echo "--- Hidden form fields ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "$portal_body" | grep -oi '<input[^>]*type="hidden"[^>]*>' | \
        sed -n 's/.*name="\([^"]*\)".*value="\([^"]*\)".*/\1=\2/p' >> "${OUTPUT_DIR}/auth-flow.txt" 2>/dev/null || true
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # CSRF tokens
    echo "--- CSRF tokens ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "$portal_body" | grep -oi 'csrf[^"]*' >> "${OUTPUT_DIR}/auth-flow.txt" 2>/dev/null || true
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # JavaScript redirects
    echo "--- JavaScript redirects ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "$portal_body" | grep -oiE '(window\.location|location\.href|location\.replace)[^;]*' >> "${OUTPUT_DIR}/auth-flow.txt" 2>/dev/null || true
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Cookie analysis
    echo "--- Cookies set ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    if [ -f "${COOKIE_JAR}" ]; then
        cat "${COOKIE_JAR}" >> "${OUTPUT_DIR}/auth-flow.txt" 2>/dev/null || true
    fi
    echo "" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Attempt authentication based on type
    attempt_auth "$portal_body" "$form_action" "$form_method"

    echo "End: $(date)" >> "${OUTPUT_DIR}/auth-flow.txt"
}

# ---- Auth Type Detection ----

detect_auth_type() {
    local body="$1"

    # If forced, use that
    if [ -n "$FORCE_AUTH_TYPE" ]; then
        DETECTED_AUTH_TYPE="$FORCE_AUTH_TYPE"
        log "Forced auth_type: ${DETECTED_AUTH_TYPE}"
        return
    fi

    # Detection logic (priority order)
    local has_js_redirect=0
    local has_grant_form=0
    local has_csrf=0
    local has_chap=0
    local has_json_api=0
    local has_session_cookie=0

    # 1. JS redirect
    if echo "$body" | grep -qiE 'window\.location|location\.href|location\.replace|location\s*='; then
        has_js_redirect=1
    fi

    # 2. Click-through grant (form with base_grant_url or grant in action)
    if echo "$body" | grep -qiE 'base_grant_url|grant.*url|action.*grant'; then
        has_grant_form=1
    fi
    # Also check URL params
    if [ -n "$PORTAL_URL" ] && echo "$PORTAL_URL" | grep -qi "base_grant_url"; then
        has_grant_form=1
    fi

    # 3. CSRF token
    if echo "$body" | grep -qiE 'csrf|CSRFToken|_token|csrfmiddlewaretoken'; then
        has_csrf=1
    fi
    if [ -f "${COOKIE_JAR}" ] && grep -qi 'csrf' "${COOKIE_JAR}" 2>/dev/null; then
        has_csrf=1
    fi

    # 4. CHAP MD5
    if echo "$body" | grep -qiE 'hexMD5|chap.challenge|CHAP|md5Challenge'; then
        has_chap=1
    fi

    # 5. JSON API
    if echo "$body" | grep -qiE '/api/|application/json'; then
        has_json_api=1
    fi
    if [ -n "$PORTAL_URL" ] && echo "$PORTAL_URL" | grep -qiE '/api/'; then
        has_json_api=1
    fi

    # 6. Multiple form pages
    local form_count=0
    form_count=$(echo "$body" | grep -ci '<form' 2>/dev/null || echo "0")

    # 7. Session cookie
    if [ -f "${COOKIE_JAR}" ] && grep -qiE 'PHPSESSID|JSESSIONID|session.id|sid' "${COOKIE_JAR}" 2>/dev/null; then
        has_session_cookie=1
    fi

    # Decision tree
    if [ "$has_js_redirect" -eq 1 ]; then
        DETECTED_AUTH_TYPE="js-redirect"
    elif [ "$has_grant_form" -eq 1 ]; then
        DETECTED_AUTH_TYPE="click-through-grant"
    elif [ "$has_csrf" -eq 1 ]; then
        DETECTED_AUTH_TYPE="csrf-form-submit"
    elif [ "$has_chap" -eq 1 ]; then
        DETECTED_AUTH_TYPE="chap-md5"
    elif [ "$has_json_api" -eq 1 ]; then
        DETECTED_AUTH_TYPE="json-api"
    elif [ "$form_count" -gt 1 ]; then
        DETECTED_AUTH_TYPE="multi-step-form"
    elif [ "$has_session_cookie" -eq 1 ]; then
        DETECTED_AUTH_TYPE="cookie-chain"
    elif [ "$form_count" -eq 1 ]; then
        DETECTED_AUTH_TYPE="form-submit"
    else
        DETECTED_AUTH_TYPE="form-submit"
    fi

    ok "Detected auth_type: ${DETECTED_AUTH_TYPE}"
}

# ---- Auth Attempts ----

attempt_auth() {
    local body="$1"
    local form_action="$2"
    local form_method="$3"

    case "$DETECTED_AUTH_TYPE" in
        click-through-grant)
            attempt_click_through "$body"
            ;;
        form-submit)
            attempt_form_submit "$body" "$form_action"
            ;;
        csrf-form-submit)
            attempt_csrf_submit "$body" "$form_action"
            ;;
        js-redirect)
            attempt_js_redirect "$body"
            ;;
        chap-md5)
            attempt_chap "$body" "$form_action"
            ;;
        json-api)
            attempt_json_api "$body"
            ;;
        cookie-chain)
            attempt_cookie_chain "$body"
            ;;
        multi-step-form)
            warn "Multi-step form detected - manual auth recommended (--manual)"
            ;;
        *)
            warn "Unknown auth type: ${DETECTED_AUTH_TYPE}"
            ;;
    esac
}

attempt_click_through() {
    local body="$1"

    log "Attempting click-through authentication..."

    # Look for base_grant_url in redirect URL
    local grant_url=""
    grant_url=$(extract_query_param "$PORTAL_URL" "base_grant_url")

    if [ -z "$grant_url" ]; then
        # Try extracting from body
        grant_url=$(echo "$body" | sed -n 's/.*base_grant_url=\([^&"'\''<> ]*\).*/\1/p' | head -1)
        if [ -n "$grant_url" ]; then
            grant_url=$(url_decode "$grant_url")
        fi
    fi

    if [ -n "$grant_url" ]; then
        local continue_url="http://captive.apple.com"
        log "Grant URL: ${grant_url}?continue_url=${continue_url}"

        echo "--- Click-through attempt ---" >> "${OUTPUT_DIR}/auth-flow.txt"
        echo "GET ${grant_url}?continue_url=${continue_url}" >> "${OUTPUT_DIR}/auth-flow.txt"

        local result=""
        result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
            -o "${OUTPUT_DIR}/bodies/grant-response.html" \
            "${grant_url}?continue_url=${continue_url}" 2>&1) || true

        echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
    else
        warn "No base_grant_url found in redirect or body"
    fi
}

attempt_form_submit() {
    local body="$1"
    local form_action="$2"

    log "Attempting form POST..."

    # Resolve form action
    if [ -z "$form_action" ]; then
        form_action=$(echo "$body" | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//' || true)
    fi
    if [ -z "$form_action" ]; then
        form_action="${PORTAL_URL}"
    fi

    # Make absolute
    if echo "$form_action" | grep -qv "^http"; then
        form_action="http://${PORTAL_DOMAIN}${form_action}"
    fi

    # Extract hidden fields
    local hidden_data=""
    hidden_data=$(echo "$body" | grep -oi '<input[^>]*type="hidden"[^>]*>' | \
        sed -n 's/.*name="\([^"]*\)".*value="\([^"]*\)".*/\1=\2\&/p' | tr -d '\n' | sed 's/&$//' || true)

    # Build POST data
    local post_data="${hidden_data}"
    if [ -n "$CLI_USER" ]; then
        local username_field=""
        username_field=$(echo "$body" | grep -oi 'name="[^"]*user[^"]*\|name="[^"]*login[^"]*\|name="[^"]*email[^"]*"' | head -1 | sed 's/name="//;s/"$//' || echo "username")
        post_data="${post_data}&${username_field}=$(url_encode "$CLI_USER")"
    fi
    if [ -n "$CLI_PASS" ]; then
        local password_field=""
        password_field=$(echo "$body" | grep -oi 'name="[^"]*pass[^"]*"' | head -1 | sed 's/name="//;s/"$//' || echo "password")
        post_data="${post_data}&${password_field}=$(url_encode "$CLI_PASS")"
    fi
    if [ -n "$CLI_VOUCHER" ]; then
        local voucher_field=""
        voucher_field=$(echo "$body" | grep -oi 'name="[^"]*voucher[^"]*\|name="[^"]*code[^"]*\|name="[^"]*access[^"]*"' | head -1 | sed 's/name="//;s/"$//' || echo "voucher")
        post_data="${post_data}&${voucher_field}=$(url_encode "$CLI_VOUCHER")"
    fi

    # Clean leading &
    post_data=$(echo "$post_data" | sed 's/^&//')

    log "POST to: ${form_action}"
    dbg "  Data: ${post_data}"

    echo "--- Form POST attempt ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "POST ${form_action}" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Data: ${post_data}" >> "${OUTPUT_DIR}/auth-flow.txt"

    local result=""
    result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -X POST "$form_action" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$post_data" \
        -o "${OUTPUT_DIR}/bodies/form-response.html" \
        2>&1) || true

    echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
}

attempt_csrf_submit() {
    local body="$1"
    local form_action="$2"

    log "Attempting CSRF form submit..."

    # Extract CSRF token from body
    local csrf_token=""
    csrf_token=$(echo "$body" | sed -n 's/.*name="\(CSRFToken\|csrf_token\|_token\|csrfmiddlewaretoken\)"[^>]*value="\([^"]*\)".*/\2/p' | head -1 || true)
    if [ -z "$csrf_token" ]; then
        csrf_token=$(echo "$body" | grep -oiE 'csrf[^>]*value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//' || true)
    fi

    # Extract from cookie jar
    if [ -z "$csrf_token" ] && [ -f "${COOKIE_JAR}" ]; then
        csrf_token=$(grep -i "csrf" "${COOKIE_JAR}" | awk '{print $NF}' | head -1 || true)
    fi

    if [ -z "$csrf_token" ]; then
        warn "Could not extract CSRF token"
        echo "csrf_token_extraction_failed=true" >> "${OUTPUT_DIR}/auth-flow.txt"
        return 1
    fi

    # Find form action
    if [ -z "$form_action" ]; then
        form_action=$(echo "$body" | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//' || true)
    fi
    if [ -z "$form_action" ]; then
        form_action="${PORTAL_URL}"
    fi
    if echo "$form_action" | grep -qv "^http"; then
        form_action="https://${PORTAL_DOMAIN}${form_action}"
    fi

    local csrf_field=""
    csrf_field=$(echo "$body" | grep -oiE 'name="(CSRFToken|csrf_token|_token|csrfmiddlewaretoken)"' | head -1 | sed 's/name="//;s/"$//' || echo "CSRFToken")

    local post_data="${csrf_field}=$(url_encode "$csrf_token")"
    if [ -n "$CLI_USER" ]; then
        post_data="${post_data}&username=$(url_encode "$CLI_USER")"
    fi
    if [ -n "$CLI_PASS" ]; then
        post_data="${post_data}&password=$(url_encode "$CLI_PASS")"
    fi

    log "CSRF POST to: ${form_action}"
    dbg "  Token: ${csrf_token:0:8}..."

    echo "--- CSRF form submit ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "POST ${form_action}" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "CSRF field: ${csrf_field}" >> "${OUTPUT_DIR}/auth-flow.txt"

    local result=""
    result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -X POST "$form_action" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$post_data" \
        -o "${OUTPUT_DIR}/bodies/csrf-response.html" \
        2>&1) || true

    echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
}

attempt_js_redirect() {
    local body="$1"

    log "Extracting JavaScript redirect URL..."

    local js_url=""
    js_url=$(echo "$body" | sed -n 's/.*window\.location[^=]*=[^"'\''"]*['\''"]\(http[^'\''"]*\)['\''"].*/\1/p' | head -1)
    if [ -z "$js_url" ]; then
        js_url=$(echo "$body" | sed -n 's/.*location\.href[^=]*=[^"'\''"]*['\''"]\(http[^'\''"]*\)['\''"].*/\1/p' | head -1)
    fi
    if [ -z "$js_url" ]; then
        js_url=$(echo "$body" | sed -n 's/.*location\.replace([^)'\''"]*['\''"]\(http[^'\''"]*\)['\''"].*/\1/p' | head -1)
    fi
    if [ -z "$js_url" ]; then
        # Relative URL
        js_url=$(echo "$body" | sed -n 's/.*window\.location[^=]*=[^"'\''"]*['\''"]\([^'\''"]*\)['\''"].*/\1/p' | head -1)
        if [ -n "$js_url" ] && echo "$js_url" | grep -qv "^http"; then
            js_url="http://${PORTAL_DOMAIN}${js_url}"
        fi
    fi

    if [ -n "$js_url" ]; then
        log "JS redirect URL: ${js_url}"
        echo "--- JS redirect follow ---" >> "${OUTPUT_DIR}/auth-flow.txt"
        echo "Extracted URL: ${js_url}" >> "${OUTPUT_DIR}/auth-flow.txt"

        local result=""
        result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
            -o "${OUTPUT_DIR}/bodies/js-redirect-response.html" \
            "${js_url}" 2>&1) || true

        echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"

        # Re-analyze the redirected page
        local new_body=""
        new_body=$(cat "${OUTPUT_DIR}/bodies/js-redirect-response.html" 2>/dev/null || true)
        if [ -n "$new_body" ]; then
            detect_auth_type "$new_body"
        fi
    else
        warn "Could not extract JS redirect URL"
    fi
}

attempt_chap() {
    local body="$1"
    local form_action="$2"

    if [ -z "$CLI_USER" ] || [ -z "$CLI_PASS" ]; then
        warn "CHAP auth requires --user and --pass"
        echo "chap_skipped=no_credentials" >> "${OUTPUT_DIR}/auth-flow.txt"
        return 1
    fi

    log "Attempting CHAP MD5 authentication..."

    # Extract challenge
    local challenge=""
    challenge=$(echo "$body" | sed -n 's/.*name="chap_challenge"[^>]*value="\([^"]*\)".*/\1/p' | head -1)
    if [ -z "$challenge" ]; then
        challenge=$(echo "$body" | sed -n 's/.*challenge[^>]*value="\([^"]*\)".*/\1/p' | head -1)
    fi
    if [ -z "$challenge" ]; then
        challenge=$(echo "$body" | sed -n 's/.*var\s\+challenge\s*=\s*['\''"]\\([^'\''"]*\\)['\''"].*/\1/p' | head -1)
    fi

    if [ -z "$challenge" ]; then
        warn "No CHAP challenge found in body"
        echo "chap_skipped=no_challenge" >> "${OUTPUT_DIR}/auth-flow.txt"
        return 1
    fi

    local chap_response=""
    chap_response=$(md5_hash "${challenge}${CLI_PASS}")

    # Resolve form action
    if [ -z "$form_action" ]; then
        form_action=$(echo "$body" | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//' || echo "/hotspot/login")
    fi
    if echo "$form_action" | grep -qv "^http"; then
        form_action="http://${PORTAL_DOMAIN}${form_action}"
    fi

    log "CHAP: MD5(challenge+password) = ${chap_response}"

    echo "--- CHAP MD5 attempt ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "POST ${form_action}" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Challenge: ${challenge}" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Response: ${chap_response}" >> "${OUTPUT_DIR}/auth-flow.txt"

    local post_data="username=$(url_encode "$CLI_USER")&response=${chap_response}&dst=http://captive.apple.com"

    local result=""
    result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -X POST "$form_action" \
        -d "$post_data" \
        -o "${OUTPUT_DIR}/bodies/chap-response.html" \
        2>&1) || true

    echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
}

attempt_json_api() {
    local body="$1"

    log "Attempting JSON API authentication..."

    # Try to find API endpoints in the body
    local api_url=""
    api_url=$(echo "$body" | grep -oiE 'https?://[^"'\'' <>]+/api/[^"'\'' <>]+' | head -1)

    if [ -z "$api_url" ]; then
        # Check if URL itself is an API
        if echo "$PORTAL_URL" | grep -qi "/api/"; then
            api_url="$PORTAL_URL"
        else
            warn "No API endpoint found"
            echo "json_api_skipped=no_endpoint" >> "${OUTPUT_DIR}/auth-flow.txt"
            return 1
        fi
    fi

    echo "--- JSON API attempt ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Endpoint: ${api_url}" >> "${OUTPUT_DIR}/auth-flow.txt"

    local result=""
    result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -H "Content-Type: application/json" \
        -o "${OUTPUT_DIR}/bodies/api-response.json" \
        "${api_url}" 2>&1) || true

    echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
}

attempt_cookie_chain() {
    local body="$1"

    log "Attempting cookie chain authentication..."

    # Check for PHPSESSID / session cookies
    if [ ! -f "${COOKIE_JAR}" ]; then
        warn "No cookie jar - cookie chain requires session cookies"
        return 1
    fi

    local session_token=""
    session_token=$(grep -iE 'PHPSESSID|JSESSIONID|session\.id|sid' "${COOKIE_JAR}" 2>/dev/null | awk '{print $NF}' | head -1)

    if [ -z "$session_token" ]; then
        warn "No session cookie found"
        return 1
    fi

    echo "--- Cookie chain attempt ---" >> "${OUTPUT_DIR}/auth-flow.txt"
    echo "Session token: ${session_token}" >> "${OUTPUT_DIR}/auth-flow.txt"

    # Try POST with session cookie
    local submit_url="http://${PORTAL_DOMAIN}"
    local post_data="accept=1"

    local result=""
    result=$(curl -sv --max-time 15 -c "${COOKIE_JAR}" -b "${COOKIE_JAR}" \
        -X POST "$submit_url" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d "$post_data" \
        -o "${OUTPUT_DIR}/bodies/cookie-chain-response.html" \
        2>&1) || true

    echo "$result" >> "${OUTPUT_DIR}/auth-flow.txt"
}

# ---- Phase 4: Anonymization ----

phase4_anonymize() {
    phase "4" "Anonymization"

    if [ "$NO_ANONYMIZE" -eq 1 ]; then
        warn "Anonymization skipped (--no-anonymize)"
        return
    fi

    log "Anonymizing captured data..."

    # Collect network info for anonymization
    local local_ip=""
    local gateway_ip=""
    local ssid=""
    local net_info=""
    net_info=$(cat "${OUTPUT_DIR}/detection.log" 2>/dev/null || true)
    local_ip=$(echo "$net_info" | grep "^local_ip=" | sed 's/local_ip=//' || true)
    gateway_ip=$(echo "$net_info" | grep "^gateway=" | sed 's/gateway=//' || true)
    ssid=$(echo "$net_info" | grep "^ssid=" | sed 's/ssid=//' || true)

    # Build anonymized HAR
    {
        printf '{\n'
        printf '  "log": {\n'
        printf '    "version": "1.2",\n'
        printf '    "creator": {"name": "capture-portal.sh", "version": "%s"},\n' "$VERSION"
        printf '    "entries": [\n'

        local first_entry=1
        local hop_idx=0

        # Process each hop
        while [ -f "${OUTPUT_DIR}/headers/hop${hop_idx}.txt" ] || [ -f "${OUTPUT_DIR}/bodies/hop${hop_idx}.html" ]; do
            local header_file="${OUTPUT_DIR}/headers/hop${hop_idx}.txt"
            local body_file="${OUTPUT_DIR}/bodies/hop${hop_idx}.html"

            # Read and anonymize headers
            local raw_headers=""
            raw_headers=$(cat "$header_file" 2>/dev/null || true)

            # Read body for URL extraction
            local raw_body=""
            raw_body=$(cat "$body_file" 2>/dev/null || true)
            # Truncate large bodies for HAR
            local body_preview=""
            body_preview=$(echo "$raw_body" | head -c 4096)

            # Anonymize
            local anon_headers=""
            anon_headers=$(echo "$raw_headers" | \
                sed "s/${local_ip}/REDACTED_IP/g; s/${gateway_ip}/REDACTED_GW/g" 2>/dev/null || true)

            local anon_body=""
            anon_body=$(echo "$body_preview" | \
                sed "s/${local_ip}/REDACTED_IP/g; s/${gateway_ip}/REDACTED_GW/g" 2>/dev/null || true)

            # Anonymize credentials
            if [ -n "$CLI_USER" ]; then
                anon_headers=$(echo "$anon_headers" | sed "s/${CLI_USER}/REDACTED_USER/g" 2>/dev/null || true)
                anon_body=$(echo "$anon_body" | sed "s/${CLI_USER}/REDACTED_USER/g" 2>/dev/null || true)
            fi
            if [ -n "$CLI_PASS" ]; then
                anon_body=$(echo "$anon_body" | sed "s/${CLI_PASS}/REDACTED_PASS/g" 2>/dev/null || true)
            fi
            if [ -n "$CLI_VOUCHER" ]; then
                anon_body=$(echo "$anon_body" | sed "s/${CLI_VOUCHER}/REDACTED_VOUCHER/g" 2>/dev/null || true)
            fi

            # Anonymize session tokens in cookies
            anon_headers=$(echo "$anon_headers" | \
                sed -E 's/(PHPSESSID|JSESSIONID|session_id|sid)=([^;]+)/\1=SESSION_TOKEN_'${hop_idx}'/g' 2>/dev/null || true)

            # Anonymize MAC addresses
            anon_headers=$(echo "$anon_headers" | \
                sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/REDACTED_MAC/g' 2>/dev/null || true)
            anon_body=$(echo "$anon_body" | \
                sed -E 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/REDACTED_MAC/g' 2>/dev/null || true)

            # Anonymize SSID
            if [ -n "$ssid" ]; then
                anon_body=$(echo "$anon_body" | sed "s/${ssid}/REDACTED_SSID/g" 2>/dev/null || true)
            fi

            # JSON-escape for output
            local safe_headers=""
            safe_headers=$(json_escape "$anon_headers")
            local safe_body=""
            safe_body=$(json_escape "$anon_body")

            # Write entry
            if [ "$first_entry" -eq 0 ]; then
                printf ",\n"
            fi
            first_entry=0

            printf '      {\n'
            printf '        "hop": %d,\n' "$hop_idx"
            printf '        "headers": "%s",\n' "$safe_headers"
            printf '        "bodyPreview": "%s"\n' "$safe_body"
            printf '      }'

            hop_idx=$((hop_idx + 1))
        done

        printf '\n    ],\n'

        # Anonymized network info
        printf '    "networkInfo": {\n'
        printf '      "localIp": "REDACTED_IP",\n'
        printf '      "gateway": "REDACTED_GW",\n'
        printf '      "ssid": "REDACTED_SSID",\n'
        printf '      "portalDomain": "%s"\n' "$PORTAL_DOMAIN"
        printf '    },\n'

        # Auth info
        printf '    "authInfo": {\n'
        printf '      "detectedType": "%s",\n' "$DETECTED_AUTH_TYPE"
        printf '      "portalUrl": "%s"\n' "$(json_escape "${PORTAL_URL}")"
        printf '    }\n'

        printf '  }\n'
        printf '}\n'
    } > "${OUTPUT_DIR}/anonymized.har"

    ok "Anonymized HAR saved: ${OUTPUT_DIR}/anonymized.har"
}

# ---- Phase 5: Recipe Generation ----

phase5_recipe() {
    phase "5" "Recipe Generation"

    log "Generating draft recipe..."

    # Load portal body for analysis
    local portal_body=""
    if [ -f "${OUTPUT_DIR}/bodies/portal-page.html" ]; then
        portal_body=$(cat "${OUTPUT_DIR}/bodies/portal-page.html" 2>/dev/null || true)
    elif [ -f "${OUTPUT_DIR}/bodies/hop0.html" ]; then
        portal_body=$(cat "${OUTPUT_DIR}/bodies/hop0.html" 2>/dev/null || true)
    fi

    # Generate recipe ID from domain
    local recipe_id=""
    if [ -n "$PORTAL_DOMAIN" ]; then
        recipe_id=$(echo "$PORTAL_DOMAIN" | tr '[:upper:]' '[:lower:]' | \
            sed 's/[^a-z0-9.-]//g; s/\./-/g; s/^-//; s/-$//' | \
            sed 's/com-//; s/net-//' | head -c 50)
    fi
    if [ -z "$recipe_id" ]; then
        recipe_id="DRAFT_$(date +%Y%m%d%H%M%S)"
    fi

    # Determine credentials requirement
    local creds_required="none"
    case "$DETECTED_AUTH_TYPE" in
        click-through-grant|js-redirect|cookie-chain)
            creds_required="none"
            ;;
        form-submit|csrf-form-submit|multi-step-form)
            if [ -n "$CLI_USER" ] || [ -n "$CLI_PASS" ]; then
                creds_required="username_password"
            else
                creds_required="TODO_CHECK"
            fi
            ;;
        chap-md5|json-api)
            creds_required="username_password"
            ;;
        *)
            creds_required="TODO_CHECK"
            ;;
    esac

    # Build recipe JSON using awk for reliability
    generate_recipe_json "$recipe_id" "$creds_required" "$portal_body"

    ok "Draft recipe saved: ${OUTPUT_DIR}/recipe-draft.json"
}

generate_recipe_json() {
    local recipe_id="$1"
    local creds="$2"
    local body="$3"

    # Extract form info
    local form_action=""
    form_action=$(echo "$body" | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//' || true)

    local username_field=""
    username_field=$(echo "$body" | grep -oiE 'name="[^"]*user[^"]*"' | head -1 | sed 's/name="//;s/"$//' || echo "username")

    local password_field=""
    password_field=$(echo "$body" | grep -oiE 'name="[^"]*pass[^"]*"' | head -1 | sed 's/name="//;s/"$//' || echo "password")

    # Extract hidden fields for extra_fields
    local hidden_names=""
    hidden_names=$(echo "$body" | grep -oi '<input[^>]*type="hidden"[^>]*>' | \
        sed -n 's/.*name="\([^"]*\)".*/\1/p' | grep -viE 'csrf|token|user|pass' | sort -u 2>/dev/null || true)

    # Extract CSRF info
    local csrf_cookie_name=""
    local csrf_field_name=""
    if [ -f "${COOKIE_JAR}" ]; then
        csrf_cookie_name=$(grep -i "csrf" "${COOKIE_JAR}" 2>/dev/null | awk '{print $5}' | head -1 || true)
    fi
    csrf_field_name=$(echo "$body" | grep -oiE 'name="(CSRFToken|csrf_token|_token|csrfmiddlewaretoken)"' | head -1 | sed 's/name="//;s/"$//' || true)

    # Extract grant URL param
    local grant_url_param=""
    grant_url_param=$(extract_query_param "$PORTAL_URL" "base_grant_url")
    local has_grant_param="false"
    if [ -n "$grant_url_param" ]; then
        has_grant_param="true"
        grant_url_param="base_grant_url"
    fi

    # Extract JS redirect pattern
    local js_pattern=""
    js_pattern=$(echo "$body" | grep -oiE '(window\.location|location\.href|location\.replace)[^;]*' | head -1 || true)

    # Extract extra fields object
    local extra_fields_json="{}"
    if [ -n "$hidden_names" ]; then
        extra_fields_json=$(echo "$hidden_names" | while IFS= read -r fname; do
            [ -z "$fname" ] && continue
            local fval=""
            fval=$(echo "$body" | grep -oi "name=\"${fname}\"[^>]*value=\"[^\"]*\"" | head -1 | sed 's/.*value="//;s/"$//' || true)
            if [ -n "$fval" ]; then
                fval="REDACTED_VALUE"
            fi
            printf '"%s": "%s",' "$fname" "$fval"
        done | sed 's/,$//')
        extra_fields_json="{${extra_fields_json}}"
    fi

    # Build URL template
    local url_template=""
    if [ -n "$PORTAL_URL" ]; then
        # Anonymize URL: keep domain and path, redact query values
        url_template=$(echo "$PORTAL_URL" | sed -E 's/([?&][^=&]+=)[^&]*/\1REDACTED/g')
    fi

    # Write recipe JSON
    {
        printf '{\n'
        printf '  "id": "%s",\n' "$recipe_id"
        printf '  "name": "DRAFT - TODO: Human-readable name",\n'
        printf '  "travelmate_domain": "%s",\n' "${PORTAL_DOMAIN:-TODO_DOMAIN}"
        printf '  "fallback_domains": [],\n'
        printf '  "auth_type": "%s",\n' "${DETECTED_AUTH_TYPE:-TODO}"
        printf '  "credentials": "%s",\n' "$creds"
        printf '  "params": {\n'

        # Auth-type-specific params
        case "$DETECTED_AUTH_TYPE" in
            click-through-grant)
                printf '    "grant_url_source": "%s",\n' "$([ "$has_grant_param" = "true" ] && echo "redirect_url" || echo "TODO_CHECK")"
                printf '    "grant_url_extract": "%s",\n' "$([ "$has_grant_param" = "true" ] && echo "query_param" || echo "TODO_CHECK")"
                printf '    "grant_url_param": "%s",\n' "${grant_url_param:-TODO_CHECK}"
                printf '    "continue_url": "http://google.com/",\n'
                printf '    "duration": 86400,\n'
                printf '    "grant_method": "GET",\n'
                printf '    "success_check": "empty_body"\n'
                ;;
            form-submit)
                printf '    "form_page_url": "${trm_captiveurl}",\n'
                if [ -n "$form_action" ]; then
                    printf '    "form_action_default": "%s",\n' "$form_action"
                else
                    printf '    "form_action_default": "TODO_EXTRACT_FROM_PAGE",\n'
                fi
                printf '    "username_field": "%s",\n' "$username_field"
                printf '    "password_field": "%s",\n' "$password_field"
                printf '    "submit_method": "POST",\n'
                printf '    "extra_fields": "%s",\n' "$(echo "$hidden_names" | tr '\n' '&' | sed 's/=$//; s/=[^&]*/=REDACTED/g' || echo "TODO_CHECK")"
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            csrf-form-submit)
                printf '    "csrf_source": "%s",\n' "$([ -n "$csrf_cookie_name" ] && echo "cookie" || echo "body_hidden")"
                printf '    "csrf_page_url": "%s",\n' "$([ -n "$PORTAL_URL" ] && echo "https://\${trm_domain}/" || echo "TODO_CHECK")"
                printf '    "csrf_cookie_name": "%s",\n' "${csrf_cookie_name:-TODO_CHECK}"
                printf '    "csrf_field_name": "%s",\n' "${csrf_field_name:-TODO_CHECK}"
                printf '    "csrf_submit_url": "%s",\n' "$([ -n "$PORTAL_URL" ] && echo "https://\${trm_domain}/" || echo "TODO_CHECK")"
                printf '    "extra_fields": "%s",\n' "$(echo "$hidden_names" | grep -vi csrf | tr '\n' '&' | sed 's/=$//; s/=[^&]*/=REDACTED/g' || echo "TODO_CHECK")"
                printf '    "submit_method": "POST",\n'
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            js-redirect)
                printf '    "js_extract_patterns": "default",\n'
                printf '    "follow_redirect": "true",\n'
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            chap-md5)
                printf '    "form_page_url": "${trm_captiveurl}",\n'
                printf '    "chap_detect_pattern": "hexMD5",\n'
                printf '    "form_action": "%s",\n' "${form_action:-/hotspot/login}"
                printf '    "username_field": "%s",\n' "$username_field"
                printf '    "response_field": "response",\n'
                printf '    "dst_field": "dst",\n'
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            json-api)
                printf '    "success_check": "json_true",\n'
                printf '    "steps": [\n'
                printf '      {\n'
                printf '        "name": "TODO_step1",\n'
                printf '        "method": "GET",\n'
                printf '        "url": "%s"\n' "$(json_escape "${url_template:-TODO}")"
                printf '      }\n'
                printf '    ]\n'
                ;;
            cookie-chain)
                printf '    "init_url": "${trm_captiveurl}",\n'
                printf '    "cookie_extract_pattern": "NR>3{print $NF}",\n'
                printf '    "submit_url": "http://${trm_domain}",\n'
                printf '    "post_data": "accept=1",\n'
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            multi-step-form)
                printf '    "step1_url": "${trm_captiveurl}",\n'
                printf '    "step1_name": "TODO_step1",\n'
                printf '    "success_check": "TODO_VERIFY"\n'
                ;;
            *)
                printf '    "TODO": "Unknown auth type - manual configuration required"\n'
                ;;
        esac

        printf '  },\n'

        # Metadata
        printf '  "_capture_meta": {\n'
        printf '    "captured_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
        printf '    "portal_url_anonymized": "%s",\n' "$(json_escape "${url_template:-unknown}")"
        printf '    "hop_count": %d,\n' "$HOP_COUNT"
        printf '    "tool_version": "%s",\n' "$VERSION"
        printf '    "draft": true,\n'
        printf '    "todo_fields": [\n'
        printf '      "Verify all field values against actual portal behavior",\n'
        printf '      "Test the generated recipe with compile-recipe.sh",\n'
        printf '      "Set proper success_check and success_pattern",\n'
        printf '      "Remove any remaining REDACTED or TODO markers"\n'
        printf '    ]\n'
        printf '  }\n'

        printf '}\n'
    } > "${OUTPUT_DIR}/recipe-draft.json"
}

# ---- Capture Summary ----

generate_summary() {
    log "Generating capture summary..."

    local net_info=""
    net_info=$(cat "${OUTPUT_DIR}/detection.log" 2>/dev/null || true)
    local local_ip=""
    local gateway_ip=""
    local ssid=""
    local_ip=$(echo "$net_info" | grep "^local_ip=" | sed 's/local_ip=//' || true)
    gateway_ip=$(echo "$net_info" | grep "^gateway=" | sed 's/gateway=//' || true)
    ssid=$(echo "$net_info" | grep "^ssid=" | sed 's/ssid=//' || true)

    {
        echo "========================================"
        echo "  Captive Portal Capture Summary"
        echo "========================================"
        echo "  Generated: $(date)"
        echo ""
        echo "--- Network ---"
        echo "  Local IP:  ${local_ip:-unknown}"
        echo "  Gateway:   ${gateway_ip:-unknown}"
        echo "  SSID:      ${ssid:-unknown}"
        echo ""
        echo "--- Portal ---"
        echo "  Domain:    ${PORTAL_DOMAIN:-unknown}"
        echo "  URL:       ${PORTAL_URL:-unknown}"
        echo "  Auth Type: ${DETECTED_AUTH_TYPE:-unknown}"
        echo "  Hops:      ${HOP_COUNT}"
        echo ""
        echo "--- Files ---"
        echo "  Detection log:     detection.log"
        echo "  Redirect chain:    redirect-chain.txt"
        echo "  Auth flow:         auth-flow.txt"
        echo "  Anonymized HAR:    anonymized.har"
        echo "  Draft recipe:      recipe-draft.json"
        echo ""
        echo "--- Next Steps ---"
        echo "  1. Review recipe-draft.json and fill in TODO markers"
        echo "  2. Test with: compile-recipe.sh recipe-draft.json"
        echo "  3. Validate the compiled login script on the target portal"
        echo "  4. Rename the recipe file (remove DRAFT_ prefix) when ready"
        echo ""
        echo "========================================"
    } > "${OUTPUT_DIR}/capture-summary.txt"

    ok "Summary saved: ${OUTPUT_DIR}/capture-summary.txt"
    cat "${OUTPUT_DIR}/capture-summary.txt" >&2
}

# ---- Main ----

main() {
    printf "${MAGENTA}capture-portal.sh v${VERSION}${NC}\n" >&2
    printf "${MAGENTA}Captive portal capture & recipe generator${NC}\n\n" >&2

    init_output

    # Phase 1: Detection
    local detect_result=0
    phase1_detection || detect_result=$?

    if [ "$detect_result" -eq 0 ]; then
        # Already connected
        exit 0
    fi

    # Phase 2: Capture redirect chain (unless recipe-only)
    if [ "$RECIPE_ONLY" -eq 0 ]; then
        phase2_redirect_chain
    fi

    # Phase 3: Auth flow recording
    phase3_auth_flow

    # Phase 4: Anonymization
    phase4_anonymize

    # Phase 5: Recipe generation
    phase5_recipe

    # Summary
    generate_summary

    log "Capture complete. Output: ${OUTPUT_DIR}"
}

main
