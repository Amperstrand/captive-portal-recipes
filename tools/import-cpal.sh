#!/usr/bin/env bash
# import-cpal.sh — Import portal handler definitions from CaptivePortalAutoLogin
#                  into recipe JSON files.
#
# Clones/fetches the CPAL repo, parses each Kotlin handler via pattern-based
# extraction (grep/awk/sed), classifies the auth_type, generates recipe JSON,
# and compares against existing recipes.
#
# Usage: ./import-cpal.sh [OPTIONS]
set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────────
CPAL_REPO_URL="https://github.com/binarynoise/CaptivePortalAutoLogin"
CPAL_DIR=""
OUTPUT_DIR=""
RECIPE_DIR=""
COMPARE_ONLY=0
FORCE=0
SINGLE_HANDLER=""
VERBOSE=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TODAY="$(date +%Y-%m-%d)"

# Counters
SCANNED=0
ALREADY_COVERED=0
NEW_RECIPES=0
NEEDS_CUSTOM=0
IMPORT_FAILURES=0

# Temp files for report
REPORT_NEW="/tmp/cpal-report-new.$$"
REPORT_CONFLICT="/tmp/cpal-conflict.$$"
REPORT_CUSTOM="/tmp/cpal-custom.$$"
REPORT_FAILURE="/tmp/cpal-failure.$$"
: > "${REPORT_NEW}" ; : > "${REPORT_CONFLICT}" ; : > "${REPORT_CUSTOM}" ; : > "${REPORT_FAILURE}"
cleanup() { rm -f "${REPORT_NEW}" "${REPORT_CONFLICT}" "${REPORT_CUSTOM}" "${REPORT_FAILURE}"; }
trap cleanup EXIT

# ── CLI ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<'HELP'
import-cpal.sh — Import CPAL handler definitions into recipe JSON files

Usage:
  ./import-cpal.sh [OPTIONS]

Options:
  --repo DIR          Path to CaptivePortalAutoLogin repo
                      (default: auto-clone to /tmp/cpal-import)
  --output DIR        Output directory for new recipes
                      (default: <project>/recipes/)
  --compare           Compare with existing recipes, don't create new files
  --force             Overwrite existing recipes with imported versions
  --handler NAME      Import only specific handler (object name, e.g. DBWifi)
  --verbose           Verbose output
  --help              Show this help

Examples:
  # Dry-run comparison
  ./import-cpal.sh --compare

  # Import all, generating new recipes with IMPORT_ prefix
  ./import-cpal.sh

  # Import one handler verbosely
  ./import-cpal.sh --handler DBWifi --verbose

  # Overwrite existing recipes
  ./import-cpal.sh --force
HELP
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)     CPAL_DIR="$2"; shift 2 ;;
        --output)   OUTPUT_DIR="$2"; shift 2 ;;
        --compare)  COMPARE_ONLY=1; shift ;;
        --force)    FORCE=1; shift ;;
        --handler)  SINGLE_HANDLER="$2"; shift 2 ;;
        --verbose)  VERBOSE=1; shift ;;
        --help|-h)  usage ;;
        *)          echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ -z "${CPAL_DIR}" ]]    && CPAL_DIR="/tmp/cpal-import"
[[ -z "${OUTPUT_DIR}" ]]  && OUTPUT_DIR="${PROJECT_DIR}/recipes"
[[ -z "${RECIPE_DIR}" ]]  && RECIPE_DIR="${PROJECT_DIR}/recipes"

# ── helpers ─────────────────────────────────────────────────────────────────
log()   { [[ "${VERBOSE}" -eq 1 ]] && echo "[INFO] $*" || true; }
warn()  { echo "[WARN] $*" >&2; }
err()   { echo "[ERR]  $*" >&2; }

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

