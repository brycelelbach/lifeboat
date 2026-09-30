#!/usr/bin/env bats
#
# Unit tests for the lifeboat backup script. Each test builds a small fixture
# tree, runs lifeboat against it, and asserts on the produced archive's
# contents — so "what gets kept vs dropped" is pinned down precisely.

setup() {
    LIFEBOAT="${BATS_TEST_DIRNAME}/../lifeboat"
    [ -x "$LIFEBOAT" ] || chmod +x "$LIFEBOAT"

    SRC="$(mktemp -d)"
    OUT="$(mktemp -d)"
    export OUT_DIR="$OUT"
}

teardown() {
    rm -rf "$SRC" "$OUT"
}

# List the regular-file members of the single .tar.gz in $OUT (paths relative
# to the backed-up directory's parent), sorted.
archive_files() {
    local tgz
    tgz="$(find "$OUT" -maxdepth 1 -name '*.tar.gz' | head -1)"
    [ -n "$tgz" ] || return 1
    tar -tzf "$tgz" | grep -v '/$' | sort
}

# --- argument handling -----------------------------------------------------

@test "fails without a name" {
    run env SRC="$SRC" "$LIFEBOAT"
    [ "$status" -eq 64 ]
}

@test "rejects a legacy separate name and tag" {
    run env SRC="$SRC" "$LIFEBOAT" myhost eigh
    [ "$status" -eq 64 ]
    [[ "$output" == *"need exactly one <name>"* ]]
}

@test "rejects names containing a path separator" {
    run env SRC="$SRC" "$LIFEBOAT" brev/env
    [ "$status" -eq 64 ]
    [[ "$output" == *"<name> must not contain '/'"* ]]
}

@test "--help prints usage and exits 0" {
    run "$LIFEBOAT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"lifeboat <name>"* ]]
    [[ "$output" == *"brev-<env-name>-<env-8char-id>"* ]]
    [[ "$output" != *"<tag>"* ]]
    [[ "$output" != *"set -u"* ]]
}

@test "fails when SRC is not a directory" {
    run env SRC="$SRC/does-not-exist" "$LIFEBOAT" host
    [ "$status" -eq 1 ]
}

# --- archive naming --------------------------------------------------------

@test "archive is named lifeboat-<name>-YYYY-MM-DD-HH-MM-SS.tar.gz" {
    echo hi >"$SRC/file.txt"
    run env SRC="$SRC" "$LIFEBOAT" myhost-eigh
    [ "$status" -eq 0 ]
    local tgz
    tgz="$(basename "$(find "$OUT" -name '*.tar.gz')")"
    [[ "$tgz" =~ ^lifeboat-myhost-eigh-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.gz$ ]]
}

# --- keep real content -----------------------------------------------------

@test "keeps source, docs, images, and .git history" {
    mkdir -p "$SRC/repo/.git/objects/pack"
    echo 'int main(){}' >"$SRC/repo/main.cpp"
    echo 'kernel'       >"$SRC/repo/k.cu"
    printf '\x89PNG'    >"$SRC/repo/diagram.png"
    echo 'doc'          >"$SRC/repo/README.md"
    echo 'packdata'     >"$SRC/repo/.git/objects/pack/p.pack"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"repo/main.cpp"* ]]
    [[ "$output" == *"repo/k.cu"* ]]
    [[ "$output" == *"repo/diagram.png"* ]]
    [[ "$output" == *"repo/README.md"* ]]
    [[ "$output" == *"repo/.git/objects/pack/p.pack"* ]]
}

@test "keeps empty files (e.g. __init__.py, .gitkeep)" {
    mkdir -p "$SRC/pkg"
    : >"$SRC/pkg/__init__.py"
    : >"$SRC/.gitkeep"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"pkg/__init__.py"* ]]
    [[ "$output" == *".gitkeep"* ]]
}

# --- drop regenerable bulk -------------------------------------------------

