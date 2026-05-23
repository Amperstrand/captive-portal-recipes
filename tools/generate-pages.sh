#!/bin/sh
# generate-pages.sh — Compile all recipes and generate a GitHub Pages index.html
#
# Usage: tools/generate-pages.sh [OPTIONS]
#
# Options:
#   --output-dir <dir>     Output directory for pages (default: pages/)
#   --compile-dir <dir>    Output directory for compiled .login files (default: output/)
#   --recipes-dir <dir>    Directory containing recipe JSON files (default: recipes/)
#   --compiler <path>      Path to compile-recipe.sh (default: compiler/compile-recipe.sh)
#   --skip-compile         Skip compilation step (only generate HTML)
#   --help                 Show this help
set -e

# ── Defaults ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="pages"
COMPILE_DIR="output"
RECIPES_DIR="recipes"
COMPILER="compiler/compile-recipe.sh"
SKIP_COMPILE=0

# ── Argument parsing ─────────────────────────────────────────────────
show_usage() {
	echo "usage: $(basename "$0") [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --output-dir <dir>     Pages output directory (default: pages/)"
	echo "  --compile-dir <dir>    Compiled .login output directory (default: output/)"
	echo "  --recipes-dir <dir>    Recipe JSON directory (default: recipes/)"
	echo "  --compiler <path>      Path to compile-recipe.sh (default: compiler/compile-recipe.sh)"
	echo "  --skip-compile         Skip compilation, only generate HTML"
	echo "  --help                 Show this help"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
		--compile-dir)  COMPILE_DIR="$2"; shift 2 ;;
		--recipes-dir)  RECIPES_DIR="$2"; shift 2 ;;
		--compiler)     COMPILER="$2"; shift 2 ;;
		--skip-compile) SKIP_COMPILE=1; shift ;;
		--help)         show_usage; exit 0 ;;
		-*) echo "error: unknown option '$1'" >&2; show_usage >&2; exit 1 ;;
		*)  echo "error: unexpected argument '$1'" >&2; show_usage >&2; exit 1 ;;
	esac
done

cd "${PROJECT_DIR}"

# ── Validate paths ───────────────────────────────────────────────────
if [ ! -d "${RECIPES_DIR}" ]; then
	echo "error: recipes directory not found: ${RECIPES_DIR}" >&2
	exit 1
fi

COMPILER_PATH="${COMPILER}"
if [ ! -x "${COMPILER_PATH}" ]; then
	# Try relative to project
	COMPILER_PATH="${PROJECT_DIR}/${COMPILER}"
fi
if [ "${SKIP_COMPILE}" = "0" ] && [ ! -x "${COMPILER_PATH}" ]; then
	echo "error: compiler not found or not executable: ${COMPILER}" >&2
	exit 1
fi

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${COMPILE_DIR}"

