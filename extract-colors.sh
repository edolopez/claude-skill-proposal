#!/usr/bin/env bash
# extract-colors.sh — Multi-source brand color extraction.
#
# Usage: bash extract-colors.sh https://acme.com
#
# Sources, in priority order:
#   1. <meta name="theme-color">           — most reliable, often the truest brand color
#   2. CSS custom properties named --primary, --brand, --accent
#   3. Inline SVG fill/stroke colors        — captures logo color
#   4. Linked SVG files (sampled by curl)   — captures external logos
#   5. Hex/RGB/HSL frequency in inline + linked CSS — falls back to bulk frequency
#
# Filters: drops pure black/white, near-greys (unless very common), and very
# light/dark colors that are typically backgrounds. Outputs candidates with
# their detected source so the seller can pick with context.
#
# Best-effort. Fails gracefully — if every source returns nothing, prints a
# hint and exits 0 so the caller can fall back to WebFetch visual inspection.

set -uo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "Usage: bash extract-colors.sh <url>" >&2
  exit 1
fi

if [[ ! "$URL" =~ ^https?:// ]]; then
  URL="https://$URL"
fi

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HTML="$TMPDIR/page.html"
ALLCSS="$TMPDIR/all.css"
ALLSVG="$TMPDIR/all.svg"
CANDIDATES="$TMPDIR/candidates.txt"
: > "$CANDIDATES"

# Fetch homepage
if ! curl -sSL --max-time 15 -A "$UA" -o "$HTML" "$URL"; then
  echo "Could not fetch $URL — site may block curl. Use WebFetch instead." >&2
  exit 0
fi

if [[ ! -s "$HTML" ]]; then
  echo "Empty response from $URL." >&2
  exit 0
fi

BASE="$(echo "$URL" | sed -E 's|^(https?://[^/]+).*|\1|')"

# Helper: normalize a color string to lowercase 6-digit hex, or empty if unparseable
normalize_hex() {
  local c="$1"
  c="$(echo "$c" | tr 'A-F' 'a-f' | tr -d ' ')"
  if [[ "$c" =~ ^#?([0-9a-f]{6})$ ]]; then
    echo "#${BASH_REMATCH[1]}"
  elif [[ "$c" =~ ^#?([0-9a-f])([0-9a-f])([0-9a-f])$ ]]; then
    echo "#${BASH_REMATCH[1]}${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[3]}"
  fi
}

# ───────────────────────────────────────────────
# SOURCE 1: <meta name="theme-color">
# ───────────────────────────────────────────────
THEME_COLOR=$(grep -oiE '<meta[^>]+name="theme-color"[^>]+>' "$HTML" 2>/dev/null \
  | grep -oiE 'content="[^"]+"' \
  | head -1 \
  | sed -E 's/content="([^"]+)"/\1/')
if [[ -n "$THEME_COLOR" ]]; then
  normalized=$(normalize_hex "$THEME_COLOR")
  [[ -n "$normalized" ]] && echo "theme-color $normalized 100" >> "$CANDIDATES"
fi

# ───────────────────────────────────────────────
# Collect inline + external CSS
# ───────────────────────────────────────────────
awk 'BEGIN{p=0} /<style[^>]*>/{p=1; sub(/.*<style[^>]*>/,""); print; next} /<\/style>/{sub(/<\/style>.*/,""); print; p=0; next} p{print}' "$HTML" > "$ALLCSS"

STYLESHEETS=$(grep -oiE '<link[^>]+rel="stylesheet"[^>]*>' "$HTML" \
  | grep -oiE 'href="[^"]+"' \
  | sed -E 's/href="([^"]+)"/\1/' \
  | head -8)

while IFS= read -r href; do
  [[ -z "$href" ]] && continue
  if [[ "$href" =~ ^// ]]; then
    href="https:$href"
  elif [[ "$href" =~ ^/ ]]; then
    href="${BASE}${href}"
  elif [[ ! "$href" =~ ^https?:// ]]; then
    href="${BASE}/${href#./}"
  fi
  curl -sSL --max-time 8 -A "$UA" "$href" >> "$ALLCSS" 2>/dev/null || true
  echo "" >> "$ALLCSS"
done <<< "$STYLESHEETS"

# Also include the raw HTML so inline-style colors are caught
cat "$HTML" >> "$ALLCSS"

# ───────────────────────────────────────────────
# SOURCE 2: CSS custom properties --primary/--brand/--accent
# ───────────────────────────────────────────────
CSS_VARS=$(grep -oiE -- '--(primary|brand|accent|theme|main)(-[a-z0-9]+)?\s*:\s*#[0-9a-f]{3,6}' "$ALLCSS" 2>/dev/null \
  | sed -E 's/.*(#[0-9a-f]{3,6}).*/\1/' \
  | tr 'A-F' 'a-f')

while IFS= read -r hex; do
  [[ -z "$hex" ]] && continue
  normalized=$(normalize_hex "$hex")
  [[ -n "$normalized" ]] && echo "css-var $normalized 50" >> "$CANDIDATES"
done <<< "$CSS_VARS"

# ───────────────────────────────────────────────
# SOURCE 3: Inline SVG fills (logo colors)
# ───────────────────────────────────────────────
SVG_FILLS=$(grep -oiE 'fill="#[0-9a-f]{3,6}"' "$HTML" 2>/dev/null \
  | sed -E 's/fill="(#[0-9a-f]{3,6})"/\1/' \
  | tr 'A-F' 'a-f')

while IFS= read -r hex; do
  [[ -z "$hex" ]] && continue
  normalized=$(normalize_hex "$hex")
  [[ -n "$normalized" ]] && echo "svg-fill $normalized 30" >> "$CANDIDATES"
done <<< "$SVG_FILLS"

# ───────────────────────────────────────────────
# SOURCE 4: Linked SVG files (download and parse)
# ───────────────────────────────────────────────
SVG_LINKS=$(grep -oiE '(src|href)="[^"]+\.svg[^"]*"' "$HTML" 2>/dev/null \
  | sed -E 's/(src|href)="([^"]+)"/\2/' \
  | head -3)

while IFS= read -r svg_path; do
  [[ -z "$svg_path" ]] && continue
  if [[ "$svg_path" =~ ^// ]]; then
    svg_path="https:$svg_path"
  elif [[ "$svg_path" =~ ^/ ]]; then
    svg_path="${BASE}${svg_path}"
  elif [[ ! "$svg_path" =~ ^https?:// ]]; then
    svg_path="${BASE}/${svg_path#./}"
  fi
  curl -sSL --max-time 5 -A "$UA" "$svg_path" 2>/dev/null >> "$ALLSVG" || true
  echo "" >> "$ALLSVG"
done <<< "$SVG_LINKS"

if [[ -s "$ALLSVG" ]]; then
  EXT_SVG_FILLS=$(grep -oiE 'fill="#[0-9a-f]{3,6}"|stop-color="#[0-9a-f]{3,6}"' "$ALLSVG" 2>/dev/null \
    | sed -E 's/(fill|stop-color)="(#[0-9a-f]{3,6})"/\2/' \
    | tr 'A-F' 'a-f')
  while IFS= read -r hex; do
    [[ -z "$hex" ]] && continue
    normalized=$(normalize_hex "$hex")
    [[ -n "$normalized" ]] && echo "svg-logo $normalized 25" >> "$CANDIDATES"
  done <<< "$EXT_SVG_FILLS"
fi

# ───────────────────────────────────────────────
# SOURCE 5: Bulk hex frequency in CSS
# ───────────────────────────────────────────────
HEXES=$(grep -oiE '#[0-9a-f]{6}\b|#[0-9a-f]{3}\b' "$ALLCSS" 2>/dev/null \
  | tr 'A-F' 'a-f' \
  | awk '{
      h=$0
      if (length(h)==4) {
        r=substr(h,2,1); g=substr(h,3,1); b=substr(h,4,1)
        printf "#%s%s%s%s%s%s\n", r,r,g,g,b,b
      } else { print h }
    }')

if [[ -n "$HEXES" ]]; then
  echo "$HEXES" | sort | uniq -c | sort -rn | head -20 | awk '{ printf "css-freq %s %d\n", $2, $1 }' >> "$CANDIDATES"
fi

# ───────────────────────────────────────────────
# Aggregate, filter, score
# ───────────────────────────────────────────────
if [[ ! -s "$CANDIDATES" ]]; then
  echo "No colors found for $URL." >&2
  echo "Use WebFetch on the homepage to inspect colors visually." >&2
  exit 0
fi

# Filter: drop pure black/white, near-greys with low frequency, near-whites
# Score: weighted sum, prioritizing semantic sources
awk '
  function hex2dec(s,    i,c,n,v) {
    n=0
    for (i=1;i<=length(s);i++){
      c=tolower(substr(s,i,1))
      if (c>="0"&&c<="9") v=c+0
      else v=index("abcdef",c)+9
      n=n*16+v
    }
    return n
  }
  {
    source=$1; hex=$2; weight=$3
    r=hex2dec(substr(hex,2,2)); g=hex2dec(substr(hex,4,2)); b=hex2dec(substr(hex,6,2))
    if (hex=="#000000" || hex=="#ffffff") next

    maxc=r; if (g>maxc) maxc=g; if (b>maxc) maxc=b
    minc=r; if (g<minc) minc=g; if (b<minc) minc=b
    chroma=maxc-minc
    luminance = (r*0.299 + g*0.587 + b*0.114)

    is_gray=(chroma<12)
    is_near_white=(luminance>240)
    is_near_black=(luminance<20)

    if (is_gray && weight<10) next
    if (is_near_white && weight<20) next
    if (is_near_black && weight<10) next

    # Aggregate by hex, summing weights and tracking sources
    sources[hex] = (hex in sources ? sources[hex] "," source : source)
    weights[hex] = (hex in weights ? weights[hex]+weight : weight)
    rgbs[hex] = sprintf("%3d,%3d,%3d", r, g, b)
  }
  END {
    for (h in weights) {
      printf "%d|%s|%s|%s\n", weights[h], h, rgbs[h], sources[h]
    }
  }
' "$CANDIDATES" | sort -t'|' -k1 -rn | head -10 | awk -F'|' '
  # Approximate relative luminance via the standard YIQ formula.
  # Good enough to distinguish colors that need white vs dark text on top.
  function luminance_approx(rs,    n,r,g,b) {
    n = split(rs, parts, ",")
    r = parts[1]+0; g = parts[2]+0; b = parts[3]+0
    return (0.299*r + 0.587*g + 0.114*b) / 255
  }
  BEGIN { print "Brand color candidates (highest signal first):"; print "" }
  {
    weight=$1; hex=$2; rgb=$3; sources=$4
    L = luminance_approx(rgb)
    if (L > 0.62)        flag = "⚠ too light for white CTA text — pair with dark text"
    else if (L > 0.45)   flag = "⚠ marginal contrast on white CTA — verify"
    else                 flag = "✓ safe for white CTA text"
    printf "  %-9s rgb(%s)   %-12s %s\n", hex, rgb, sources, flag
  }
  END {
    print ""
    print "Pick one PRIMARY (CTA + price + 1-2 emphasis) and one ACCENT (rare)."
    print "Restraint matters more than precision. Heed the contrast flag — a primary"
    print "color used on the CTA needs WCAG AA contrast (luminance ≲ 0.45 with white text)."
  }
'
