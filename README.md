# lifeboat

Make a compressed tarball of a home directory, keeping the things you can't
regenerate — git history, source, docs — and dropping the bulky things you can:
build artifacts, profiler dumps, caches, virtualenvs.

The name is the idea: when a box is about to go down, you grab the lifeboat —
the essential work — and leave the heavy, replaceable cargo behind.

## Usage

```sh
lifeboat <name> <tag>
```

Produces, in the current directory:

```
<name>-<tag>-YYYY-MM-DD-HH-MM-SS.tar.gz
```

Example:

```sh
$ lifeboat myhost eigh
Backing up : /home/me
Writing    : /home/me/myhost-eigh-2026-06-30-14-22-05.tar.gz
Compressor : pigz -6

Done: /home/me/myhost-eigh-2026-06-30-14-22-05.tar.gz
Size: 20G
```

Uses `pigz` for parallel compression when available, otherwise `gzip`.

## What it keeps and drops

**Keeps:** `.git` history, source, docs, images/PDFs, logs, config — including
source inside git worktrees.

**Drops** (regenerable):

| Category | Patterns |
| --- | --- |
| Build output | `build/`, `.torch_ext/`, `*.o *.a *.so *.dylib *.dll *.cubin *.fatbin *.ptx`, `*.ninja_deps` |
| Profiler reports | `profiles/`, `*.nsys-rep *.ncu-rep *.qdrep *.qdstrm` |
| Caches | `.cache/ .triton/ .nv/ __pycache__/ *.pyc`, `.pytest_cache/ .mypy_cache/ .ruff_cache/` |
| Virtualenvs / deps | `.venv*/`, `node_modules/` |

Exclusions are **pattern-based, never content-based**. That is deliberate: a
content sniffer such as `file` reports empty and one-byte files as "binary", so
a backup built on it would silently drop empty `__init__.py`, `.gitkeep`, and
the like. Patterns can't make that mistake, and every build artifact lives in a
predictable place anyway.

A matched directory is pruned with everything beneath it, so worktree *source*
is kept while worktree *build output* is dropped.

## Options

Set via environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `SRC` | `$HOME` | directory to back up |
| `OUT_DIR` | current dir | where to write the archive |
| `LEVEL` | `6` | gzip/pigz compression level (`0`–`9`) |
| `EXTRA_EXCLUDES` | — | extra `tar --exclude` patterns (space/newline separated) |
| `DRY_RUN` | — | if set, list what would be archived and write nothing |

```sh
# smaller archive: also drop images and PDFs
EXTRA_EXCLUDES='*.png *.pdf' lifeboat myhost eigh

# see what would be included, write nothing
DRY_RUN=1 lifeboat myhost eigh
```

## Notes

- Archiving a live home directory is fine: `tar`'s "file changed as we read it"
  is treated as a warning, not a failure. Genuine `tar` errors still fail.
- The script never archives its own output, even when `OUT_DIR` is inside `SRC`.
- `.git` packfiles are already compressed, so on a repo-heavy home directory
  they dominate the result and set the floor on how small it can get.

## Development

```sh
./test.bash            # lint + unit (default)
./test.bash --lint     # bash -n + shellcheck
./test.bash --unit     # bats suite
```

CI runs the same `./test.bash` flags, so green locally means green in CI.

## License

Apache-2.0 WITH LLVM-exception. See [LICENSE](LICENSE).
