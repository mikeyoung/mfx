#!/usr/bin/env bash
# Deploy Chaotic Sound Effects to https://mikeyoung.org/csfx/ over explicit FTPS.
#
# This script is intentionally non-destructive: it uploads the current site but
# never lists or deletes remote files. Authentication is handled only by curl
# through C:/Users/mikey/.netrc; this script never reads or prints credentials.

set -euo pipefail
PATH="${BASH%/*}:$PATH"
export PATH

readonly SRC="M:/backup/webdev/chaotic sound effects"
readonly HOST="p1438.use1.mysecurecloudhost.com"
readonly REMOTE_DIR="/csfx"
readonly BASE="ftp://${HOST}${REMOTE_DIR}"
readonly LIVE="https://mikeyoung.org${REMOTE_DIR}/"
readonly NETRC="C:/Users/mikey/.netrc"
readonly PARALLEL_UPLOADS=4
readonly STATE_DIR="$SRC/.deploy-state"
readonly STATE_MANIFEST="$STATE_DIR/manifest-v1.tsv"
readonly MODE="${1:-deploy}"

if [[ "$MODE" != "deploy" && "$MODE" != "--plan" ]]; then
  echo "Usage: $0 [--plan]" >&2
  exit 2
fi

if [[ "$REMOTE_DIR" != "/csfx" || "$BASE" != "ftp://${HOST}/csfx" ]]; then
  echo "ERROR: remote safety check failed; refusing to deploy." >&2
  exit 1
fi

for required in awk cp curl find mkdir mktemp mv sed sha256sum tr wc xargs; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: $required" >&2
    exit 1
  }
done

[[ -d "$SRC/snd" ]] || { echo "ERROR: missing $SRC/snd" >&2; exit 1; }
for site_file in index.html sw.js manifest.webmanifest icon-192.png icon-512.png web.config sounds.pack VERSION; do
  [[ -f "$SRC/$site_file" ]] || { echo "ERROR: missing $SRC/$site_file" >&2; exit 1; }
done
if [[ "$MODE" == "deploy" ]]; then
  [[ -f "$NETRC" ]] || { echo "ERROR: missing credential file: $NETRC" >&2; exit 1; }
fi

# A changed sound requires regenerating index.html and sw.js before deployment.
if [[ -n "$(find "$SRC/snd" -type f -newer "$SRC/sounds.pack" -print -quit)" \
      || -n "$(find "$SRC/snd" -type f -newer "$SRC/index.html" -print -quit)" \
      || -n "$(find "$SRC/snd" -type f -newer "$SRC/sw.js" -print -quit)" ]]; then
  echo "ERROR: sound files are newer than index.html or sw.js; rebuild before deploying." >&2
  exit 1
fi
if [[ "$SRC/src/index.template.html" -nt "$SRC/index.html" \
      || "$SRC/src/sw.template.js" -nt "$SRC/sw.js" \
      || "$SRC/VERSION" -nt "$SRC/index.html" \
      || "$SRC/VERSION" -nt "$SRC/sw.js" \
      || "$SRC/manifest.webmanifest" -nt "$SRC/sw.js" \
      || "$SRC/icon-192.png" -nt "$SRC/sw.js" \
      || "$SRC/icon-512.png" -nt "$SRC/sw.js" ]]; then
  echo "ERROR: PWA sources are newer than generated output; rebuild before deploying." >&2
  exit 1
fi

readonly TMP_DIR="$(mktemp -d)"
readonly ALL_FILES="$TMP_DIR/all-files.list"
readonly FILE_LIST="$TMP_DIR/changed-files.list"
readonly CHANGED_LINES="$TMP_DIR/changed-files.txt"
readonly CURRENT_MANIFEST="$TMP_DIR/manifest-v1.tsv"
readonly FAILURES="$TMP_DIR/failures.txt"
readonly FIRST_FAILURES="$TMP_DIR/failures.first.txt"
trap 'rm -rf -- "$TMP_DIR"' EXIT

cd "$SRC"
: > "$FAILURES"
{
  printf 'index.html\0sw.js\0manifest.webmanifest\0icon-192.png\0icon-512.png\0web.config\0sounds.pack\0'
} > "$ALL_FILES"

