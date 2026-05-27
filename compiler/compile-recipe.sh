#!/bin/sh
# Usage: ./compile-recipe.sh <recipe.json> [-o <output.login>] [-t <template-dir>] [--target <name>]
#        ./compile-recipe.sh --list-targets [-t <template-dir>]
#        ./compile-recipe.sh --help
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates"
TARGET="travelmate"
OUTPUT_FILE=""
RECIPE_FILE=""
LIST_TARGETS=0
SHOW_HELP=0

show_usage() {
	echo "usage: $(basename "$0") <recipe.json> [-o <output>] [-t <template-dir>] [--target <name>]"
	echo "       $(basename "$0") --list-targets [-t <template-dir>]"
	echo "       $(basename "$0") --help"
	echo ""
	echo "Options:"
	echo "  -o <output>        Output file path (default: <recipe-id>.login)"
	echo "  -t <template-dir>  Base template directory (default: <script-dir>/../templates)"
	echo "  --target <name>    Compilation target (default: travelmate)"
	echo "  --list-targets     List available targets"
	echo "  --help             Show this help text"
	echo ""
	echo "Available targets:"
	_targets_dir="${TEMPLATE_DIR}/targets"
	if [ -d "${_targets_dir}" ]; then
		for _td in "${_targets_dir}"/*/; do
			[ -d "${_td}" ] && printf '  %s\n' "$(basename "${_td}")"
		done
	else
		echo "  (none found)"
	fi
}

while [ $# -gt 0 ]; do
	case "$1" in
		-o) OUTPUT_FILE="$2"; shift 2 ;;
		-t) TEMPLATE_DIR="$2"; shift 2 ;;
		--target) TARGET="$2"; shift 2 ;;
		--list-targets) LIST_TARGETS=1; shift ;;
		--help) SHOW_HELP=1; shift ;;
		-*) echo "usage: $(basename "$0") <recipe.json> [-o <output>] [-t <template-dir>] [--target <name>]" >&2; exit 1 ;;
		*) [ -z "${RECIPE_FILE}" ] && { RECIPE_FILE="$1"; shift; } || { echo "error: unexpected '$1'" >&2; exit 1; } ;;
	esac
done

if [ "${SHOW_HELP}" = "1" ]; then
	show_usage
	exit 0
fi

if [ "${LIST_TARGETS}" = "1" ]; then
	_targets_dir="${TEMPLATE_DIR}/targets"
	if [ ! -d "${_targets_dir}" ]; then
		echo "error: no targets directory: ${_targets_dir}" >&2; exit 1
	fi
	_found=0
	for _td in "${_targets_dir}"/*/; do
		[ -d "${_td}" ] && { printf '%s\n' "$(basename "${_td}")"; _found=1; }
	done
	[ "${_found}" = "0" ] && { echo "error: no targets found" >&2; exit 1; }
	exit 0
fi

[ -z "${RECIPE_FILE}" ] && { show_usage >&2; exit 1; }
[ ! -f "${RECIPE_FILE}" ] && { echo "error: not found: ${RECIPE_FILE}" >&2; exit 1; }

# Validate target
TARGETS_DIR="${TEMPLATE_DIR}/targets"
if [ ! -d "${TARGETS_DIR}/${TARGET}" ]; then
	echo "error: unknown target '${TARGET}'" >&2
	echo "available targets:" >&2
	if [ -d "${TARGETS_DIR}" ]; then
		for _td in "${TARGETS_DIR}"/*/; do
			[ -d "${_td}" ] && echo "  $(basename "${_td}")" >&2
		done
	else
		echo "  (none found)" >&2
	fi
	exit 1
fi

# ── JSON extraction via awk ─────────────────────────────────────────
json_get() {
	_key="$1"
	awk -v k="\"${_key}\"" '
		{ gsub(/[[:space:]]+/, " "); line = line " " $0 }
		END {
			pos = index(line, k); if (pos == 0) exit 1
			rest = substr(line, pos + length(k))
			sub(/^[[:space:]]*:[[:space:]]*/, "", rest)
			if (substr(rest,1,1) == "\"") {
				rest = substr(rest,2); result = ""; i = 1
				while (i <= length(rest)) {
					c = substr(rest, i, 1)
					if (c == "\\" && substr(rest, i+1, 1) == "\"") { result = result "\""; i = i + 2 }
					else if (c == "\"") { break }
					else { result = result c; i = i + 1 }
				}
				print result
			} else { sub(/[,[:space:]].*$/,"",rest); print rest }
		}
	' "${RECIPE_FILE}"
}

json_get_nested() {
	_fullkey="$1"; _obj="${_fullkey%%.*}"; _key="${_fullkey#*.}"
	awk -v obj="\"${_obj}\"" -v k="\"${_key}\"" '
		{ gsub(/[[:space:]]+/, " "); line = line " " $0 }
		END {
			opos = index(line,obj); if (opos == 0) exit 1
			rest = substr(line,opos)
			bstart = index(rest,"{"); if (bstart == 0) exit 1
			rest = substr(rest,bstart); depth=0; obj_body=""
			for (i=1;i<=length(rest);i++) {
				c=substr(rest,i,1); obj_body=obj_body c
				if (c=="{") depth++; else if (c=="}") { depth--; if (depth==0) break }
			}
			kpos = index(obj_body,k); if (kpos == 0) exit 1
			krest = substr(obj_body,kpos+length(k))
			sub(/^[[:space:]]*:[[:space:]]*/,"",krest)
			if (substr(krest,1,1)=="\"") {
				krest=substr(krest,2); result=""; i=1
				while (i<=length(krest)) {
					c=substr(krest,i,1)
					if (c=="\\" && substr(krest,i+1,1)=="\"") { result=result "\""; i=i+2 }
					else if (c=="\"") { break }
					else { result=result c; i=i+1 }
				}
				print result
			} else { sub(/[,[:space:]].*$/,"",krest); print krest }
		}
	' "${RECIPE_FILE}"
}

json_get_array() {
	_key="$1"
	awk -v k="\"${_key}\"" '
		{ gsub(/[[:space:]]+/, " "); line = line " " $0 }
		END {
			pos = index(line,k); if (pos == 0) exit 1
			rest = substr(line,pos+length(k))
			sub(/^[[:space:]]*:[[:space:]]*/,"",rest)
			if (substr(rest,1,1) != "[") exit 1
			rest = substr(rest,2)
			b = index(rest,"]")
			if (b > 0) rest = substr(rest,1,b-1)
			n = split(rest,parts,"\"")
			for (i=2;i<=n;i+=2) print parts[i]
		}
	' "${RECIPE_FILE}"
}

# ── Read recipe ─────────────────────────────────────────────────────
recipe_id="$(json_get "id" 2>/dev/null || true)"
recipe_name="$(json_get "name" 2>/dev/null || true)"
recipe_domain="$(json_get "travelmate_domain" 2>/dev/null || true)"
auth_type="$(json_get "auth_type" 2>/dev/null || true)"

[ -z "${recipe_id}" ] || [ -z "${recipe_name}" ] || [ -z "${recipe_domain}" ] || [ -z "${auth_type}" ] && {
	echo "error: missing required fields" >&2; exit 1; }