@test "drops build artifacts by extension at any depth" {
    mkdir -p "$SRC/a/b/c"
    echo x >"$SRC/top.o"
    echo x >"$SRC/a/lib.so"
    echo x >"$SRC/a/b/kernel.cubin"
    echo x >"$SRC/a/b/c/mod.ptx"
    echo x >"$SRC/a/b/c/keep.cpp"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" != *".o"* ]]
    [[ "$output" != *".so"* ]]
    [[ "$output" != *".cubin"* ]]
    [[ "$output" != *".ptx"* ]]
    [[ "$output" == *"a/b/c/keep.cpp"* ]]
}

@test "drops Rust compiler artifacts and renamed compilation caches" {
    mkdir -p "$SRC/project/cargo-target/debug/incremental/crate/hash" \
             "$SRC/project/custom-build/debug/deps"
    printf source >"$SRC/project/kernel.rs"
    printf library >"$SRC/project/custom-build/debug/deps/libkernel.rlib"
    printf metadata >"$SRC/project/custom-build/debug/deps/libkernel.rmeta"
    printf graph >"$SRC/project/cargo-target/debug/incremental/crate/hash/dep-graph.bin"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"/project/kernel.rs"* ]]
    [[ "$output" != *".rlib"* ]]
    [[ "$output" != *".rmeta"* ]]
    [[ "$output" != *"/cargo-target/"* ]]
    [[ "$output" != *"/incremental/"* ]]
}

@test "drops embedded Rust and CUDA toolchains" {
    mkdir -p "$SRC/run/scratch_toolchain/cuda-root/bin" \
             "$SRC/run/.cutile-toolchain/rustup/toolchains/stable/bin" \
             "$SRC/run/vendor/rustup/toolchains/stable/bin" \
             "$SRC/run/vendor/cargo/registry/cache" \
             "$SRC/run/vendor/cuda-root/bin"
    printf source >"$SRC/run/solution.py"
    printf compiler >"$SRC/run/scratch_toolchain/cuda-root/bin/nvcc"
    printf compiler >"$SRC/run/.cutile-toolchain/rustup/toolchains/stable/bin/rustc"
    printf compiler >"$SRC/run/vendor/rustup/toolchains/stable/bin/rustc"
    printf package >"$SRC/run/vendor/cargo/registry/cache/crate"
    printf compiler >"$SRC/run/vendor/cuda-root/bin/nvcc"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"/run/solution.py"* ]]
    [[ "$output" != *"/scratch_toolchain/"* ]]
    [[ "$output" != *"/.cutile-toolchain/"* ]]
    [[ "$output" != *"/rustup/toolchains/"* ]]
    [[ "$output" != *"/cargo/registry/"* ]]
    [[ "$output" != *"/cuda-root/"* ]]
}

@test "drops build/, caches, and virtualenvs by directory" {
    mkdir -p "$SRC/proj/build" "$SRC/proj/.cache" \
             "$SRC/proj/.venv/lib" "$SRC/proj/__pycache__" \
             "$SRC/proj/node_modules" "$SRC/proj/.triton" "$SRC/proj/src"
    echo x >"$SRC/proj/build/out.bin"
    echo x >"$SRC/proj/.cache/blob"
    echo x >"$SRC/proj/.venv/lib/pkg.py"
    echo x >"$SRC/proj/__pycache__/m.pyc"
    echo x >"$SRC/proj/node_modules/dep.js"
    echo x >"$SRC/proj/.triton/kernel.bin"
    echo x >"$SRC/proj/src/real.py"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" != *"/build/"* ]]
    [[ "$output" != *"/.cache/"* ]]
    [[ "$output" != *"/.venv/"* ]]
    [[ "$output" != *"/__pycache__/"* ]]
    [[ "$output" != *"/node_modules/"* ]]
    [[ "$output" != *"/.triton/"* ]]
    # the real source next to all that junk survives
    [[ "$output" == *"proj/src/real.py"* ]]
}