: > "$CURRENT_MANIFEST"
xargs -0 sha256sum --zero -- < "$ALL_FILES" |
while IFS= read -r -d '' record; do
  digest="${record%% *}"
  relative="${record:66}"
  if [[ "$relative" == *$'\t'* || "$relative" == *$'\r'* || "$relative" == *$'\n'* ]]; then
    echo "ERROR: deployment paths may not contain tabs or newlines: $relative" >&2
    exit 1
  fi
  printf '%s\t%s\n' "$digest" "$relative" >> "$CURRENT_MANIFEST"
done

: > "$FILE_LIST"
if [[ -f "$STATE_MANIFEST" ]]; then
  awk -F '\t' '
    NR == FNR { deployed[$0] = 1; next }
    !($0 in deployed) { print $2 }
  ' "$STATE_MANIFEST" "$CURRENT_MANIFEST" > "$CHANGED_LINES"
else
  awk -F '\t' '{ print $2 }' "$CURRENT_MANIFEST" > "$CHANGED_LINES"
fi
changed_count="$(wc -l < "$CHANGED_LINES" | tr -d '[:space:]')"
while IFS= read -r relative; do
  printf '%s\0' "$relative" >> "$FILE_LIST"
done < "$CHANGED_LINES"

encode_url_path() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//' '/'%20'}"
  value="${value//'#'/'%23'}"
  value="${value//'&'/'%26'}"
  value="${value//'('/'%28'}"
  value="${value//')'/'%29'}"
  value="${value//'?'/'%3F'}"
  value="${value//'['/'%5B'}"
  value="${value//']'/'%5D'}"
  printf '%s' "$value"
}

upload_one() {
  local relative="$1"
  local encoded
  encoded="$(encode_url_path "$relative")"
  if ! curl -sS \
      --netrc-file "$NETRC" \
      --ssl-reqd \
      --ftp-create-dirs \
      --upload-file "$relative" \
      "$BASE/$encoded" >/dev/null; then
    printf '%s\n' "$relative" >> "$FAILURES"
  fi
}

export BASE NETRC FAILURES
export -f encode_url_path upload_one

total=7
if [[ -f "$STATE_MANIFEST" ]]; then
  echo "Uploading $changed_count modified file(s) out of $total to ${BASE}/ with $PARALLEL_UPLOADS connections..."
else
  echo "No successful deployment state found; uploading all $total files to ${BASE}/..."
fi

if [[ "$MODE" == "--plan" ]]; then
  echo "PLAN: $changed_count of $total files would be uploaded."
  exit 0
fi

if (( changed_count > 0 )); then
  xargs -0 -P "$PARALLEL_UPLOADS" -I '{}' "$BASH" -c 'upload_one "$1"' _ '{}' < "$FILE_LIST"
fi

if [[ -s "$FAILURES" ]]; then
  first_failure_count="$(wc -l < "$FAILURES" | tr -d '[:space:]')"
  echo "Retrying $first_failure_count failed upload(s) sequentially..."
  mv "$FAILURES" "$FIRST_FAILURES"
  : > "$FAILURES"
  while IFS= read -r relative; do
    upload_one "$relative"
  done < "$FIRST_FAILURES"
fi

if [[ -s "$FAILURES" ]]; then
  failure_count="$(wc -l < "$FAILURES" | tr -d '[:space:]')"
  echo "ERROR: $failure_count upload(s) still failed:" >&2
  sed 's/^/  /' "$FAILURES" >&2
  exit 1
fi

verify_url() {
  local url="$1"
  local label="$2"
  local result
  result="$(curl -sS -m 30 -o /dev/null \
    -w '%{http_code} %{content_type} %{size_download}' "$url")"
  echo "$label -> HTTP $result"
  [[ "${result%% *}" == "200" ]]
}

verify_head_url() {
  local url="$1"
  local label="$2"
  local result
  result="$(curl -sS -m 30 -I -o /dev/null \
    -w '%{http_code} %{content_type}' "$url")"
  echo "$label -> HTTP $result"
  [[ "${result%% *}" == "200" ]]
}

echo "Verifying public deployment..."
verify_url "$LIVE" "/csfx/"
verify_url "${LIVE}sw.js" "/csfx/sw.js"
verify_url "${LIVE}manifest.webmanifest" "/csfx/manifest.webmanifest"
verify_head_url "${LIVE}sounds.pack" "/csfx/sounds.pack"

mkdir -p "$STATE_DIR"
cp -- "$CURRENT_MANIFEST" "$STATE_MANIFEST.tmp"
mv -f -- "$STATE_MANIFEST.tmp" "$STATE_MANIFEST"

echo "DONE: uploaded $changed_count modified file(s) out of $total to $LIVE"