TEMPLATE_FILE="${TEMPLATE_DIR}/targets/${TARGET}/${auth_type}.sh.template"
[ ! -f "${TEMPLATE_FILE}" ] && { echo "error: no template for '${auth_type}' (target: ${TARGET})" >&2; exit 1; }
[ -z "${OUTPUT_FILE}" ] && OUTPUT_FILE="${recipe_id}.login"

# ── Substitution engine ─────────────────────────────────────────────
SUBST_DIR="/tmp/rc-subst.$$"
mkdir -p "${SUBST_DIR}"
trap 'rm -rf "${SUBST_DIR}"' EXIT

_subst_count=0
subst() {
	_subst_count=$((_subst_count + 1))
	printf '%s' "$1" | awk -F'\t' 'NR==1{printf "%s",$1}' > "${SUBST_DIR}/${_subst_count}.ph"
	printf '%s' "$1" | awk 'NR==1{sub(/^[^\t]*\t/,"")} {printf "%s%s",(NR>1?"\n":""),$0}' > "${SUBST_DIR}/${_subst_count}.val"
}

subst_file() {
	_ph="$1"
	_vf="$2"
	_subst_count=$((_subst_count + 1))
	printf '%s' "${_ph}" > "${SUBST_DIR}/${_subst_count}.ph"
	cp "${_vf}" "${SUBST_DIR}/${_subst_count}.val"
}

apply_substs() {
	cp "${TEMPLATE_FILE}" "${OUTPUT_FILE}"
	for _sf in "${SUBST_DIR}"/*.ph; do
		[ -f "${_sf}" ] || continue
		_base="${_sf%.ph}"
		_ph="$(cat "${_sf}")"
		_vf="${_base}.val"
		awk -v ph="${_ph}" -v vf="${_vf}" '
			BEGIN { val = ""; sep = ""; while ((getline l < vf) > 0) { val = val sep l; sep = ORS }; close(vf) }
			{
				line = $0
				while ((pos = index(line, ph)) > 0) {
					line = substr(line, 1, pos-1) val substr(line, pos + length(ph))
				}
				printf "%s\n", line
			}
		' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
		mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
	done
}

# ── Shared helpers ──────────────────────────────────────────────────

subst_common() {
	subst "%%NAME%%	${recipe_name}"
	subst "%%ID%%	${recipe_id}"
	subst "%%DOMAIN%%	${recipe_domain}"
	subst "%%CREDENTIAL_SETUP%%	$(gen_credential_setup)"
	subst "%%FALLBACK_DOMAINS%%	$(gen_fallback_domains)"
}

apply_common_finish() {
	subst "%%SUCCESS_CHECK%%	$(gen_success_check)"
	apply_substs
}

# Generate awk extraction lines from comma-separated varname:awkcode spec
# Usage: gen_awk_extracts <spec> <source_var> <outfile> <tmp_prefix>
gen_awk_extracts() {
	_ea_spec="$1"
	_ea_source="$2"
	_ea_outfile="$3"
	_ea_prefix="$4"
	[ -z "${_ea_spec}" ] && return
	_oldifs="${IFS}"; IFS=','
	_oldglob="$(set +o | grep noglob)" 2>/dev/null || true
	set -f
	for _ext in ${_ea_spec}; do
		_varname="${_ext%%:*}"; _awk_code="${_ext#*:}"
		[ -z "${_varname}" ] || [ -z "${_awk_code}" ] && continue
		_ext_tmp="${SUBST_DIR}/${_ea_prefix}_${_varname}"
		cat << 'AWKEXTEOF' > "${_ext_tmp}"
__EXT_VAR__="$(printf "%s" "${__EXT_SRC__}" 2>/dev/null | "${trm_awkcmd}" '__EXT_AWK__')"
AWKEXTEOF
		marker_subst "__EXT_VAR__" "${_varname}" "${_ext_tmp}"
		marker_subst "__EXT_SRC__" "${_ea_source}" "${_ext_tmp}"
		marker_subst "__EXT_AWK__" "${_awk_code}" "${_ext_tmp}"
		cat "${_ext_tmp}" >> "${_ea_outfile}"
	done
	set +f
	eval "${_oldglob}" 2>/dev/null || true
	IFS="${_oldifs}"
}

# Generate jsonfilter extraction lines from comma-separated varname:jsonpath spec
# Usage: gen_json_extracts <spec> <source_var> <outfile> <tmp_prefix>
gen_json_extracts() {
	_ej_spec="$1"
	_ej_source="$2"
	_ej_outfile="$3"
	_ej_prefix="$4"
	[ -z "${_ej_spec}" ] && return
	_oldifs="${IFS}"; IFS=','
	_oldglob="$(set +o | grep noglob)" 2>/dev/null || true
	set -f
	for _ext in ${_ej_spec}; do
		_varname="${_ext%%:*}"; _jsonpath="${_ext#*:}"
		[ -z "${_varname}" ] || [ -z "${_jsonpath}" ] && continue
		_ext_tmp="${SUBST_DIR}/${_ej_prefix}_${_varname}"
		cat << 'JSONEXTEOF' > "${_ext_tmp}"
__EXT_VAR__="$(printf "%s" "${__EXT_SRC__}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '__EXT_JSON__')"
JSONEXTEOF
		marker_subst "__EXT_VAR__" "${_varname}" "${_ext_tmp}"
		marker_subst "__EXT_SRC__" "${_ej_source}" "${_ext_tmp}"
		marker_subst "__EXT_JSON__" "${_jsonpath}" "${_ext_tmp}"
		cat "${_ext_tmp}" >> "${_ej_outfile}"
	done
	set +f
	eval "${_oldglob}" 2>/dev/null || true
	IFS="${_oldifs}"
}

# ── Generators ──────────────────────────────────────────────────────
TAB="$(printf '\t')"

# Safe marker substitution using awk index/substr (no regex, no & issues)
marker_subst() {
	_marker="$1" _value="$2" _file="$3"
	_vf="${SUBST_DIR}/ms_$$_${_marker}"
	printf '%s' "${_value}" > "${_vf}"
	awk -v m="${_marker}" -v vf="${_vf}" '
		BEGIN { val = ""; sep = ""; while ((getline l < vf) > 0) { val = val sep l; sep = ORS }; close(vf) }
		{
			line = $0
			while ((pos = index(line, m)) > 0) {
				line = substr(line, 1, pos-1) val substr(line, pos + length(m))
			}
			printf "%s\n", line
		}
	' "${_file}" > "${_file}.tmp" && mv "${_file}.tmp" "${_file}"
	rm -f "${_vf}"
}

gen_fallback_domains() {
	_fallbacks="$(json_get_array "fallback_domains" 2>/dev/null || true)"
	if [ -z "${_fallbacks}" ]; then
		printf '%sexit 1' "${TAB}"
		return
	fi
	_depth=0
	printf '%s\n' "${_fallbacks}" | while IFS= read -r fb; do
		[ -z "${fb}" ] && continue
		_tabs=""
		_d=0; while [ "${_d}" -le "${_depth}" ]; do _tabs="${_tabs}${TAB}"; _d=$((_d+1)); done
		printf '%strm_domain="%s"\n' "${_tabs}" "${fb}"
		printf '%sif ! "${trm_lookupcmd}" "${trm_domain}" >/dev/null 2>&1; then\n' "${_tabs}"
		_depth=$((_depth+1))
	done
	_count="$(printf '%s\n' "${_fallbacks}" | grep -c .)"
	_i=$((_count - 1))
	while [ "${_i}" -ge 0 ]; do
		_tabs=""; _j=0
		while [ "${_j}" -le "${_i}" ]; do _tabs="${_tabs}${TAB}"; _j=$((_j+1)); done
		printf '%sexit 1\n' "${_tabs}${TAB}"
		printf '%sfi\n' "${_tabs}"
		_i=$((_i - 1))
	done
}

gen_credential_setup() {
	_cred_type="$(json_get "credentials" 2>/dev/null || echo "none")"
	_url_encode="$(json_get_nested "params.url_encode_creds" 2>/dev/null || echo "false")"
	case "${_cred_type}" in
		"username_password"|"userpass")
			if [ "${_url_encode}" = "true" ]; then
				printf 'username="$(urlencode "${1}")"\npassword="$(urlencode "${2}")"'
			else
				printf 'username="${1}"\npassword="${2}"'
			fi
			;;
		"username_only")
			if [ "${_url_encode}" = "true" ]; then
				printf 'username="$(urlencode "${1}")"'
			else
				printf 'username="${1}"'
			fi
			;;
		"password_only")
			if [ "${_url_encode}" = "true" ]; then
				printf 'password="$(urlencode "${1}")"'
			else
				printf 'password="${1}"'
			fi
			;;
		*) printf '# no credentials required' ;;
	esac
}

gen_urlencode_func() {
	_url_encode="$(json_get_nested "params.url_encode_creds" 2>/dev/null || echo "false")"
	if [ "${_url_encode}" = "true" ]; then
		cat << 'URLEOF'
urlencode()
{
	local chr str="${1}" len="${#1}" pos=0

	while [ "${pos}" -lt "${len}" ]; do
		chr="${str:pos:1}"
		case "${chr}" in
			[a-zA-Z0-9.~_-])
				printf "%s" "${chr}"
				;;
			" ")
				printf "%%20"
				;;
			*)
				printf "%%%02X" "'${chr}"
				;;
		esac
		pos=$((pos + 1))
	done
}

URLEOF
	fi
}

gen_success_check() {
	_check="$(json_get_nested "params.success_check_type" 2>/dev/null || json_get_nested "params.success_check" 2>/dev/null || echo "empty_body")"
	case "${_check}" in
		"empty_body")
			echo '[ -z "${raw_html}" ] && exit 0 || exit 255' ;;
		"json_true")
			cat << 'SCEOF'
success="$(printf "%s" "${raw_html}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '@.success')"
[ "${success}" = "true" ] && exit 0 || exit 255
SCEOF
			;;
		"contains_string")
			_str="$(json_get_nested "params.success_check_string" 2>/dev/null || json_get_nested "params.success_string" 2>/dev/null || echo "success")"
			printf 'printf "%%s" "${raw_html}" 2>/dev/null | grep -q "%s" && exit 0 || exit 255' "${_str}" ;;
		"json_not_null")
			_field="$(json_get_nested "params.success_check_field" 2>/dev/null || json_get_nested "params.success_field" 2>/dev/null || echo "session")"
			printf 'result="$(printf "%%s" "${raw_html}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '"'"'@.%s'"'"')"\n[ -n "${result}" ] && exit 0 || exit 255' "${_field}" ;;
		"redirect_match")
			_pattern="$(json_get_nested "params.success_check_pattern" 2>/dev/null || json_get_nested "params.success_pattern" 2>/dev/null || echo "")"
			printf 'printf "%%s" "${raw_html}" 2>/dev/null | grep -q "%s" && exit 0 || exit 255' "${_pattern}" ;;
		*) echo '[ -z "${raw_html}" ] && exit 0 || exit 255' ;;
	esac
}

# ── CSRF fetch+extract code generator ───────────────────────────────
gen_csrf_cookie_fetch() {
	_page_url="$1"
	_cookie_name="$2"
	_tmpfile="${SUBST_DIR}/csrf_fetch_tmp"
	cat << 'CSREOF' > "${_tmpfile}"
"${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" --cookie-jar "/tmp/${trm_domain}.cookie" --output /dev/null "__CSRF_PAGE_URL__"
sec_token="$("${trm_awkcmd}" '/__CSRF_COOKIE_NAME__/{print $7}' "/tmp/${trm_domain}.cookie" 2>/dev/null)"
rm -f "/tmp/${trm_domain}.cookie"
CSREOF
	marker_subst "__CSRF_PAGE_URL__" "${_page_url}" "${_tmpfile}"
	marker_subst "__CSRF_COOKIE_NAME__" "${_cookie_name}" "${_tmpfile}"
	printf '%s' "${_tmpfile}"
}

gen_csrf_body_fetch() {
	_page_url="$1"
	_field_name="$2"
	_tmpfile="${SUBST_DIR}/csrf_fetch_tmp"
	cat << 'CSREOF' > "${_tmpfile}"
form_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" "__CSRF_PAGE_URL__")"
sec_token="$(printf "%s" "${form_html}" 2>/dev/null | "${trm_awkcmd}" 'match(tolower($0),/__CSRF_FIELD_NAME__="[^"]*"/){val=substr($0,RSTART); gsub(/.*value="/,"",val); gsub(/".*/,"",val); print val; exit}' 2>/dev/null)"
CSREOF
	marker_subst "__CSRF_PAGE_URL__" "${_page_url}" "${_tmpfile}"
	marker_subst "__CSRF_FIELD_NAME__" "${_field_name}" "${_tmpfile}"
	printf '%s' "${_tmpfile}"
}

