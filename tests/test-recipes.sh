#!/bin/sh
# test-recipes.sh - Test runner for compiled .login scripts
# Runs all 44 recipes with mock travelmate environment
#shellcheck disable=all

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPILE_DIR="/tmp/recipe-compile-test"

# ── Options ──
VERBOSE=0
STOP_ON_FAIL=0
SPECIFIC_RECIPE=""

while [ $# -gt 0 ]; do
	case "$1" in
		-v|--verbose) VERBOSE=1; shift ;;
		-x|--stop) STOP_ON_FAIL=1; shift ;;
		-h|--help)
			echo "Usage: $0 [-v] [-x] [recipe_name | test_dir]"
			echo "  -v    Verbose: show mock HTTP traffic"
			echo "  -x    Stop on first failure"
			echo "  recipe_name   Run only this recipe"
			echo "  test_dir       Directory with .login scripts (default: /tmp/recipe-compile-test)"
			exit 0
			;;
		-*) echo "Unknown option: $1" >&2; exit 1 ;;
		*)
			if [ -d "$1" ]; then
				COMPILE_DIR="$1"
			else
				SPECIFIC_RECIPE="$1"
			fi
			shift
			;;
	esac
done

if [ ! -d "${COMPILE_DIR}" ]; then
	echo "Error: compiled scripts directory not found: ${COMPILE_DIR}" >&2
	exit 1
fi

# ── Source mock environment ──
. "${SCRIPT_DIR}/mock-travelmate.sh"

if [ "${VERBOSE}" = 1 ]; then
	export MOCK_VERBOSE=1
fi

# ── Determine which scripts to test ──
if [ -n "${SPECIFIC_RECIPE}" ]; then
	SCRIPTS="${COMPILE_DIR}/${SPECIFIC_RECIPE}.login"
	if [ ! -f "${SCRIPTS}" ]; then
		echo "Error: ${SCRIPTS} not found" >&2
		exit 1
	fi
else
	SCRIPTS=$(ls "${COMPILE_DIR}"/*.login 2>/dev/null | sort)
fi

if [ -z "${SCRIPTS}" ]; then
	echo "Error: no .login scripts found in ${COMPILE_DIR}" >&2
	exit 1
fi

# ── Detect auth_type from compiled script ──
detect_auth_type() {
	_script="$1"
	_name="$(head -2 "${_script}" | grep -o 'for [^(]*' | sed 's/for //')"
	if grep -q 'hexMD5' "${_script}" 2>/dev/null; then
		echo "chap-md5"
	elif grep -q 'window\.location\|location\.replace\|location\.href' "${_script}" 2>/dev/null; then
		echo "js-redirect"
	elif grep -q 'base_grant_url\|%%GRANT_URL_PARAM%%' "${_script}" 2>/dev/null || grep -q 'write-out.*redirect_url' "${_script}" 2>/dev/null; then
		if grep -q 'step_html\|step2\|step3' "${_script}" 2>/dev/null; then
			echo "multi-step-form"
		else
			echo "click-through-grant"
		fi
	elif grep -q 'cookie-jar\|COOKIE_JAR\|cookie_jar' "${_script}" 2>/dev/null; then
		if grep -q 'CSRFToken\|csrf\|sec_token' "${_script}" 2>/dev/null; then
			echo "csrf-form-submit"
		else
			echo "cookie-chain"
		fi
	elif grep -q 'trm_jsoncmd\|jsonfilter' "${_script}" 2>/dev/null; then
		echo "json-api"
	elif grep -q 'form_html\|hidden_fields' "${_script}" 2>/dev/null; then
		echo "form-submit"
	else
		echo "unknown"
	fi
}

# ── Run tests ──
PASS=0
FAIL=0
FAIL_LIST=""
TOTAL=0

# Print header
printf "%-28s %-22s %4s %6s\n" "RECIPE" "AUTH_TYPE" "EXIT" "STATUS"
printf "%-28s %-22s %4s %6s\n" "-------" "---------" "----" "------"

for script in ${SCRIPTS}; do
	recipe_name="$(basename "${script}" .login)"
	auth_type="$(detect_auth_type "${script}")"
	TOTAL=$((TOTAL + 1))

	# Set recipe name for mock-curl
	export MOCK_RECIPE="${recipe_name}"

	# Reset mock call counter
	mock_reset_counter

	# Run the script
	if [ "${VERBOSE}" = 1 ]; then
		echo "--- Running: ${recipe_name} ---" >&2
	fi

	exit_code=0
	if [ "${VERBOSE}" = 1 ]; then
		sh "${script}" >/dev/null || exit_code=$?
	else
		sh "${script}" >/dev/null 2>&1 || exit_code=$?
	fi

	# Determine expected result
	# All scripts should exit 0 (success) in our mock environment
	if [ "${exit_code}" = 0 ]; then
		status="PASS"
		PASS=$((PASS + 1))
	else
		status="FAIL"
		FAIL=$((FAIL + 1))
		FAIL_LIST="${FAIL_LIST} ${recipe_name}(exit=${exit_code})"
		if [ "${VERBOSE}" = 1 ]; then
			echo "  FAILED: ${recipe_name} with exit code ${exit_code}" >&2
			# Re-run with output for debugging
			mock_reset_counter
			sh "${script}" 2>&1 || true
		fi
	fi

	printf "%-28s %-22s %4d %6s\n" "${recipe_name}" "${auth_type}" "${exit_code}" "${status}"

	if [ "${STOP_ON_FAIL}" = 1 ] && [ "${status}" = "FAIL" ]; then
		echo ""
		echo "Stopping on first failure: ${recipe_name}"
		break
	fi
done

# ── Summary ──
echo ""
echo "════════════════════════════════════════════"
printf "Total: %d  Pass: %d  Fail: %d\n" "${TOTAL}" "${PASS}" "${FAIL}"
if [ "${FAIL}" -gt 0 ]; then
	echo "Failed: ${FAIL_LIST}"
fi
echo "════════════════════════════════════════════"

# Cleanup
mock_cleanup

[ "${FAIL}" = 0 ] && exit 0 || exit 1
