#!/usr/bin/env bash
# Run lifeboat's tests. Mirrors the jobs in .github/workflows/ci.yml so that
# "passes locally" == "passes CI".
#
# Usage:
#   ./test.bash            lint + unit (default)
#   ./test.bash --lint     bash -n + shellcheck
#   ./test.bash --unit     bats suite (tests/lifeboat.bats)
#   ./test.bash --all      lint + unit
#   ./test.bash -h|--help  this help

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

need() {
    command -v "$1" >/dev/null 2>&1 ||
        { echo "test.bash: missing dependency: $1" >&2; return 1; }
}

run_lint() {
    echo "=== lint ==="
    need bash
    need shellcheck
    bash -n lifeboat
    bash -n test.bash
    shellcheck -S warning lifeboat test.bash
}

run_unit() {
    echo "=== unit (bats) ==="
    need bats
    need tar
    need gzip
    bats tests/lifeboat.bats
}

main() {
    local mode="${1:-default}"
    case "$mode" in
        --lint) run_lint ;;
        --unit) run_unit ;;
        --all)
            run_lint
            run_unit
            ;;
        default)
            run_lint
            run_unit
            ;;
        -h | --help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "test.bash: unknown option: $mode" >&2
            exit 2
            ;;
    esac
    echo
    echo "OK"
}

main "$@"