# ── JSON-API step code generator ────────────────────────────────────
gen_json_api_steps() {
	_tmpfile="${SUBST_DIR}/json_steps_tmp"
	> "${_tmpfile}"
	_step=1
	while true; do
		_step_url="$(json_get_nested "params.step${_step}_url" 2>/dev/null || true)"
		[ -z "${_step_url}" ] && break
		_step_method="$(json_get_nested "params.step${_step}_method" 2>/dev/null || echo "GET")"
		_step_name="$(json_get_nested "params.step${_step}_name" 2>/dev/null || echo "step ${_step}")"
		_step_type="$(json_get_nested "params.step${_step}_type" 2>/dev/null || echo "fetch")"
		_step_referer="$(json_get_nested "params.step${_step}_referer" 2>/dev/null || true)"
		_step_data="$(json_get_nested "params.step${_step}_data" 2>/dev/null || true)"
		_step_extract="$(json_get_nested "params.step${_step}_extract" 2>/dev/null || true)"
		_step_required="$(json_get_nested "params.step${_step}_required" 2>/dev/null || true)"

		_step_tmp="${SUBST_DIR}/step_${_step}_tmp"

		case "${_step_type}" in
		redirect)
			_opts_markers='${trm_fetchparm} --user-agent "${trm_useragent}" --write-out "%{redirect_url}" --output /dev/null'
			[ -n "${_step_referer}" ] && _opts_markers="${_opts_markers} --referer \"${_step_referer}\""
			cat << 'STEPEOF' > "${_step_tmp}"