# Compute relative path from OUTPUT_DIR to COMPILE_DIR for download links.
# If COMPILE_DIR is a child of OUTPUT_DIR, use just the trailing part.
# e.g. OUTPUT_DIR=_site, COMPILE_DIR=_site/output → LINK_PREFIX=output
#      OUTPUT_DIR=pages, COMPILE_DIR=output → LINK_PREFIX=../output
_LINK_PREFIX="../${COMPILE_DIR}"
case "${COMPILE_DIR}" in
	${OUTPUT_DIR}/*)
		_LINK_PREFIX="${COMPILE_DIR#"${OUTPUT_DIR}"/}"
		;;
esac

# ── JSON extraction via awk (same pattern as compiler) ───────────────
json_get() {
	_file="$1"
	_key="$2"
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
	' "${_file}"
}

# ── Parse COMPATIBILITY.md for reliability ───────────────────────────
# Outputs: "<recipe_id> <reliability>" per line
parse_compatibility() {
	_compat_file="${PROJECT_DIR}/docs/COMPATIBILITY.md"
	if [ ! -f "${_compat_file}" ]; then
		return
	fi
	# Extract table rows: | recipe-name | auth_type | ... | reliability | ...
	awk -F'|' '
		/^\|/ && NF >= 5 {
			recipe = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", recipe)
			reliability = $6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", reliability)
			# Skip header/separator rows
			if (recipe ~ /^-+$/) next
			if (recipe == "Recipe") next
			if (recipe == "") next
			if (reliability ~ /HIGH/) print recipe " HIGH"
			else if (reliability ~ /MEDIUM/) print recipe " MEDIUM"
			else if (reliability ~ /LOW/) print recipe " LOW"
			else if (reliability ~ /UNTESTED/) print recipe " UNTESTED"
		}
	' "${_compat_file}"
}

# ── Build compatibility lookup ───────────────────────────────────────
COMPAT_DATA=""
COMPAT_DATA="$(parse_compatibility 2>/dev/null || true)"

get_reliability() {
	_id="$1"
	_match="$(printf '%s\n' "${COMPAT_DATA}" | while IFS=' ' read -r _rid _rel; do
		if [ "${_rid}" = "${_id}" ]; then
			printf '%s' "${_rel}"
			break
		fi
	done)"
	if [ -n "${_match}" ]; then
		printf '%s' "${_match}"
	else
		printf 'UNTESTED'
	fi
}

# ── HTML-escape helper ───────────────────────────────────────────────
html_escape() {
	printf '%s' "$1" | awk '
		BEGIN { RS = ""; ORS = "" }
		{
			gsub(/&/, "\\&amp;")
			gsub(/</, "\\&lt;")
			gsub(/>/, "\\&gt;")
			gsub(/"/, "\\&quot;")
			print
		}
	'
}

# ── Step 1: Compile all recipes ──────────────────────────────────────
RECIPE_COUNT=0
COMPILE_OK=0
COMPILE_FAIL=0

if [ "${SKIP_COMPILE}" = "0" ]; then
	echo "==> Compiling recipes..."
	for recipe in "${RECIPES_DIR}"/*.json; do
		[ -f "${recipe}" ] || continue
		_base="$(basename "${recipe}" .json)"
		RECIPE_COUNT=$((RECIPE_COUNT + 1))
		if "${COMPILER_PATH}" "${recipe}" -o "${COMPILE_DIR}/${_base}.login" 2>/dev/null; then
			COMPILE_OK=$((COMPILE_OK + 1))
		else
			echo "  warning: failed to compile ${_base}" >&2
			COMPILE_FAIL=$((COMPILE_FAIL + 1))
		fi
	done
	echo "    compiled: ${COMPILE_OK} ok, ${COMPILE_FAIL} failed, ${RECIPE_COUNT} total"
else
	# Count recipes without compiling
	for recipe in "${RECIPES_DIR}"/*.json; do
		[ -f "${recipe}" ] || continue
		RECIPE_COUNT=$((RECIPE_COUNT + 1))
	done
fi

# ── Step 2: Collect recipe metadata ─────────────────────────────────
# Format: id|name|auth_type|domain|credentials|reliability (pipe-separated for safety)
RECIPES_DATA=""
AUTH_TYPES=""

for recipe in "${RECIPES_DIR}"/*.json; do
	[ -f "${recipe}" ] || continue
	_id="$(json_get "${recipe}" "id" 2>/dev/null || true)"
	_name="$(json_get "${recipe}" "name" 2>/dev/null || true)"
	_auth="$(json_get "${recipe}" "auth_type" 2>/dev/null || true)"
	_domain="$(json_get "${recipe}" "travelmate_domain" 2>/dev/null || true)"
	_creds="$(json_get "${recipe}" "credentials" 2>/dev/null || true)"
	[ -z "${_id}" ] && continue
	_rel="$(get_reliability "${_id}")"
	# Escape pipe chars in fields
	_esc_name="$(printf '%s' "${_name}" | tr '|' ' ')"
	_esc_domain="$(printf '%s' "${_domain}" | tr '|' ' ')"
	_esc_creds="$(printf '%s' "${_creds}" | tr '|' ' ')"
	RECIPES_DATA="${RECIPES_DATA}${_id}|${_esc_name}|${_auth}|${_esc_domain}|${_esc_creds}|${_rel}
"
	# Collect unique auth types
	if ! printf '%s\n' "${AUTH_TYPES}" | grep -qxF "${_auth}" 2>/dev/null; then
		AUTH_TYPES="${AUTH_TYPES}${_auth}
"
	fi
done

# Count unique auth types
AUTH_TYPE_COUNT=0
if [ -n "${AUTH_TYPES}" ]; then
	AUTH_TYPE_COUNT="$(printf '%s\n' "${AUTH_TYPES}" | grep -c .)"
fi

# ── Step 3: Generate HTML ────────────────────────────────────────────
HTML_FILE="${OUTPUT_DIR}/index.html"

# Build table rows
TABLE_ROWS=""
_row_num=0
printf '%s\n' "${RECIPES_DATA}" | while IFS='|' read -r _id _name _auth _domain _creds _rel; do
	[ -z "${_id}" ] && continue
	_row_num=$((_row_num + 1))

	# Reliability badge
	case "${_rel}" in
		HIGH)    _badge='<span class="badge badge-high">HIGH</span>' ;;
		MEDIUM)  _badge='<span class="badge badge-medium">MEDIUM</span>' ;;
		LOW)     _badge='<span class="badge badge-low">LOW</span>' ;;
		*)       _badge='<span class="badge badge-untested">UNTESTED</span>' ;;
	esac

	# Credentials display
	case "${_creds}" in
		none)           _cred_display='<span class="cred-none">none</span>' ;;
		username_password|userpass) _cred_display='user + pass' ;;
		username_only)  _cred_display='username' ;;
		password_only)  _cred_display='password' ;;
		*)              _cred_display="$(html_escape "${_creds}")" ;;
	esac

	_esc_name_html="$(html_escape "${_name}")"
	_esc_auth_html="$(html_escape "${_auth}")"
	_esc_domain_html="$(html_escape "${_domain}")"

	# Odd/even row class
	_cls="row-even"
	_mod=$((_row_num % 2))
	if [ "${_mod}" = "1" ]; then _cls="row-odd"; fi

	_js_arg="togglePreview(event,&quot;${_id}&quot;)"
	printf '      <tr class="%s"><td><a href="%s/%s.login" class="recipe-link" download>%s</a></td><td><code>%s</code></td><td><code class="domain">%s</code></td><td>%s</td><td>%s</td><td><a href="%s/%s.login" class="action-link" download>download</a>&#160;<a href="#" class="action-link preview-toggle" onclick="%s">preview</a></td></tr>\n' \
		"${_cls}" "${_LINK_PREFIX}" "${_id}" "${_esc_name_html}" "${_esc_auth_html}" "${_esc_domain_html}" "${_cred_display}" "${_badge}" "${_LINK_PREFIX}" "${_id}" "${_js_arg}"
	printf '      <tr class="preview-row" id="preview-%s"><td colspan="6"><button class="preview-close" onclick="closePreview(&quot;%s&quot;)">close</button><pre><code></code></pre></td></tr>\n' "${_id}" "${_id}"
done > "${PROJECT_DIR}/.pages-table-rows.$$"

# Generate the full HTML page
cat > "${HTML_FILE}" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
<title>Captive Portal Recipes</title>
<meta name="description" content="Template-based captive portal login recipes compiled for travelmate and similar platforms">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0d1117;--surface:#161b22;--border:#30363d;--text:#c9d1d9;
  --text-muted:#8b949e;--accent:#58a6ff;--accent-hover:#79c0ff;
  --green:#3fb950;--yellow:#d29922;--red:#f85149;--orange:#db6d28;
  --font:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;
  --mono:ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,monospace;
}
html{font-size:16px;-webkit-text-size-adjust:100%}
body{background:var(--bg);color:var(--text);font-family:var(--font);line-height:1.6;min-height:100vh}
.container{max-width:100%;margin:0 auto;padding:1.5rem 2rem}

/* Header */
header{text-align:center;padding:2.5rem 0 1.5rem;border-bottom:1px solid var(--border);margin-bottom:1.5rem}
header h1{font-size:1.75rem;font-weight:600;color:#f0f6fc;margin-bottom:.5rem;letter-spacing:-.02em}
header p{color:var(--text-muted);font-size:.95rem;max-width:520px;margin:0 auto .75rem}

/* Banner */
.banner{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:.75rem 1rem;margin-bottom:1.5rem;text-align:center;font-size:.8rem;color:var(--orange);font-weight:500;letter-spacing:.03em}

/* Stats */
.stats{display:flex;justify-content:center;gap:2rem;flex-wrap:wrap;margin-bottom:2rem;padding:1rem 0;border-bottom:1px solid var(--border)}
.stats .stat{text-align:center}
.stats .stat-value{font-size:1.5rem;font-weight:700;color:var(--accent);font-family:var(--mono)}
.stats .stat-label{font-size:.75rem;color:var(--text-muted);text-transform:uppercase;letter-spacing:.05em;margin-top:.15rem}

/* Table */
.table-wrap{overflow-x:auto;margin-bottom:2rem;border:1px solid var(--border);border-radius:8px}
table{width:100%;border-collapse:collapse;font-size:.875rem}
thead{background:var(--surface)}
th{padding:.6rem .75rem;text-align:left;font-weight:600;color:var(--text-muted);font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid var(--border);white-space:nowrap}
td{padding:.5rem .75rem;border-bottom:1px solid var(--border);vertical-align:middle}
tr:last-child td{border-bottom:none}
.row-odd{background:transparent}
.row-even{background:rgba(22,27,34,.4)}

/* Links */
a{color:var(--accent);text-decoration:none}
a:hover{color:var(--accent-hover);text-decoration:underline}
.recipe-link{font-weight:500}

/* Code */
code{font-family:var(--mono);font-size:.8rem;background:rgba(110,118,129,.15);padding:.15em .35em;border-radius:4px;color:var(--text)}
.domain{color:var(--text-muted);font-size:.75rem;word-break:break-all}

/* Badges */
.badge{display:inline-block;padding:.15em .5em;border-radius:12px;font-size:.7rem;font-weight:600;letter-spacing:.03em;text-transform:uppercase}
.badge-high{background:rgba(63,185,80,.15);color:var(--green);border:1px solid rgba(63,185,80,.3)}
.badge-medium{background:rgba(210,153,34,.15);color:var(--yellow);border:1px solid rgba(210,153,34,.3)}
.badge-low{background:rgba(248,81,73,.15);color:var(--red);border:1px solid rgba(248,81,73,.3)}
.badge-untested{background:rgba(139,148,158,.1);color:var(--text-muted);border:1px solid rgba(139,148,158,.2)}

.cred-none{color:var(--text-muted);font-size:.8rem}

.action-link{display:inline-block;font-size:.7rem;padding:.3em .6em;border-radius:4px;border:1px solid var(--border);background:var(--surface);color:var(--text-muted);white-space:nowrap;transition:background .15s,color .15s,border-color .15s;cursor:pointer;text-align:center;line-height:1.4}
.action-link:hover{color:var(--accent-hover);text-decoration:none;background:rgba(88,166,255,.1);border-color:rgba(88,166,255,.3)}
.action-link.active{color:var(--red);background:rgba(248,81,73,.12);border-color:rgba(248,81,73,.3)}

.active-row{background:rgba(88,166,255,.1)!important;border-left:2px solid var(--accent)}

.preview-row{display:none;background:var(--surface)}
.preview-row.open{display:table-row}
.preview-row td{padding:0;position:relative}
.preview-row pre{margin:0;padding:.75rem 1rem;overflow-x:auto;max-height:400px;overflow-y:auto}
.preview-row code{font-family:var(--mono);font-size:.75rem;line-height:1.5;color:var(--text);background:none;padding:0;white-space:pre}
.preview-close{position:absolute;top:.6rem;right:.6rem;font-size:.7rem;font-family:var(--font);padding:.3em .6em;border-radius:4px;background:var(--surface);border:1px solid var(--border);color:var(--text-muted);cursor:pointer;line-height:1.4;transition:color .15s,border-color .15s}
.preview-close:hover{color:var(--red);border-color:rgba(248,81,73,.4);background:rgba(248,81,73,.08)}

/* Footer */
footer{text-align:center;padding:1.5rem 0;border-top:1px solid var(--border);color:var(--text-muted);font-size:.8rem;line-height:1.8}
footer a{color:var(--text-muted)}
footer a:hover{color:var(--accent)}
.build-time{font-size:.7rem;color:rgba(139,148,158,.5);margin-top:.5rem}

/* Responsive */
@media(max-width:640px){
  .container{padding:1rem}
  header h1{font-size:1.3rem}
  .stats{gap:1rem}
  .stats .stat-value{font-size:1.2rem}
  table{font-size:.8rem}
  th,td{padding:.4rem .5rem}
  .domain{display:none}
}
</style>
</head>
<body>
<div class="container">
<header>
<h1>Captive Portal Recipes</h1>
<p>Template-based captive portal login recipes compiled for multiple targets</p>
</header>
<div class="banner">EXPERIMENTAL &#8212; AI-Generated &#8212; Not device-tested</div>
HTMLEOF

# Insert stats bar
printf '<div class="stats">\n' >> "${HTML_FILE}"
printf '  <div class="stat"><div class="stat-value">%d</div><div class="stat-label">Recipes</div></div>\n' "${RECIPE_COUNT}" >> "${HTML_FILE}"
printf '  <div class="stat"><div class="stat-value">%d</div><div class="stat-label">Auth Types</div></div>\n' "${AUTH_TYPE_COUNT}" >> "${HTML_FILE}"
printf '  <div class="stat"><div class="stat-value">1</div><div class="stat-label">Target (travelmate)</div></div>\n' >> "${HTML_FILE}"
printf '</div>\n' >> "${HTML_FILE}"

# Insert table
cat >> "${HTML_FILE}" << 'HTMLEOF2'
<div class="table-wrap">
<table>
<thead>
<tr><th>Name</th><th>Auth Type</th><th>Target Domain</th><th>Credentials</th><th>Reliability</th><th>Actions</th></tr>
</thead>
<tbody>
HTMLEOF2

# Insert pre-built table rows
cat "${PROJECT_DIR}/.pages-table-rows.$$" >> "${HTML_FILE}"
rm -f "${PROJECT_DIR}/.pages-table-rows.$$"

cat >> "${HTML_FILE}" << 'HTMLEOF3'
</tbody>
</table>
</div>
<footer>
<p><a href="https://github.com/Amperstrand/captive-portal-recipes">Amperstrand/captive-portal-recipes</a></p>
<p><a href="https://github.com/Amperstrand/captive-portal-recipes/blob/main/DISCLAIMER.md">Disclaimer</a> &#183; Licensed under <a href="https://www.gnu.org/licenses/gpl-3.0.en.html">GPL-3.0</a></p>
HTMLEOF3

printf '<p class="build-time">built: %s</p>\n' "$(date -u '+%Y-%m-%dT%H:%MZ')" >> "${HTML_FILE}"

cat >> "${HTML_FILE}" << 'HTMLEOF4'
</footer>
</div>
<script>
var cache={};
function closePreview(id){
  var row=document.getElementById('preview-'+id);
  if(!row)return;
  row.classList.remove('open');
  var parent=row.previousElementSibling;
  if(parent)parent.classList.remove('active-row');
  var link=parent?parent.querySelector('.preview-toggle'):null;
  if(link){link.textContent='preview';link.classList.remove('active');}
}
function togglePreview(e,id){
  e.preventDefault();
  var row=document.getElementById('preview-'+id);
  if(!row)return;
  if(row.classList.contains('open')){closePreview(id);return;}
  var allOpen=document.querySelectorAll('.preview-row.open');
  for(var i=0;i<allOpen.length;i++){
    var oid=allOpen[i].id.replace('preview-','');
    closePreview(oid);
  }
  row.classList.add('open');
  var parent=row.previousElementSibling;
  if(parent)parent.classList.add('active-row');
  var link=parent?parent.querySelector('.preview-toggle'):null;
  if(link){link.textContent='close';link.classList.add('active');}
  var code=row.querySelector('code');
  if(code.textContent)return;
  var src=parent.querySelector('.recipe-link').href;
  if(cache[id]){code.textContent=cache[id];return;}
  fetch(src).then(function(r){return r.text();}).then(function(t){cache[id]=t;code.textContent=t;}).catch(function(){code.textContent='Failed to load script';});
}
</script>
</body>
</html>
HTMLEOF4

# ── Summary ──────────────────────────────────────────────────────────
echo "Generated ${HTML_FILE} with ${RECIPE_COUNT} recipes"
