#!/bin/sh
# mock-travelmate.sh - Mock travelmate environment for testing
# Source this before running compiled .login scripts
#shellcheck disable=all

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_BIN="${TEST_DIR}/mock-bin"

# ── travelmate variables ──
export trm_bver="99.99.99"
export trm_fetch="${MOCK_BIN}/mock-curl"
export trm_fetchparm="-sS -L --max-time 10"
export trm_useragent="Mozilla/5.0 (test) travelmate-test"
export trm_captiveurl="http://captive.apple.com"
export trm_awkcmd="awk"
export trm_jsoncmd="${MOCK_BIN}/mock-jsonfilter"
export trm_lookupcmd="${MOCK_BIN}/mock-nslookup"
export trm_domain=""

# ── BASH_ENV injection for md5sum (needed by CHAP scripts) ──
# /bin/sh on macOS is bash, so BASH_ENV is sourced before scripts run
# This injects md5sum as a function since scripts override PATH
MOCK_ENV_FILE="/tmp/mock-travelmate-env-$$.sh"
cat > "${MOCK_ENV_FILE}" << 'ENVEOF'
md5sum() {
	if [ -x /usr/local/bin/md5sum ]; then
		/usr/local/bin/md5sum
	elif [ -x /opt/homebrew/bin/md5sum ]; then
		/opt/homebrew/bin/md5sum
	else
		/sbin/md5 -r | /usr/bin/awk '{print $1}'
	fi
}
ENVEOF
export BASH_ENV="${MOCK_ENV_FILE}"

# ── Call counter reset ──
mock_reset_counter() {
	echo "0" > /tmp/mock-curl-counter
}

# ── Cleanup ──
mock_cleanup() {
	rm -f /tmp/mock-curl-counter
	rm -f /tmp/mock-travelmate-env-$$.sh
	rm -f /tmp/*.cookie /tmp/*.cookies 2>/dev/null
}