# __STEP_NAME__
#
redirect_url="$("${trm_fetch}" __STEP_OPTS__ "__STEP_URL__")"
STEPEOF
			marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
			marker_subst "__STEP_OPTS__" "${_opts_markers}" "${_step_tmp}"
			marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
			cat "${_step_tmp}" >> "${_tmpfile}"

			if [ -n "${_step_extract}" ]; then
				gen_awk_extracts "${_step_extract}" "redirect_url" "${_tmpfile}" "ext_${_step}"
			fi
			;;
		*)
			_opts_markers='${trm_fetchparm} --user-agent "${trm_useragent}"'
			[ -n "${_step_referer}" ] && _opts_markers="${_opts_markers} --referer \"${_step_referer}\""
			[ "${_step_method}" = "POST" ] && [ -n "${_step_data}" ] && _opts_markers="${_opts_markers} --data \"${_step_data}\""

			cat << 'STEPEOF' > "${_step_tmp}"
# __STEP_NAME__
raw_html="$("${trm_fetch}" __STEP_OPTS__ "__STEP_URL__")"
STEPEOF
			marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
			marker_subst "__STEP_OPTS__" "${_opts_markers}" "${_step_tmp}"
			marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
			cat "${_step_tmp}" >> "${_tmpfile}"

			if [ -n "${_step_extract}" ]; then
				gen_json_extracts "${_step_extract}" "raw_html" "${_tmpfile}" "jext_${_step}"
			fi
			;;
		esac

		if [ -n "${_step_required}" ]; then
			printf '[ -z "${%s}" ] && exit %d\n' "${_step_required}" "${_step}" >> "${_tmpfile}"
		fi
		_step=$((_step + 1))
	done
	printf '%s' "${_tmpfile}"
}

# ── Template compilers ──────────────────────────────────────────────

compile_click_through_grant() {
	_grant_url_param="$(json_get_nested "params.grant_url_param" 2>/dev/null || echo "base_grant_url")"
	_param_len="$((${#_grant_url_param} + 1))"
	_continue_url="$(json_get_nested "params.continue_url" 2>/dev/null || echo "http://google.com/")"
	_duration="$(json_get_nested "params.duration" 2>/dev/null || echo "86400")"
	_grant_method="$(json_get_nested "params.grant_method" 2>/dev/null || echo "GET")"
	[ "${_grant_method}" = "POST" ] && _method_opt="--request POST " || _method_opt=""

	subst_common
	subst "%%GRANT_URL_PARAM%%	${_grant_url_param}"
	subst "%%GRANT_URL_PARAM_LEN%%	${_param_len}"
	subst "%%CONTINUE_URL%%	${_continue_url}"
	subst "%%DURATION%%	${_duration}"
	subst "%%GRANT_METHOD_OPT%%	${_method_opt}"
	apply_common_finish
}

compile_form_submit() {
	_form_page_url="$(json_get_nested "params.form_page_url" 2>/dev/null || echo '${trm_captiveurl}')"
	_submit_url="$(json_get_nested "params.submit_url" 2>/dev/null || echo 'http://${trm_domain}')"
	_username_field="$(json_get_nested "params.username_field" 2>/dev/null || echo "username")"
	_password_field="$(json_get_nested "params.password_field" 2>/dev/null || echo "password")"
	_form_action_default="$(json_get_nested "params.form_action_default" 2>/dev/null || echo "/")"
	_extra_fields_raw="$(json_get_nested "params.extra_fields" 2>/dev/null || true)"
	[ -n "${_extra_fields_raw}" ] && _extra_fields="&${_extra_fields_raw}" || _extra_fields=""

	subst_common
	subst "%%URLENCODE_FUNC%%	$(gen_urlencode_func)"
	subst "%%FORM_PAGE_URL%%	${_form_page_url}"
	subst "%%FORM_ACTION_DEFAULT%%	${_form_action_default}"
	subst "%%USERNAME_FIELD%%	${_username_field}"
	subst "%%PASSWORD_FIELD%%	${_password_field}"
	subst "%%EXTRA_FIELDS%%	${_extra_fields}"
	subst "%%SUBMIT_URL%%	${_submit_url}"
	apply_common_finish
}

compile_csrf_form_submit() {
	_csrf_source="$(json_get_nested "params.csrf_source" 2>/dev/null || echo "cookie")"
	_csrf_page_url="$(json_get_nested "params.csrf_page_url" 2>/dev/null || true)"
	_csrf_cookie_name="$(json_get_nested "params.csrf_cookie_name" 2>/dev/null || echo "csrf")"
	_csrf_field_name="$(json_get_nested "params.csrf_field_name" 2>/dev/null || echo "CSRFToken")"
	_csrf_regex="$(json_get_nested "params.csrf_regex" 2>/dev/null || true)"
	_csrf_submit_url="$(json_get_nested "params.csrf_submit_url" 2>/dev/null || true)"
	_extra_fields_raw="$(json_get_nested "params.extra_fields" 2>/dev/null || true)"
	[ -n "${_extra_fields_raw}" ] && _extra_fields="&${_extra_fields_raw}" || _extra_fields=""

	case "${_csrf_source}" in
		cookie)
			_csrf_tmp="$(gen_csrf_cookie_fetch "${_csrf_page_url}" "${_csrf_cookie_name}")"
			_csrf_header="--header \"Cookie: ${_csrf_cookie_name}=\${sec_token}\""
			;;
		body_hidden)
			_csrf_tmp="$(gen_csrf_body_fetch "${_csrf_page_url}" "${_csrf_field_name}")"
			_csrf_header=""
			;;
		body_regex)
			_csrf_tmp="${SUBST_DIR}/csrf_fetch_tmp"
			if [ -n "${_csrf_regex}" ]; then
				cat << 'REGEXEOF' > "${_csrf_tmp}"
form_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" "__CSRF_PAGE_URL__")"
sec_token="$(printf "%s" "${form_html}" 2>/dev/null | grep -o '__CSRF_REGEX__' 2>/dev/null)"
REGEXEOF
				marker_subst "__CSRF_PAGE_URL__" "${_csrf_page_url}" "${_csrf_tmp}"
				marker_subst "__CSRF_REGEX__" "${_csrf_regex}" "${_csrf_tmp}"
			else
				cat << 'REGEXEOF' > "${_csrf_tmp}"
form_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" "__CSRF_PAGE_URL__")"
sec_token="$(printf "%s" "${form_html}" 2>/dev/null | "${trm_awkcmd}" '/csrf/{print $NF}' 2>/dev/null)"
REGEXEOF
				marker_subst "__CSRF_PAGE_URL__" "${_csrf_page_url}" "${_csrf_tmp}"
			fi
			_csrf_header=""
			;;
		*) echo "error: unknown csrf_source '${_csrf_source}'" >&2; exit 1 ;;
	esac

	subst_common
	subst_file "%%CSRF_FETCH_AND_EXTRACT%%" "${_csrf_tmp}"
	subst "%%CSRF_HEADER%%	${_csrf_header}"
	subst "%%CSRF_FIELD_NAME%%	${_csrf_field_name}"
	subst "%%EXTRA_FIELDS%%	${_extra_fields}"
	subst "%%CSRF_SUBMIT_URL%%	${_csrf_submit_url}"
	apply_common_finish
}

