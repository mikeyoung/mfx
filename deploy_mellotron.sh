#!/usr/bin/env bash
# Deploy Mellotron Sound Effects to https://mikeyoung.org/mfx/ over explicit FTPS.
#
# This script is intentionally non-destructive: it uploads the current site but
# never lists or deletes remote files. Authentication is handled only by curl
# through C:/Users/mikey/.netrc; this script never reads or prints credentials.

set -euo pipefail

readonly SRC="M:/backup/webdev/chaotic sound effects"
readonly HOST="p1438.use1.mysecurecloudhost.com"
readonly REMOTE_DIR="/mfx"
readonly BASE="ftp://${HOST}${REMOTE_DIR}"
readonly LIVE="https://mikeyoung.org${REMOTE_DIR}/"
readonly NETRC="C:/Users/mikey/.netrc"
readonly PARALLEL_UPLOADS=4

if [[ "$REMOTE_DIR" != "/mfx" || "$BASE" != "ftp://${HOST}/mfx" ]]; then
  echo "ERROR: remote safety check failed; refusing to deploy." >&2
  exit 1
fi

for required in curl find xargs; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: $required" >&2
    exit 1
  }
done

[[ -d "$SRC/snd" ]] || { echo "ERROR: missing $SRC/snd" >&2; exit 1; }
for site_file in index.html sw.js manifest.webmanifest icon-192.png icon-512.png VERSION; do
  [[ -f "$SRC/$site_file" ]] || { echo "ERROR: missing $SRC/$site_file" >&2; exit 1; }
done
[[ -f "$NETRC" ]] || { echo "ERROR: missing credential file: $NETRC" >&2; exit 1; }

# A changed sound requires regenerating index.html and sw.js before deployment.
if [[ -n "$(find "$SRC/snd" -type f -newer "$SRC/index.html" -print -quit)" \
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
readonly FILE_LIST="$TMP_DIR/files.list"
readonly FAILURES="$TMP_DIR/failures.txt"
readonly FIRST_FAILURES="$TMP_DIR/failures.first.txt"
trap 'rm -rf -- "$TMP_DIR"' EXIT

cd "$SRC"
: > "$FAILURES"
{
  printf 'index.html\0sw.js\0manifest.webmanifest\0icon-192.png\0icon-512.png\0'
  find snd -type f -print0
} > "$FILE_LIST"

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

sound_count="$(find snd -type f | wc -l | tr -d '[:space:]')"
total=$((sound_count + 5))
echo "Uploading $total files to ${BASE}/ with $PARALLEL_UPLOADS connections..."

xargs -0 -P "$PARALLEL_UPLOADS" -I '{}' bash -c 'upload_one "$1"' _ '{}' < "$FILE_LIST"

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

echo "Verifying public deployment..."
verify_url "$LIVE" "/mfx/"
verify_url "${LIVE}sw.js" "/mfx/sw.js"
verify_url "${LIVE}manifest.webmanifest" "/mfx/manifest.webmanifest"

echo "DONE: uploaded $total/$total files to $LIVE"
