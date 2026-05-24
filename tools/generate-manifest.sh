#!/bin/sh
# generate-manifest.sh — Extract match data from all recipes into a single manifest
#
# Outputs match-manifest.json containing a lookup table for auto-detection:
#   { "<recipe-id>": { "ssids": [...], "domains": [...], "paths": [...], ... } }
#
# Usage: tools/generate-manifest.sh [OPTIONS]
#
# Options:
#   --recipes-dir <dir>    Recipe JSON directory (default: recipes/)
#   --output <file>        Output file (default: match-manifest.json)
#   --help                 Show this help
set -e

# ── Defaults ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RECIPES_DIR="recipes"
OUTPUT_FILE="match-manifest.json"

# ── Argument parsing ─────────────────────────────────────────────────
show_usage() {
	echo "usage: $(basename "$0") [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --recipes-dir <dir>    Recipe JSON directory (default: recipes/)"
	echo "  --output <file>        Output JSON file (default: match-manifest.json)"
	echo "  --help                 Show this help"
}

while [ $# -gt 0 ]; do
	case "$1" in
		--recipes-dir) RECIPES_DIR="$2"; shift 2 ;;
		--output) OUTPUT_FILE="$2"; shift 2 ;;
		--help) show_usage; exit 0 ;;
		-*) echo "error: unknown option '$1'" >&2; exit 1 ;;
		*) echo "error: unexpected argument '$1'" >&2; exit 1 ;;
	esac
done

cd "${PROJECT_DIR}"

if [ ! -d "${RECIPES_DIR}" ]; then
	echo "error: recipes directory not found: ${RECIPES_DIR}" >&2; exit 1
fi

# ── Extract match data from all recipes via awk ──────────────────────
# Each recipe JSON has a "match" object. We extract it using awk.

echo '{' > "${OUTPUT_FILE}"
_first=1

for recipe_file in "${RECIPES_DIR}"/*.json; do
	[ -f "${recipe_file}" ] || continue

	# Extract recipe ID
	recipe_id="$(awk '
		{ gsub(/[[:space:]]+/, " "); line = line " " $0 }
		END {
			pos = index(line, "\"id\""); if (pos == 0) exit 1
			rest = substr(line, pos + 4)
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
			}
		}
	' "${recipe_file}" 2>/dev/null)" || continue

	[ -z "${recipe_id}" ] && continue

	# Extract the match object as raw JSON text
	match_json="$(awk '
		{ gsub(/[[:space:]]+/, " "); line = line " " $0 }
		END {
			pos = index(line, "\"match\""); if (pos == 0) { print "{}"; exit 0 }
			rest = substr(line, pos + 7)
			sub(/^[[:space:]]*:[[:space:]]*/, "", rest)
			if (substr(rest, 1, 1) != "{") { print "{}"; exit 0 }
			# Find matching closing brace
			depth = 0; result = ""
			for (i = 1; i <= length(rest); i++) {
				c = substr(rest, i, 1)
				result = result c
				if (c == "{") depth++
				else if (c == "}") { depth--; if (depth == 0) break }
			}
			print result
		}
	' "${recipe_file}" 2>/dev/null)" || match_json="{}"

	# Pretty-format the match object with proper indentation
	# Use awk to re-indent the JSON
	formatted="$(printf '%s' "${match_json}" | awk '
		BEGIN { indent = 0 }
		{
			n = split($0, chars, "")
			for (i = 1; i <= n; i++) {
				c = chars[i]
				if (c == "{" || c == "[") {
					printf "%s\n", c
					indent++
					for (j = 0; j < indent; j++) printf "  "
				} else if (c == "}" || c == "]") {
					printf "\n"
					indent--
					for (j = 0; j < indent; j++) printf "  "
					printf "%s", c
				} else if (c == ",") {
					printf "%s\n", c
					for (j = 0; j < indent; j++) printf "  "
				} else {
					printf "%s", c
				}
			}
		}
	')"

	# Write entry
	if [ "${_first}" = "1" ]; then
		_first=0
	else
		printf ',\n' >> "${OUTPUT_FILE}"
	fi

	# Use printf to write indented entry
	printf '  "%s": %s' "${recipe_id}" "${formatted}" >> "${OUTPUT_FILE}"
done

printf '\n}\n' >> "${OUTPUT_FILE}"

# ── Count and report ─────────────────────────────────────────────────
_count="$(ls "${RECIPES_DIR}"/*.json 2>/dev/null | wc -l | tr -d ' ')"
echo "Generated ${OUTPUT_FILE} with ${_count} recipe match entries"