compile_json_api() {
	_steps_tmp="$(gen_json_api_steps)"

	subst_common
	subst_file "%%STEPS%%" "${_steps_tmp}"
	apply_common_finish
}

# ── Multi-API step code generator (extends json-api with foreach) ────
gen_multi_api_steps() {
	_tmpfile="${SUBST_DIR}/multi_api_steps_tmp"
	> "${_tmpfile}"
	_step=1
	while true; do
		_step_url="$(json_get_nested "params.step${_step}_url" 2>/dev/null || true)"
		[ -z "${_step_url}" ] && break
		_step_method="$(json_get_nested "params.step${_step}_method" 2>/dev/null || echo "GET")"
		_step_name="$(json_get_nested "params.step${_step}_name" 2>/dev/null || echo "step ${_step}")"
		_step_type="$(json_get_nested "params.step${_step}_type" 2>/dev/null || echo "fetch")"
		_step_referer="$(json_get_nested "params.step${_step}_referer" 2>/dev/null || true)"
		_step_data="$(json_get_nested "params.step${_step}_data" 2>/dev/null || true)"
		_step_extract="$(json_get_nested "params.step${_step}_extract" 2>/dev/null || true)"
		_step_required="$(json_get_nested "params.step${_step}_required" 2>/dev/null || true)"

		_step_tmp="${SUBST_DIR}/mastep_${_step}_tmp"

		case "${_step_type}" in
		redirect)
			_opts_markers='${trm_fetchparm} --user-agent "${trm_useragent}" --write-out "%{redirect_url}" --output /dev/null'
			[ -n "${_step_referer}" ] && _opts_markers="${_opts_markers} --referer \"${_step_referer}\""
			cat << 'STEPEOF' > "${_step_tmp}"
# __STEP_NAME__
#
redirect_url="$("${trm_fetch}" __STEP_OPTS__ "__STEP_URL__")"
STEPEOF
			marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
			marker_subst "__STEP_OPTS__" "${_opts_markers}" "${_step_tmp}"
			marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
			cat "${_step_tmp}" >> "${_tmpfile}"

			if [ -n "${_step_extract}" ]; then
				gen_awk_extracts "${_step_extract}" "redirect_url" "${_tmpfile}" "mext_${_step}"
			fi
			;;
		foreach)
			_fe_in="$(json_get_nested "params.step${_step}_foreach_in" 2>/dev/null || true)"
			_fe_as="$(json_get_nested "params.step${_step}_foreach_as" 2>/dev/null || echo "item")"
			_fe_until="$(json_get_nested "params.step${_step}_foreach_until_success" 2>/dev/null || echo "false")"
			_fe_referer="${_step_referer}"
			_fe_data="${_step_data}"

			# Build fetch options for inside the loop
			_fe_opts='${trm_fetchparm} --user-agent "${trm_useragent}"'
			[ -n "${_fe_referer}" ] && _fe_opts="${_fe_opts} --referer \"${_fe_referer}\""
			[ "${_step_method}" = "POST" ] && [ -n "${_fe_data}" ] && _fe_opts="${_fe_opts} --data \"${_fe_data}\""

			# Generate the foreach loop header
			cat << 'FEEOF' > "${_step_tmp}"
# __STEP_NAME__ (foreach: try each __FE_AS__)
_fe_success=1
echo "${__FE_IN__}" | while IFS= read -r __FE_AS__; do
	[ -z "${__FE_AS__}" ] && continue
	raw_html="$("${trm_fetch}" __FE_OPTS__ "__STEP_URL__")"
FEEOF
			marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
			marker_subst "__FE_IN__" "${_fe_in}" "${_step_tmp}"
			marker_subst "__FE_AS__" "${_fe_as}" "${_step_tmp}"
			marker_subst "__FE_OPTS__" "${_fe_opts}" "${_step_tmp}"
			marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
			cat "${_step_tmp}" >> "${_tmpfile}"

			# Extract inside the loop body (if any)
			if [ -n "${_step_extract}" ]; then
				gen_json_extracts "${_step_extract}" "raw_html" "${_tmpfile}" "mfext_${_step}"
			fi

			# Generate loop success check and footer
			if [ "${_fe_until}" = "true" ]; then
				# Use gen_success_check logic inline for the check
				_check="$(json_get_nested "params.success_check_type" 2>/dev/null || json_get_nested "params.success_check" 2>/dev/null || echo "empty_body")"
				case "${_check}" in
					json_true)
						cat << 'CHECKEOF' >> "${_tmpfile}"
	_result="$(printf "%s" "${raw_html}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '@.success')"
	[ "${_result}" = "true" ] && exit 0
CHECKEOF
						;;
					empty_body)
						echo '	[ -z "${raw_html}" ] && exit 0' >> "${_tmpfile}"
						;;
					contains_string)
						_str="$(json_get_nested "params.success_check_string" 2>/dev/null || json_get_nested "params.success_string" 2>/dev/null || echo "success")"
						printf '\tprintf "%%s" "${raw_html}" 2>/dev/null | grep -q "%s" && exit 0\n' "${_str}" >> "${_tmpfile}"
						;;
					json_not_null)
						_field="$(json_get_nested "params.success_check_field" 2>/dev/null || json_get_nested "params.success_field" 2>/dev/null || echo "session")"
						printf '\t_result="$(printf "%%s" "${raw_html}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '"'"'@.%s'"'"')"\n' "${_field}" >> "${_tmpfile}"
						echo '	[ -n "${_result}" ] && exit 0' >> "${_tmpfile}"
						;;
					*)
						echo '	[ -z "${raw_html}" ] && exit 0' >> "${_tmpfile}"
						;;
				esac
			fi

			echo "done" >> "${_tmpfile}"
			echo "_fe_success=\$?" >> "${_tmpfile}"
			echo '[ "${_fe_success}" = "0" ] || exit 5' >> "${_tmpfile}"
			touch "${SUBST_DIR}/multi_api_foreach_flag"
			;;
		*)
			_opts_markers='${trm_fetchparm} --user-agent "${trm_useragent}"'
			[ -n "${_step_referer}" ] && _opts_markers="${_opts_markers} --referer \"${_step_referer}\""
			[ "${_step_method}" = "POST" ] && [ -n "${_step_data}" ] && _opts_markers="${_opts_markers} --data \"${_step_data}\""

			cat << 'STEPEOF' > "${_step_tmp}"