@test "drops binary profiler captures but KEEPS text summaries in profiles/" {
    mkdir -p "$SRC/proj/profiles/run1"
    # bulky binary captures — dropped by extension
    echo x >"$SRC/proj/profiles/run1/trace.nsys-rep"
    echo x >"$SRC/proj/profiles/run1/kernel.ncu-rep"
    echo x >"$SRC/proj/profiles/run1/trace.sqlite"
    # hand-written / text measurement artifacts next to them — KEPT
    echo note >"$SRC/proj/profiles/run1/CAPSTONE-SUMMARY.md"
    echo cols >"$SRC/proj/profiles/run1/kernel.ncu-txt"
    echo cols >"$SRC/proj/profiles/run1/timeline.nsys-txt"
    echo a,b  >"$SRC/proj/profiles/run1/metrics.csv"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    # bulky binaries gone
    [[ "$output" != *".nsys-rep"* ]]
    [[ "$output" != *".ncu-rep"* ]]
    [[ "$output" != *".sqlite"* ]]
    # non-regenerable text survives — this is the whole point
    [[ "$output" == *"profiles/run1/CAPSTONE-SUMMARY.md"* ]]
    [[ "$output" == *"profiles/run1/kernel.ncu-txt"* ]]
    [[ "$output" == *"profiles/run1/timeline.nsys-txt"* ]]
    [[ "$output" == *"profiles/run1/metrics.csv"* ]]
}

@test "drops installed toolchains, package stores, and duplicate pane capture" {
    mkdir -p "$SRC/.rustup/toolchains/stable/bin" \
             "$SRC/.cargo/registry/cache" "$SRC/.npm/_cacache/content" \
             "$SRC/.codex/packages/standalone/bin" \
             "$SRC/.local/share/aab/node/bin" "$SRC/.local/share/claude/versions" \
             "$SRC/.local/share/uv/python/bin" "$SRC/.local/bin" \
             "$SRC/breval-run" "$SRC/.codex/sessions" "$SRC/project/.git/objects/pack"
    printf x >"$SRC/.rustup/toolchains/stable/bin/rustc"
    printf x >"$SRC/.cargo/registry/cache/crate"
    printf x >"$SRC/.npm/_cacache/content/blob"
    printf x >"$SRC/.codex/packages/standalone/bin/codex"
    printf x >"$SRC/.local/share/aab/node/bin/node"
    printf x >"$SRC/.local/share/claude/versions/claude"
    printf x >"$SRC/.local/share/uv/python/bin/python"
    printf x >"$SRC/.local/bin/tool"
    printf x >"$SRC/breval-run/harness-pane.raw"
    printf session >"$SRC/.codex/sessions/run.jsonl"
    printf history >"$SRC/project/.git/objects/pack/run.pack"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" != *"/.rustup/toolchains/"* ]]
    [[ "$output" != *"/.cargo/registry/"* ]]
    [[ "$output" != *"/.npm/_cacache/"* ]]
    [[ "$output" != *"/.codex/packages/"* ]]
    [[ "$output" != *"/.local/share/aab/"* ]]
    [[ "$output" != *"/.local/share/claude/"* ]]
    [[ "$output" != *"/.local/share/uv/"* ]]
    [[ "$output" != *"/.local/bin/"* ]]
    [[ "$output" != *"/breval-run/harness-pane.raw"* ]]
    [[ "$output" == *"/.codex/sessions/run.jsonl"* ]]
    [[ "$output" == *"/project/.git/objects/pack/run.pack"* ]]
}