# Check if any extracted domain matches an existing recipe's travelmate_domain.
# Handles wildcard matching: *.example.com matches sub.example.com
domains_match_existing() {
    local domains_file="$1"
    local recipe_file="$2"
    local td
    td="$(grep -o '"travelmate_domain"[[:space:]]*:[[:space:]]*"[^"]*"' "${recipe_file}" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    [[ -z "${td}" ]] && return 1
    while IFS= read -r d; do
        [[ -z "${d}" ]] && continue
        local d_norm="${d#\*.}"
        local e_norm="${td#\*.}"
        [[ "${d_norm}" == "${e_norm}" ]] && return 0
        [[ "${d}" == "*."* && "${td}" == *"${d_norm}" ]] && return 0
        [[ "${td}" == *"${d_norm}" ]] && [[ "${d_norm}" != "" ]] && return 0
    done < "${domains_file}"
    return 1
}

# ── Step 1: Fetch CPAL source ──────────────────────────────────────────────
fetch_cpal() {
    if [[ ! -d "${CPAL_DIR}/.git" ]]; then
        echo "Cloning CaptivePortalAutoLogin into ${CPAL_DIR} ..."
        git clone --depth 1 "${CPAL_REPO_URL}" "${CPAL_DIR}"
    else
        echo "Updating CaptivePortalAutoLogin in ${CPAL_DIR} ..."
        git -C "${CPAL_DIR}" pull --ff-only 2>/dev/null || \
            warn "Could not pull — using existing checkout"
    fi
}

HANDLERS_DIR="${CPAL_DIR}/liberator/src/main/kotlin/de/binarynoise/liberator/portals"

# ── Steps 2-5: Process a single .kt file ────────────────────────────────────
process_handler() {
    local kt_file="$1"
    local base
    base="$(basename "${kt_file}" .kt)"

    local content
    content="$(cat "${kt_file}")" || {
        IMPORT_FAILURES=$((IMPORT_FAILURES+1))
        echo "${base}: unreadable" >> "${REPORT_FAILURE}"
        return 1
    }

    # ── Find all PortalLiberator objects/classes ─────────────────────────
    local obj_names=""
    obj_names="$(echo "${content}" | grep -E 'PortalLiberator' | grep -oE '(object|class)[[:space:]]+[A-Za-z0-9_]+' | awk '{print $2}' | sort -u)"

    if [[ -z "${obj_names}" ]]; then
        IMPORT_FAILURES=$((IMPORT_FAILURES+1))
        echo "${base}: no PortalLiberator object/class found" >> "${REPORT_FAILURE}"
        return 1
    fi

    local class_name
    while IFS= read -r class_name; do
        [[ -z "${class_name}" ]] && continue
        [[ "${class_name}" == "_Template" ]] && continue
        # Skip abstract classes — they are base classes, not concrete handlers
        echo "${content}" | grep -q "abstract.*class.*${class_name}" && continue

        if [[ -n "${SINGLE_HANDLER}" && "${class_name}" != "${SINGLE_HANDLER}" ]]; then
            continue
        fi

        SCANNED=$((SCANNED+1))
        _process_object "${class_name}" "${base}" "${content}"
    done <<< "${obj_names}"
}

_process_object() {
    local class_name="$1"
    local base="$2"
    local content="$3"

    log "Extracting: ${class_name} (${base}.kt)"

    # ── Extract per-object code block ───────────────────────────────────
    # Get the block from "object Foo" to the next "object|class" or EOF
    local obj_start obj_end obj_block
    obj_start="$(echo "${content}" | grep -n "^object ${class_name}\|^class ${class_name}" | head -1 | cut -d: -f1)"
    if [[ -z "${obj_start}" ]]; then
        # Try with abstract prefix
        obj_start="$(echo "${content}" | grep -n "object ${class_name}\|class ${class_name}" | head -1 | cut -d: -f1)"
    fi

    if [[ -n "${obj_start}" ]]; then
        # Find next top-level object/class declaration after obj_start
        obj_end="$(echo "${content}" | awk -v start="${obj_start}" 'NR>start && /^(object|class|abstract|fun )/ {print NR; exit}')"
        [[ -z "${obj_end}" ]] && obj_end="$(echo "${content}" | wc -l | tr -d ' ')"
        obj_block="$(echo "${content}" | sed -n "${obj_start},${obj_end}p")"
    else
        obj_block="${content}"
    fi

    # ── canSolve() block ────────────────────────────────────────────────
    local can_solve_block=""
    can_solve_block="$(echo "${obj_block}" | awk '/override fun canSolve/,/^    \}/' | head -40)"

    # ── Domains extraction ──────────────────────────────────────────────
    local domains_tmp="/tmp/cpal-domains-${class_name}-$$"
    : > "${domains_tmp}"

    # 1. val domains = setOf("a", "b") inside the object
    echo "${obj_block}" | awk '/val domains[[:space:]]*=[[:space:]]*setOf/,/\)/' | grep -oE '"[^"]+"' | tr -d '"' | sort -u >> "${domains_tmp}"

    # 2. host == "domain" from canSolve
    echo "${can_solve_block}" | grep -oE 'host[[:space:]]*==[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u >> "${domains_tmp}"

    # 3. host in ... (uses val domains above — already handled)
    #    No additional extraction needed.

    # 4. Wildcard domain patterns
    echo "${can_solve_block}" | grep -ioE '\*\.[a-z0-9._-]+' | sort -u >> "${domains_tmp}"

    # 5. url.host == "domain"
    echo "${can_solve_block}" | grep -oE '\.host[[:space:]]*==[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u >> "${domains_tmp}"

    # 6. host.endsWith("domain") — convert to wildcard *.domain
    echo "${can_solve_block}" | grep -oE '\.endsWith\("[^"]+"\)' | grep -oE '"[^"]*"' | tr -d '"' | sed 's/^\.//' | while IFS= read -r d; do
        [[ -n "${d}" ]] && echo "*.${d}"
    done >> "${domains_tmp}"

    # 7. host.contains("domain") — extract
    echo "${can_solve_block}" | grep -oE '\.contains\("[^"]+"\)' | grep -oE '"[^"]*"' | tr -d '"' | sort -u >> "${domains_tmp}"

    # 8. Extract domains from helper functions in the same object
    echo "${obj_block}" | grep -oE '\.endsWith\("[^"]+"\)' | grep -oE '"[^"]*"' | tr -d '"' | sed 's/^\.//' | while IFS= read -r d; do
        [[ -n "${d}" ]] && echo "*.${d}"
    done >> "${domains_tmp}"
    echo "${obj_block}" | grep -oE '\.host[[:space:]]*(==|contains)[[:space:]]*\("[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u >> "${domains_tmp}"

    # Deduplicate and clean
    sort -u "${domains_tmp}" > "${domains_tmp}.dedup" 2>/dev/null || : > "${domains_tmp}.dedup"
    mv "${domains_tmp}.dedup" "${domains_tmp}"

    # ── Paths extraction ────────────────────────────────────────────────
    local paths_tmp="/tmp/cpal-paths-${class_name}-$$"
    : > "${paths_tmp}"
    echo "${can_solve_block}" | grep -oE 'encodedPath[[:space:]]*==[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u > "${paths_tmp}"
    echo "${can_solve_block}" | grep -oE 'firstPathSegment[[:space:]]*==[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | sort -u >> "${paths_tmp}" 2>/dev/null || true
    sort -u "${paths_tmp}" -o "${paths_tmp}" 2>/dev/null || true

    # ── Ports ───────────────────────────────────────────────────────────
    local ports_tmp="/tmp/cpal-ports-${class_name}-$$"
    : > "${ports_tmp}"
    echo "${obj_block}" | grep -ioE 'port[^0-9]*[0-9]{2,5}' | grep -oE '[0-9]{2,5}' | sort -u > "${ports_tmp}" 2>/dev/null || true

    # ── SSIDs: find @SSID block closest before this object ──────────────
    local ssids_tmp="/tmp/cpal-ssids-${class_name}-$$"
    : > "${ssids_tmp}"
    # Extract SSIDs from the @SSID annotation that appears before this object
    # For multi-object files, only take SSIDs between last object and this one
    if [[ -n "${obj_start}" ]]; then
        echo "${content}" | head -$((obj_start - 1)) | awk '/@SSID\(/,/\)/' | grep -oE '"[^"]+"' | tr -d '"' | sort -u > "${ssids_tmp}"
    else
        echo "${content}" | awk '/@SSID\(/,/\)/' | grep -oE '"[^"]+"' | tr -d '"' | sort -u > "${ssids_tmp}"
    fi

    # ── solve() block ───────────────────────────────────────────────────
    local solve_block=""
    solve_block="$(echo "${obj_block}" | awk '/override fun solve/,/^    \}/' | head -300)"

    # Detect patterns
    local flags=""
    echo "${solve_block}" | grep -qi 'submitOnlyForm'     && flags="${flags}S"
    echo "${solve_block}" | grep -qi 'postForm\|postFormUrlEncoded' && flags="${flags}P"
    echo "${solve_block}" | grep -qi 'JSONObject\|JSONArray\|parseJsonObject\|postJson\|\.getInt\|\.getString\|parseJson' && flags="${flags}J"
    echo "${solve_block}" | grep -qi 'hexMD5\|chap\|CHAP\|md5'       && flags="${flags}C"
    echo "${solve_block}" | grep -qi 'grant_url\|base_grant_url\|grantUrl\|isNetworkAuthGrantUrl' && flags="${flags}G"
    echo "${solve_block}" | grep -qi 'csrf\|CSRF\|CSRFToken'         && flags="${flags}F"
    echo "${solve_block}" | grep -qi 'window\.location\|location\.href\|location\.replace' && flags="${flags}R"
    echo "${solve_block}" | grep -qi 'cookie\|Cookie\|\.cookies'     && flags="${flags}K"

    local has_form="no" has_json="no" has_chap="no" has_grant="no"
    local has_csrf="no" has_jsredir="no"
    [[ "${flags}" == *S* || "${flags}" == *P* ]] && has_form="yes"
    [[ "${flags}" == *J* ]] && has_json="yes"
    [[ "${flags}" == *C* ]] && has_chap="yes"
    [[ "${flags}" == *G* ]] && has_grant="yes"
    [[ "${flags}" == *F* ]] && has_csrf="yes"
    [[ "${flags}" == *R* ]] && has_jsredir="yes"

    # Credentials
    local creds="none"
    echo "${solve_block}" | grep -qiE 'username|password|getCredentials' && creds="username_password"

    # Complexity
    local solve_lines
    solve_lines="$(echo "${solve_block}" | wc -l | tr -d ' ')"

    # ── Step 3: Classify ────────────────────────────────────────────────
    local auth_type="needs-custom"
    local confidence="low"

    if [[ "${has_chap}" == "yes" ]]; then
        auth_type="chap-md5"; confidence="high"
    elif [[ "${has_csrf}" == "yes" && "${has_form}" == "yes" ]]; then
        auth_type="csrf-form-submit"; confidence="medium"
    elif [[ "${has_grant}" == "yes" && "${has_form}" == "no" && "${has_json}" == "no" ]]; then
        auth_type="click-through-grant"; confidence="high"
    elif [[ "${has_jsredir}" == "yes" && "${has_form}" == "no" && "${has_json}" == "no" ]]; then
        auth_type="js-redirect"; confidence="medium"
    elif [[ "${has_json}" == "yes" && "${has_form}" == "no" ]]; then
        auth_type="json-api"
        if [[ "${solve_lines}" -lt 60 ]]; then confidence="high"
        elif [[ "${solve_lines}" -lt 100 ]]; then confidence="medium"
        else confidence="low"; fi
    elif [[ "${has_form}" == "yes" && "${has_json}" == "no" ]]; then
        auth_type="form-submit"
        if [[ "${solve_lines}" -lt 50 ]]; then confidence="high"
        elif [[ "${solve_lines}" -lt 90 ]]; then confidence="medium"
        else confidence="low"; fi
    elif [[ "${has_form}" == "yes" && "${has_json}" == "yes" ]]; then
        auth_type="json-api"; confidence="low"
    fi

    # ── Needs custom? ───────────────────────────────────────────────────
    if [[ "${auth_type}" == "needs-custom" ]]; then
        NEEDS_CUSTOM=$((NEEDS_CUSTOM+1))
        # Check if existing recipe covers this handler anyway
        local _covered=""
        for _rfile in "${RECIPE_DIR}"/*.json; do
            [[ -f "${_rfile}" ]] || continue
            if domains_match_existing "${domains_tmp}" "${_rfile}"; then
                _covered="$(basename "${_rfile}" .json)"
                break
            fi
        done
        if [[ -n "${_covered}" ]]; then
            ALREADY_COVERED=$((ALREADY_COVERED+1))
            echo "${_covered}: covers ${class_name} (needs-custom) ✓" >> "${REPORT_CONFLICT}"
        else
            echo "${class_name} (${base}.kt)" >> "${REPORT_CUSTOM}"
        fi
        rm -f "${domains_tmp}" "${paths_tmp}" "${ports_tmp}" "${ssids_tmp}"
        return 0
    fi

    # ── Step 4: Build recipe JSON ───────────────────────────────────────
    local rid
    rid="$(echo "${class_name}" | sed -E 's/([A-Z])/-\1/g; s/^-//' | tr '[:upper:]' '[:lower:]')"

    # Primary domain — prefer non-wildcard, shortest meaningful domain
    local primary_domain=""
    primary_domain="$(grep -v '^\*\.' "${domains_tmp}" | awk '{print length, $0}' | sort -n | head -1 | awk '{print $2}')"
    [[ -z "${primary_domain}" ]] && primary_domain="$(awk '{print length, $0}' "${domains_tmp}" | sort -n | head -1 | awk '{print $2}')"

    # Fallback domains
    local fb_domains=""
    while IFS= read -r d; do
        [[ -z "${d}" ]] && continue
        [[ "${d}" == "${primary_domain}" ]] && continue
        fb_domains="${fb_domains}, \"$(json_escape "${d}")\""
    done < "${domains_tmp}"
    fb_domains="${fb_domains#, }"

    # Match domains
    local match_domains=""
    while IFS= read -r d; do
        [[ -z "${d}" ]] && continue
        match_domains="${match_domains}, \"$(json_escape "${d}")\""
    done < "${domains_tmp}"
    match_domains="${match_domains#, }"

    # SSIDs
    local ssids_json=""
    while IFS= read -r s; do
        [[ -z "${s}" ]] && continue
        ssids_json="${ssids_json}, \"$(json_escape "${s}")\""
    done < "${ssids_tmp}"
    ssids_json="${ssids_json#, }"

    # Ports
    local ports_json=""
    while IFS= read -r p; do
        [[ -z "${p}" ]] && continue
        ports_json="${ports_json}, \"$(json_escape "${p}")\""
    done < "${ports_tmp}"
    ports_json="${ports_json#, }"

    # Paths
    local paths_json=""
    while IFS= read -r p; do
        [[ -z "${p}" ]] && continue
        paths_json="${paths_json}, \"$(json_escape "${p}")\""
    done < "${paths_tmp}"
    paths_json="${paths_json#, }"

    # Auth-type params
    local params_block=""
    case "${auth_type}" in
        form-submit)
            params_block='{"form_page_url": "${trm_captiveurl}", "submit_method": "POST", "success_check": "empty_body"}'
            ;;
        csrf-form-submit)
            params_block='{"csrf_source": "cookie", "success_check": "empty_body"}'
            ;;
        click-through-grant)
            params_block='{"grant_url_source": "redirect_url", "grant_url_extract": "query_param", "grant_method": "GET", "success_check": "empty_body"}'
            ;;
        json-api)
            params_block='{"success_check": "empty_body"}'
            ;;
        chap-md5)
            params_block='{"chap_detect": "hexMD5", "form_action": "/login", "username_field": "username", "response_field": "password", "success_check": "empty_body"}'
            ;;
        js-redirect)
            params_block='{"follow_redirect": "true"}'
            ;;
        *)
            params_block='{}'
            ;;
    esac

    # Assemble recipe
    local recipe
    recipe=$(cat <<RECIPE_EOF
{
  "id": "$(json_escape "${rid}")",
  "name": "$(json_escape "${class_name}") (Auto-imported)",
  "travelmate_domain": "$(json_escape "${primary_domain}")",
  "fallback_domains": [${fb_domains}],
  "auth_type": "$(json_escape "${auth_type}")",
  "credentials": "$(json_escape "${creds}")",
  "params": ${params_block},
  "source": {
    "project": "CaptivePortalAutoLogin",
    "handler": "$(json_escape "${class_name}")",
    "url": "https://github.com/binarynoise/CaptivePortalAutoLogin/blob/main/liberator/src/main/kotlin/de/binarynoise/liberator/portals/${base}.kt",
    "license": "GPL-3.0",
    "imported_date": "${TODAY}",
    "confidence": "$(json_escape "${confidence}")"
  },
  "match": {
    "domains": [${match_domains}],
    "ssids": [${ssids_json}],
    "ports": [${ports_json}],
    "paths": [${paths_json}]
  }
}
RECIPE_EOF
)

    # ── Step 5: Compare with existing ───────────────────────────────────
    local existing_file="" existing_id=""

    if [[ -f "${RECIPE_DIR}/${rid}.json" ]]; then
        existing_file="${RECIPE_DIR}/${rid}.json"
        existing_id="${rid}"
    else
        for recipe_file in "${RECIPE_DIR}"/*.json; do
            [[ -f "${recipe_file}" ]] || continue
            if domains_match_existing "${domains_tmp}" "${recipe_file}"; then
                existing_file="${recipe_file}"
                existing_id="$(basename "${recipe_file}" .json)"
                break
            fi
        done
    fi

    if [[ -n "${existing_file}" ]]; then
        ALREADY_COVERED=$((ALREADY_COVERED+1))

        local existing_auth existing_td
        existing_auth="$(grep -o '"auth_type"[[:space:]]*:[[:space:]]*"[^"]*"' "${existing_file}" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
        existing_td="$(grep -o '"travelmate_domain"[[:space:]]*:[[:space:]]*"[^"]*"' "${existing_file}" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"

        local conflict=""
        [[ "${existing_auth}" != "${auth_type}" ]] && conflict="auth_type mismatch: importer=${auth_type} vs existing=${existing_auth}"
        if [[ "${existing_td}" != "${primary_domain}" && -n "${primary_domain}" ]]; then
            [[ -n "${conflict}" ]] && conflict="${conflict}; "
            conflict="${conflict}domain: importer=${primary_domain} vs existing=${existing_td}"
        fi

        if [[ -n "${conflict}" ]]; then
            echo "${existing_id}: ${conflict} — review" >> "${REPORT_CONFLICT}"
        else
            echo "${existing_id}: matches existing recipe ✓" >> "${REPORT_CONFLICT}"
        fi

        if [[ "${FORCE}" -eq 1 && "${COMPARE_ONLY}" -eq 0 ]]; then
            mkdir -p "${OUTPUT_DIR}"
            echo "${recipe}" > "${OUTPUT_DIR}/${rid}.json"
            NEW_RECIPES=$((NEW_RECIPES+1))
            echo "${rid}.json (auth_type: ${auth_type}, confidence: ${confidence}) — OVERWRITE" >> "${REPORT_NEW}"
            log "Overwrote: ${rid}.json"
        fi
    else
        local out_name="IMPORT_${rid}.json"
        [[ "${FORCE}" -eq 1 ]] && out_name="${rid}.json"

        if [[ "${COMPARE_ONLY}" -eq 0 ]]; then
            mkdir -p "${OUTPUT_DIR}"
            echo "${recipe}" > "${OUTPUT_DIR}/${out_name}"
            log "Generated: ${out_name}"
        fi
        NEW_RECIPES=$((NEW_RECIPES+1))
        echo "${out_name} (auth_type: ${auth_type}, confidence: ${confidence})" >> "${REPORT_NEW}"
    fi

    rm -f "${domains_tmp}" "${paths_tmp}" "${ports_tmp}" "${ssids_tmp}"
}

# ── Step 6: Report ──────────────────────────────────────────────────────────
print_report() {
    echo ""
    echo "Import Report"
    echo "============="
    echo "Handlers scanned:    ${SCANNED}"
    echo "Already covered:     ${ALREADY_COVERED} (existing recipes match)"
    echo "New recipes:         ${NEW_RECIPES}"
    echo "Needs custom code:   ${NEEDS_CUSTOM}"
    echo "Import failures:     ${IMPORT_FAILURES}"
    echo ""

    local section
    for section in "New recipes:${REPORT_NEW}" "Conflicts with existing:${REPORT_CONFLICT}" "Needs custom code:${REPORT_CUSTOM}" "Import failures:${REPORT_FAILURE}"; do
        local label="${section%%:*}"
        local file="${section#*:}"
        if [[ -s "${file}" ]]; then
            echo "${label}:"
            while IFS= read -r line; do
                echo "  - ${line}"
            done < "${file}"
            echo ""
        fi
    done
}

# ── main ────────────────────────────────────────────────────────────────────
main() {
    echo "import-cpal.sh — CPAL handler importer"
    echo "========================================"

    fetch_cpal

    if [[ ! -d "${HANDLERS_DIR}" ]]; then
        err "Handlers directory not found: ${HANDLERS_DIR}"
        err "Check that the repo structure matches liberator/src/main/kotlin/de/binarynoise/liberator/portals/"
        exit 1
    fi

    echo "Scanning handlers in ${HANDLERS_DIR} ..."
    echo ""

    local handler_files=""
    if [[ -n "${SINGLE_HANDLER}" ]]; then
        local found=0
        for kt in "${HANDLERS_DIR}"/*.kt; do
            [[ -f "${kt}" ]] || continue
            if echo "${kt}" | grep -qi "${SINGLE_HANDLER}" || grep -q "object ${SINGLE_HANDLER} " "${kt}" 2>/dev/null; then
                handler_files="${kt}"
                found=1
                break
            fi
        done
        if [[ "${found}" -eq 0 ]]; then
            err "Handler '${SINGLE_HANDLER}' not found in ${HANDLERS_DIR}/"
            exit 1
        fi
    else
        handler_files="$(find "${HANDLERS_DIR}" -maxdepth 1 -name '*.kt' -type f | sort)"
    fi

    local kt_file
    while IFS= read -r kt_file; do
        [[ -z "${kt_file}" ]] && continue
        process_handler "${kt_file}" || true
    done <<< "${handler_files}"

    print_report
}

main "$@"