# __STEP_NAME__
raw_html="$("${trm_fetch}" __STEP_OPTS__ "__STEP_URL__")"
STEPEOF
			marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
			marker_subst "__STEP_OPTS__" "${_opts_markers}" "${_step_tmp}"
			marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
			cat "${_step_tmp}" >> "${_tmpfile}"

			if [ -n "${_step_extract}" ]; then
				_ma_oldifs="${IFS}"; IFS='|'
				set -f
				for _ma_ext in ${_step_extract}; do
					_ma_vn="${_ma_ext%%:*}"
					_ma_code="${_ma_ext#*:}"
					[ -z "${_ma_vn}" ] || [ -z "${_ma_code}" ] && continue
					_ma_ext_tmp="${SUBST_DIR}/maext_${_step}_${_ma_vn}"
					if [ "${_ma_code#\@}" != "${_ma_code}" ]; then
						printf '%s="$(printf "%%s" "${raw_html}" 2>/dev/null | "${trm_jsoncmd}" -q -l1 -e '"'"'%s'"'"')"\n' "${_ma_vn}" "${_ma_code}" > "${_ma_ext_tmp}"
					else
						printf '%s="$(printf "%%s" "${raw_html}" 2>/dev/null | "${trm_awkcmd}" '"'"'%s'"'"')"\n' "${_ma_vn}" "${_ma_code}" > "${_ma_ext_tmp}"
					fi
					cat "${_ma_ext_tmp}" >> "${_tmpfile}"
				done
				set +f
				IFS="${_ma_oldifs}"
			fi
			;;
		esac

		if [ -n "${_step_required}" ]; then
			printf '[ -z "${%s}" ] && exit %d\n' "${_step_required}" "${_step}" >> "${_tmpfile}"
		fi
		_step=$((_step + 1))
	done
	printf '%s' "${_tmpfile}"
}

compile_multi_api() {
	_multi_api_foreach_flag=""
	rm -f "${SUBST_DIR}/multi_api_foreach_flag"
	_steps_tmp="$(gen_multi_api_steps)"
	[ -f "${SUBST_DIR}/multi_api_foreach_flag" ] && _multi_api_foreach_flag=1

	subst_common
	subst_file "%%STEPS%%" "${_steps_tmp}"
	if [ -n "${_multi_api_foreach_flag}" ]; then
		subst "%%SUCCESS_CHECK%%	exit 0"
	else
		subst "%%SUCCESS_CHECK%%	$(gen_success_check)"
	fi
	apply_substs
}

compile_chap_md5() {
	_chap_detect="$(json_get_nested "params.chap_detect" 2>/dev/null || echo "chap-challenge")"
	_form_action="$(json_get_nested "params.form_action" 2>/dev/null || echo 'http://${trm_domain}/login')"
	_username_field="$(json_get_nested "params.username_field" 2>/dev/null || echo "username")"
	_response_field="$(json_get_nested "params.response_field" 2>/dev/null || echo "response")"
	_dst_field="$(json_get_nested "params.dst_field" 2>/dev/null || echo "dst")"
	_dst_default="$(json_get_nested "params.dst_default" 2>/dev/null || echo "http://www.google.com")"

	_id_tmp="${SUBST_DIR}/chap_id_tmp"
	_chal_tmp="${SUBST_DIR}/chap_chal_tmp"
	_id_extract_raw="$(json_get_nested "params.chap_id_extract" 2>/dev/null || true)"
	_chal_extract_raw="$(json_get_nested "params.chap_challenge_extract" 2>/dev/null || true)"

	if [ -n "${_id_extract_raw}" ]; then
		printf 'chap_id="$(printf "%%s" "${raw_html}" 2>/dev/null | %s)"\n' "${_id_extract_raw}" > "${_id_tmp}"
	else
		cat > "${_id_tmp}" << 'CHAPIDEOF'
chap_id="$(printf "%s" "${raw_html}" 2>/dev/null | "${trm_awkcmd}" 'match(tolower($0),/name="chap-id"[^>]*value="[^"]*"/){val=substr($0,RSTART); gsub(/.*value="/,"",val); gsub(/".*/,"",val); print val; exit}' 2>/dev/null)"
CHAPIDEOF
	fi

	if [ -n "${_chal_extract_raw}" ]; then
		printf 'challenge="$(printf "%%s" "${raw_html}" 2>/dev/null | %s)"\n' "${_chal_extract_raw}" > "${_chal_tmp}"
	else
		cat > "${_chal_tmp}" << 'CHAPCHALEOF'
challenge="$(printf "%s" "${raw_html}" 2>/dev/null | "${trm_awkcmd}" 'match(tolower($0),/name="chap-challenge"[^>]*value="[^"]*"/){val=substr($0,RSTART); gsub(/.*value="/,"",val); gsub(/".*/,"",val); print val; exit}' 2>/dev/null)"
CHAPCHALEOF
	fi

	subst_common
	subst "%%CHAP_DETECT%%	${_chap_detect}"
	subst_file "%%CHAP_ID_EXTRACT%%" "${_id_tmp}"
	subst_file "%%CHAP_CHALLENGE_EXTRACT%%" "${_chal_tmp}"
	subst "%%FORM_ACTION%%	${_form_action}"
	subst "%%USERNAME_FIELD%%	${_username_field}"
	subst "%%RESPONSE_FIELD%%	${_response_field}"
	subst "%%DST_FIELD%%	${_dst_field}"
	subst "%%DST_DEFAULT%%	${_dst_default}"
	apply_common_finish
}