@test "drops generated compiler state and duplicate KernelBench output" {
    mkdir -p "$SRC/project/src" "$SRC/project/target/debug" \
             "$SRC/project/.scratch/toolchain" "$SRC/.codex/.tmp/plugins" \
             "$SRC/.cargo/cuda-oxide/src" "$SRC/.pi/agent/git/repo" \
             "$SRC/kernelbench-hard-eval/outputs/runs/run" \
             "$SRC/breval-run/kernelbench-result"
    printf source >"$SRC/project/src/kernel.rs"
    printf object >"$SRC/project/target/debug/kernel.o"
    printf scratch >"$SRC/project/.scratch/toolchain/rustc"
    printf plugin >"$SRC/.codex/.tmp/plugins/plugin"
    printf clone >"$SRC/.cargo/cuda-oxide/src/lib.rs"
    printf clone >"$SRC/.pi/agent/git/repo/file"
    printf duplicate >"$SRC/kernelbench-hard-eval/outputs/runs/run/result.json"
    printf result >"$SRC/breval-run/kernelbench-result/result.json"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"/project/src/kernel.rs"* ]]
    [[ "$output" == *"/breval-run/kernelbench-result/result.json"* ]]
    [[ "$output" != *"/target/"* ]]
    [[ "$output" != *"/.scratch/"* ]]
    [[ "$output" != *"/.codex/.tmp/"* ]]
    [[ "$output" != *"/.cargo/cuda-oxide/"* ]]
    [[ "$output" != *"/.pi/agent/git/"* ]]
    [[ "$output" != *"/kernelbench-hard-eval/outputs/"* ]]
}

@test "drops archives (.tar.gz/.tgz/.tar) so a prior backup isn't swallowed" {
    mkdir -p "$SRC/proj/src"
    echo x >"$SRC/lifeboat-host-2026-01-01-00-00-00.tar.gz"
    echo x >"$SRC/proj/old-backup.tgz"
    echo x >"$SRC/proj/bundle.tar"
    echo x >"$SRC/proj/src/real.py"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" != *".tar.gz"* ]]
    [[ "$output" != *".tgz"* ]]
    [[ "$output" != *".tar"* ]]
    [[ "$output" == *"proj/src/real.py"* ]]
}

@test "keeps worktree source but drops worktree build output" {
    mkdir -p "$SRC/wt/w1/src" "$SRC/wt/w1/build" "$SRC/wt/w1/.torch_ext"
    echo src >"$SRC/wt/w1/src/k.cu"
    echo obj >"$SRC/wt/w1/build/o.o"
    echo ext >"$SRC/wt/w1/.torch_ext/ext.so"

    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"wt/w1/src/k.cu"* ]]
    [[ "$output" != *"/build/"* ]]
    [[ "$output" != *"/.torch_ext/"* ]]
}

# --- options ---------------------------------------------------------------

@test "EXTRA_EXCLUDES drops additional patterns" {
    echo keep >"$SRC/keep.txt"
    echo drop >"$SRC/secret.pdf"

    run env SRC="$SRC" EXTRA_EXCLUDES='*.pdf' "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    run archive_files
    [[ "$output" == *"keep.txt"* ]]
    [[ "$output" != *"secret.pdf"* ]]
}

@test "DRY_RUN writes no archive but lists members" {
    echo hi >"$SRC/file.txt"

    run env SRC="$SRC" DRY_RUN=1 "$LIFEBOAT" host
    [ "$status" -eq 0 ]
    [[ "$output" == *"file.txt"* ]]

    # nothing was written
    run find "$OUT" -name '*.tar.gz'
    [ -z "$output" ]
}

# --- self-exclusion --------------------------------------------------------

@test "does not archive its own output when writing inside SRC" {
    echo hi >"$SRC/file.txt"

    run env SRC="$SRC" OUT_DIR="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]

    local tgz
    tgz="$(find "$SRC" -maxdepth 1 -name '*.tar.gz' | head -1)"
    [ -n "$tgz" ]
    # the archive must not contain a .tar.gz member (i.e. itself)
    run tar -tzf "$tgz"
    [[ "$output" != *".tar.gz"* ]]
    [[ "$output" == *"file.txt"* ]]
}

# --- produces a valid gzip -------------------------------------------------

@test "produces a valid, non-empty gzip archive" {
    echo hi >"$SRC/file.txt"
    run env SRC="$SRC" "$LIFEBOAT" host
    [ "$status" -eq 0 ]
    local tgz
    tgz="$(find "$OUT" -name '*.tar.gz')"
    run gzip -t "$tgz"
    [ "$status" -eq 0 ]
}
