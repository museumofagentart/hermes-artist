#!/usr/bin/env bash
# Test helpers for artist skill
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIST_DIR="$(cd "$TEST_DIR/.." && pwd)"
WORKS_DIR="$ARTIST_DIR/works"
TEST_PIECES_DIR="$WORKS_DIR"

PASSED=0
FAILED=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_eq}"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $msg"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAILED=$((FAILED + 1))
  fi
}

assert_json_valid() {
  local file="$1"
  local msg="${2:-assert_json_valid}"
  if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
    echo "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $msg"
    echo "    invalid JSON: $file"
    FAILED=$((FAILED + 1))
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local msg="${1:-assert_exit_code}"
  shift
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $msg"
    echo "    expected exit code: $expected"
    echo "    actual exit code:   $actual"
    FAILED=$((FAILED + 1))
  fi
}

setup_test_piece() {
  local id="${1:-$(date +%Y%m%d-%H%M%S)-0000-test-piece}"
  local piece_dir="$TEST_PIECES_DIR/$id"
  mkdir -p "$piece_dir/thumbs" "$piece_dir/intermediates"
  cat > "$piece_dir/meta.json" <<EOF
{
  "schema_version": "1",
  "id": "$id",
  "title": "Test Piece",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)",
  "seed": "test seed",
  "medium": "image/png",
  "output_file": "output.png",
  "tools_used": ["pillow"],
  "revision_of": null,
  "references": [],
  "patron_feedback": {
    "favorite": false,
    "favorite_at": null,
    "discouraged": false,
    "discouraged_at": null,
    "comments": []
  }
}
EOF
  printf '\x89PNG\r\n\x1a\n' > "$piece_dir/output.png"
  echo "$piece_dir"
}

teardown_test_pieces() {
  # Remove pieces created by setup_test_piece (match *-test-piece*)
  for d in "$TEST_PIECES_DIR"/*-test-piece*; do
    if [[ -d "$d" ]]; then
      rm -rf "$d"
    fi
  done
}

report_results() {
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

export TEST_DIR ARTIST_DIR WORKS_DIR TEST_PIECES_DIR
export -f assert_eq assert_json_valid assert_exit_code setup_test_piece teardown_test_pieces report_results
export PASSED FAILED