# ── Multi-step form step generator ──────────────────────────────────
gen_multi_step_form_steps() {
	_tmpfile="${SUBST_DIR}/msf_steps_tmp"
	> "${_tmpfile}"
	_step=1
	while true; do
		_step_url="$(json_get_nested "params.step${_step}_url" 2>/dev/null || true)"
		[ -z "${_step_url}" ] && break
		_step_name="$(json_get_nested "params.step${_step}_name" 2>/dev/null || echo "step ${_step}")"
		_step_extra_raw="$(json_get_nested "params.step${_step}_extra_fields" 2>/dev/null || true)"
		_step_extract="$(json_get_nested "params.step${_step}_extract" 2>/dev/null || true)"

		[ -n "${_step_extra_raw}" ] && _extra_post="&${_step_extra_raw}" || _extra_post=""

		_step_tmp="${SUBST_DIR}/msf_step_${_step}_tmp"
		_exit_code=$((_step + 1))

		cat << 'MSEOF' > "${_step_tmp}"
# __STEP_NAME__
#
step_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" "__STEP_URL__")"
[ -z "${step_html}" ] && exit __STEP_EXIT__

form_action="$(printf "%s" "${step_html}" 2>/dev/null | "${trm_awkcmd}" 'match(tolower($0),/action="[^"]*"/){val=substr($0,RSTART+8,RLENGTH-9); print val; exit}' 2>/dev/null)"
[ -z "${form_action}" ] && form_action="__STEP_URL__"

hidden_fields="$(printf "%s" "${step_html}" 2>/dev/null | "${trm_awkcmd}" '
match(tolower($0),/<input[^>]*type="hidden"[^>]*>/){
	line=substr($0,RSTART,RLENGTH)
	nam=""
	val=""
	if(match(line,/name="[^"]*"/)){nam=substr(line,RSTART+6,RLENGTH-7)}
	if(match(line,/value="[^"]*"/)){val=substr(line,RSTART+7,RLENGTH-8)}
	if(nam!=""){printf "%s=%s&",nam,val}
}')"

post_data="${hidden_fields}__STEP_EXTRA__"
raw_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" --header "Content-Type:application/x-www-form-urlencoded" --data "${post_data}" "${form_action}")"
MSEOF
		marker_subst "__STEP_NAME__" "${_step_name}" "${_step_tmp}"
		marker_subst "__STEP_URL__" "${_step_url}" "${_step_tmp}"
		marker_subst "__STEP_EXIT__" "${_exit_code}" "${_step_tmp}"
		marker_subst "__STEP_EXTRA__" "${_extra_post}" "${_step_tmp}"
		cat "${_step_tmp}" >> "${_tmpfile}"

		if [ -n "${_step_extract}" ]; then
			gen_awk_extracts "${_step_extract}" "raw_html" "${_tmpfile}" "msf_ext_${_step}"
		fi
		_step=$((_step + 1))
	done
	printf '%s' "${_tmpfile}"
}

compile_js_redirect() {
	_js_patterns="$(json_get_nested "params.js_extract_patterns" 2>/dev/null || true)"
	_follow_redirect="$(json_get_nested "params.follow_redirect" 2>/dev/null || echo "true")"

	_js_tmp="${SUBST_DIR}/js_extract_tmp"
	if [ -n "${_js_patterns}" ]; then
		cat > "${_js_tmp}" << EXTEOF
redirect_url="\$(printf "%s" "\${raw_html}" 2>/dev/null | "\${trm_awkcmd}" '${_js_patterns}')"
EXTEOF
	else
		cat > "${_js_tmp}" << 'JSEOF'
redirect_url="$(printf "%s" "${raw_html}" 2>/dev/null | "${trm_awkcmd}" '
{
	line = tolower($0)
	if (match(line, /window\.location[[:space:]]*=[[:space:]]*"[^"]*"/)) {
		s = substr($0, RSTART); gsub(/.*"/, "", s); gsub(/".*/, "", s); print s; exit
	}
	if (match(line, /location\.replace[[:space:]]*\([[:space:]]*"[^"]*"/)) {
		s = substr($0, RSTART); gsub(/.*"/, "", s); gsub(/".*/, "", s); print s; exit
	}
	if (match(line, /location\.href[[:space:]]*=[[:space:]]*"[^"]*"/)) {
		s = substr($0, RSTART); gsub(/.*"/, "", s); gsub(/".*/, "", s); print s; exit
	}
	if (match(line, /location[[:space:]]*=[[:space:]]*"[^"]*"/)) {
		s = substr($0, RSTART); gsub(/.*"/, "", s); gsub(/".*/, "", s); print s; exit
	}
}')"
JSEOF
	fi

	_follow_tmp="${SUBST_DIR}/follow_redirect_tmp"
	if [ "${_follow_redirect}" = "true" ]; then
		cat > "${_follow_tmp}" << 'FOLLEOF'
raw_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}" "${redirect_url}")"
FOLLEOF
	else
		printf '# redirect not followed by configuration' > "${_follow_tmp}"
	fi

	subst_common
	subst_file "%%JS_EXTRACT%%" "${_js_tmp}"
	subst_file "%%FOLLOW_REDIRECT%%" "${_follow_tmp}"
	apply_common_finish
}

compile_js_parse() {
	_page_url="$(json_get_nested "params.js_page_url" 2>/dev/null || echo '${trm_captiveurl}')"
	_submit_url="$(json_get_nested "params.submit_url" 2>/dev/null || echo 'http://${trm_domain}')"
	_submit_method="$(json_get_nested "params.submit_method" 2>/dev/null || echo "POST")"
	_submit_data="$(json_get_nested "params.submit_data" 2>/dev/null || true)"
	_submit_content_type="$(json_get_nested "params.submit_content_type" 2>/dev/null || echo "application/x-www-form-urlencoded")"
	_submit_extra_headers="$(json_get_nested "params.submit_extra_headers" 2>/dev/null || true)"

	# Generate extraction steps
	_ext_tmp="${SUBST_DIR}/js_parse_steps_tmp"
	> "${_ext_tmp}"
	_ext_num=1
	while true; do
		_ext_var="$(json_get_nested "params.js_extract${_ext_num}_var" 2>/dev/null || true)"
		[ -z "${_ext_var}" ] && break
		_ext_pattern="$(json_get_nested "params.js_extract${_ext_num}_pattern" 2>/dev/null || true)"
		_ext_default="$(json_get_nested "params.js_extract${_ext_num}_default" 2>/dev/null || true)"

		_ext_step_tmp="${SUBST_DIR}/js_parse_ext_${_ext_num}"
		cat > "${_ext_step_tmp}" << 'EXTEOF'
__EXT_VAR__="$(printf "%s" "${raw_html}" | sed -nE 's/.*__EXT_PATTERN__.*/\1/p' | head -1)"
EXTEOF
		if [ -n "${_ext_default}" ]; then
			printf '[ -z "${__EXT_VAR__}" ] && __EXT_VAR__="__EXT_DEFAULT__"\n' >> "${_ext_step_tmp}"
		else
			printf '[ -z "${__EXT_VAR__}" ] && exit __EXT_EXIT__\n' >> "${_ext_step_tmp}"
		fi

		marker_subst "__EXT_VAR__" "${_ext_var}" "${_ext_step_tmp}"
		marker_subst "__EXT_PATTERN__" "${_ext_pattern}" "${_ext_step_tmp}"
		if [ -n "${_ext_default}" ]; then
			marker_subst "__EXT_DEFAULT__" "${_ext_default}" "${_ext_step_tmp}"
		else
			marker_subst "__EXT_EXIT__" "$((_ext_num + 1))" "${_ext_step_tmp}"
		fi

		cat "${_ext_step_tmp}" >> "${_ext_tmp}"
		_ext_num=$((_ext_num + 1))
	done

	# Generate submit action
	_submit_tmp="${SUBST_DIR}/js_parse_submit_tmp"
	_opts='${trm_fetchparm} --user-agent "${trm_useragent}"'
	if [ "${_submit_method}" = "POST" ]; then
		_opts="${_opts} --header \"Content-Type:${_submit_content_type}\""
		[ -n "${_submit_data}" ] && _opts="${_opts} --data \"${_submit_data}\""
	fi
	[ -n "${_submit_extra_headers}" ] && _opts="${_opts} --header \"${_submit_extra_headers}\""

	cat > "${_submit_tmp}" << 'SUBMITEOF'
raw_html="$("${trm_fetch}" __SUBMIT_OPTS__ "__SUBMIT_URL__")"
SUBMITEOF
	marker_subst "__SUBMIT_OPTS__" "${_opts}" "${_submit_tmp}"
	marker_subst "__SUBMIT_URL__" "${_submit_url}" "${_submit_tmp}"

	subst_common
	subst "%%JS_PAGE_URL%%	${_page_url}"
	subst_file "%%JS_PARSE_STEPS%%" "${_ext_tmp}"
	subst_file "%%SUBMIT_ACTION%%" "${_submit_tmp}"
	apply_common_finish
}

compile_multi_step_form() {
	_steps_tmp="$(gen_multi_step_form_steps)"

	subst_common
	subst_file "%%STEPS%%" "${_steps_tmp}"
	apply_common_finish
}

compile_multipart_post() {
	_form_page_url="$(json_get_nested "params.form_page_url" 2>/dev/null || echo '${trm_captiveurl}')"
	_submit_url="$(json_get_nested "params.submit_url" 2>/dev/null || echo 'http://${trm_domain}')"
	_extra_form_fields="$(json_get_nested "params.extra_form_fields" 2>/dev/null || true)"

	# Generate hidden field extraction code
	_extract_tmp="${SUBST_DIR}/multipart_extract_tmp"
	> "${_extract_tmp}"
	_field_num=1
	while true; do
		_field_name="$(json_get_nested "params.field${_field_num}_name" 2>/dev/null || true)"
		[ -z "${_field_name}" ] && break
		_field_source="$(json_get_nested "params.field${_field_num}_source" 2>/dev/null || echo "static")"

		case "${_field_source}" in
			hidden)
				_extract_pattern="$(json_get_nested "params.field${_field_num}_extract" 2>/dev/null || true)"
				if [ -n "${_extract_pattern}" ]; then
					printf '%s="$(printf "%%s" "${raw_html}" | sed -nE '"'"'s/.*%s.*/\\1/p'"'"' | head -1)"\n' "${_field_name}" "${_extract_pattern}" >> "${_extract_tmp}"
				fi
				;;
			extract)
				_extract_pattern="$(json_get_nested "params.field${_field_num}_pattern" 2>/dev/null || true)"
				if [ -n "${_extract_pattern}" ]; then
					printf '%s="$(printf "%%s" "${raw_html}" | sed -nE '"'"'s/.*%s.*/\\1/p'"'"' | head -1)"\n' "${_field_name}" "${_extract_pattern}" >> "${_extract_tmp}"
				fi
				;;
		esac
		_field_num=$((_field_num + 1))
	done

	# Generate multipart submit command
	_submit_tmp="${SUBST_DIR}/multipart_submit_tmp"
	printf 'raw_html="$("${trm_fetch}" ${trm_fetchparm} --user-agent "${trm_useragent}"' > "${_submit_tmp}"

	_field_num=1
	while true; do
		_field_name="$(json_get_nested "params.field${_field_num}_name" 2>/dev/null || true)"
		[ -z "${_field_name}" ] && break
		_field_value="$(json_get_nested "params.field${_field_num}_value" 2>/dev/null || true)"
		_field_source="$(json_get_nested "params.field${_field_num}_source" 2>/dev/null || echo "static")"

		case "${_field_source}" in
			static)
				printf ' \\\n  --form-string "%s=%s"' "${_field_name}" "${_field_value}" >> "${_submit_tmp}"
				;;
			hidden|extract)
				printf ' \\\n  --form-string "%s=${%s}"' "${_field_name}" "${_field_name}" >> "${_submit_tmp}"
				;;
		esac
		_field_num=$((_field_num + 1))
	done

	if [ -n "${_extra_form_fields}" ]; then
		printf ' \\\n  %s' "${_extra_form_fields}" >> "${_submit_tmp}"
	fi

	printf ' \\\n  "%s")"\n' "${_submit_url}" >> "${_submit_tmp}"

	subst_common
	subst "%%FORM_PAGE_URL%%	${_form_page_url}"
	subst_file "%%HIDDEN_FIELDS_EXTRACT%%" "${_extract_tmp}"
	subst_file "%%MULTIPART_SUBMIT%%" "${_submit_tmp}"
	apply_common_finish
}

compile_cookie_chain() {
	_init_url="$(json_get_nested "params.init_url" 2>/dev/null || echo '${trm_captiveurl}')"
	_cookie_pattern="$(json_get_nested "params.cookie_extract_pattern" 2>/dev/null || true)"
	_submit_url="$(json_get_nested "params.submit_url" 2>/dev/null || echo 'http://${trm_domain}')"
	_post_data="$(json_get_nested "params.post_data" 2>/dev/null || echo 'accept=1')"
	_extra_headers_raw="$(json_get_nested "params.extra_headers" 2>/dev/null || true)"
	[ -n "${_extra_headers_raw}" ] && _extra_headers="--header \"${_extra_headers_raw}\"" || _extra_headers=""

	_cookie_tmp="${SUBST_DIR}/cookie_extract_tmp"
	if [ -n "${_cookie_pattern}" ]; then
		printf 'session_token="$("${trm_awkcmd}" '"'"'%s'"'"' "${cookie_jar}" 2>/dev/null)"' "${_cookie_pattern}" > "${_cookie_tmp}"
	else
		printf 'session_token="$("${trm_awkcmd}" '"'"'NR>3{print $NF}'"'"' "${cookie_jar}" 2>/dev/null)"' > "${_cookie_tmp}"
	fi

	subst_common
	subst "%%INIT_URL%%	${_init_url}"
	subst_file "%%COOKIE_EXTRACT%%" "${_cookie_tmp}"
	subst "%%EXTRA_HEADERS%%	${_extra_headers}"
	subst "%%POST_DATA%%	${_post_data}"
	subst "%%SUBMIT_URL%%	${_submit_url}"
	apply_common_finish
}

compile_jwt_sign() {
	_jwt_header="$(json_get_nested "params.jwt_header" 2>/dev/null || echo '{"alg":"HS256","typ":"JWT"}')"
	_jwt_payload="$(json_get_nested "params.jwt_payload" 2>/dev/null || true)"
	_jwt_secret="$(json_get_nested "params.jwt_secret" 2>/dev/null || true)"
	_jwt_query_param="$(json_get_nested "params.jwt_query_param" 2>/dev/null || echo "jwt")"
	_request_url="$(json_get_nested "params.request_url" 2>/dev/null || true)"
	_request_method="$(json_get_nested "params.request_method" 2>/dev/null || echo "GET")"

	# Build the auth request
	_request_tmp="${SUBST_DIR}/jwt_request_tmp"
	if [ "${_request_method}" = "POST" ]; then
		_opts='${trm_fetchparm} --user-agent "${trm_useragent}" --header "Content-Type: application/json" --data "${jwt_token}"'
	else
		_opts='${trm_fetchparm} --user-agent "${trm_useragent}"'
	fi

	cat > "${_request_tmp}" << 'JWTEOF'
raw_html="$("${trm_fetch}" __JWT_OPTS__ "__JWT_URL__")"
JWTEOF
	marker_subst "__JWT_OPTS__" "${_opts}" "${_request_tmp}"
	marker_subst "__JWT_URL__" "${_request_url}" "${_request_tmp}"

	subst_common
	subst "%%JWT_HEADER%%	${_jwt_header}"
	subst "%%JWT_PAYLOAD%%	${_jwt_payload}"
	subst "%%JWT_SECRET%%	${_jwt_secret}"
	subst_file "%%JWT_REQUEST%%" "${_request_tmp}"
	apply_common_finish
}

# ── Dispatch ────────────────────────────────────────────────────────
case "${auth_type}" in
	click-through-grant) compile_click_through_grant ;;
	form-submit)         compile_form_submit ;;
	csrf-form-submit)    compile_csrf_form_submit ;;
	json-api)            compile_json_api ;;
	chap-md5)            compile_chap_md5 ;;
	js-redirect)          compile_js_redirect ;;
	js-parse)             compile_js_parse ;;
	multi-step-form)      compile_multi_step_form ;;
	multipart-post)       compile_multipart_post ;;
	cookie-chain)         compile_cookie_chain ;;
	jwt-sign)             compile_jwt_sign ;;
	multi-api)            compile_multi_api ;;
	*) echo "error: unknown auth_type '${auth_type}'" >&2; exit 1 ;;
esac

if command -v sh >/dev/null 2>&1; then
	if ! sh -n "${OUTPUT_FILE}" 2>/dev/null; then
		echo "warning: syntax check failed - run 'sh -n ${OUTPUT_FILE}'" >&2
	fi
fi

echo "compiled: ${OUTPUT_FILE}"
