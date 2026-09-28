# Ber CLI

`ber-cli` exposes the public API of `ber-core` (`ber.bend`, levels 1 and 2) as a command-line interface written in pure Bend. It is not git-like and does not compete as a VCS: a thin 1:1 shell over the ber-core domains (`record`, `commit`, `diff`/`compare`, `merge`, `certificate`), with pretty output (human + `--json`) and errors that point at the next step.

Built on `ber-core-store@0.1.2.0` (pins inherited: mylsm, bend-kit-json, bend-codec-lib, vendored SHA).

## What is Ber?

**Ber** is a content-addressed store for versioned records. Data lives in
namespaces (`shop-config`), split into records (`limits`); each `commit` is a
snapshot identified by its hash, and values are typed (`text`, structured
`json`, binary `blob`). The CLI stages values in a session, commits snapshots,
diffs any two commits, and merges divergent histories.

**How it differs from git:** git versions file trees with branch DAGs and
leaves conflict resolution to humans. Ber versions individual records with
linear-parent history, and its three-way `union-disjoint` merges carry
**verification certificates** that can be re-checked offline
(`certificate verify`) — a merge is either `merged`, `conflict` or
`unprovable`, each with a machine-checked meaning (`bend PROOF.bend`,
60 laws). Ber is built for app state and config, not for source code.

**How it builds on mylsm:** `ber-core`'s `Store.Handle` wraps a
`mylsm-lsm-store` LSM database (`mylsm-lsm-store@0.3.2.0`): every command
replays `<store>/wal.log` on open and flushes its journal with fsync, so
separate processes share durable state. Content hashes (vendored SHA) make
commits content-addressed; `bend-kit-json` parses documents.

## Install / Build

Prerequisites: [Bend](https://bend-lang.com) >= 2.0.32 (`bend version`).
2.0.32 changed `IO.args()` to include `argv[0]`; the CLI strips it, so older
toolchains build binaries that misparse every command.

```bash
git clone <repo> ber-cli && cd ber-cli
bend cli.bend -o ber        # build the binary (./ber)
export PATH="$PWD:$PATH"    # use `ber` directly (or: cp ber ~/.local/bin/)
ber --version               # check the install: ber-cli 0.2.2.0
for f in src/Args.bend src/Key.bend; do bend $f --check-only; done   # gate: ALL PROOFS CHECK
```

Pure modules certify under `bend ... --check-only`. The full
`bend PROOF.bend` verdict additionally demands kernel certification of
foreign code: since 2.0.32 it fails closed on `ber-core`'s `Fs`/JSON foreign
imports (pre-existing — fails identically on a clean checkout), so the
effects shell (`Run`) is covered by binary smoke instead (see
`docs/superpowers/plans/2026-09-28-ber-cli-friendly.md`, Task 6).

No `npm install`, no dependencies to fetch: `ber-core-store` and pins resolve
through Bend packages. Put `./ber` on your `PATH` or call it by path; per-command
help lives in the binary itself (`ber --help`, `ber help set`).

## Quickstart

### Friendly (recommended)

```bash
ber init
ber set shop-config/limits --text "hello" --session demo
ber get shop-config/limits --session demo   # reads HEAD (no --at needed)
ber log --short
ber status --session demo
```

No `export S`, no `--store`: the store defaults to `./.ber` (`ber init`
creates it). `--session` is still required: it names your uncommitted working
set.

Shortcuts: `set` = `write`, `get` = `record get`. The key goes in a single
`ns/record` arg (`:` is not a separator). `get` without `--at` reads the last
commit recorded in `./.ber/LOG` (best-effort journal: pass `--at` explicitly
in scripts). Colors are on by default, turned off by `NO_COLOR=1`,
`TERM=dumb`, `--no-colors` or `--json` (pipes stay clean only when one of
those applies). `--colors` is accepted for compatibility but is a no-op. The `init` logo shows unless `TERM=dumb`, the locale is not UTF-8
(POSIX precedence: `LC_ALL` → `LC_CTYPE` → `LANG`, checked for `UTF-8`), or `--json`.

Advanced reference with `--ns/--record` flags (still supported):

```bash
ber write --session demo --ns shop-config --record limits --text "50"
ber write --session demo --ns shop-config --record limits --text "100" --parent <base>
ber write --session dev --ns shop-config --record banner --text "sale" --parent <base>
ber log --short   # copy the ids to use below

ber record get --ns shop-config --record limits --at <a>   # read=100
ber diff --from <a> --to <c> --verbose
ber merge --first <a> --second <c>                          # merged:<id>, exit 0
```

State is durable: every command replays `<store>/wal.log` on open and flushes its journal with fsync, so separate processes share state.

## Concepts

- **session**: id of the uncommitted working set (`stage/{session}/…` in ber-core). `record put`/`rm` write into the session; `commit create` materializes it into a commit. Nothing is visible to `record get` until committed. That is why the quickstart passes `--session demo` to the `set` step.
- **ns (namespace)**: first segment of the logical key; groups records by area (e.g. `shop-config`, `shop-prices`). The full logical key is `ns/record`.
- **record**: id of the record inside the namespace; the versioned unit (each commit stores one value or tombstone per key, e.g. `shop-config/limits`).
- **commit**: content-addressed snapshot (id = hash). `record get --at COMMIT` reads the value in force at that commit; `--parent` links linear history so `merge` can find a common ancestor.

## Storing files

- `--file F --kind text`: reads UTF-8 → `Text`.
- `--file F --kind json`: parses → `Object` (structured document).
- `--file F --kind blob`: reads raw bytes → `Blob` (generic binary: images, PDFs, …). Single reads are capped at 1 MiB.
- Inline alternatives without a file: `--text`, `--json`, `--blob-hex`.
- Blobs never dump bytes to the output: `read=<blob N bytes>`; bad `--kind` → usage-error (2), unreadable file → io-error (3).

```bash
ber record put --session demo --ns product-media --record sku-42-front --file ./front.jpg --kind blob
ber commit create --session demo
ber record get --ns product-media --record sku-42-front --at <COMMIT>   # read=<blob 18432 bytes>
```

## Commands

Global flags: `--store DIR` (default `./.ber`), `--session ID`, `--json`, `--colors` (compat no-op; colors are on by default), `--no-colors` (force plain; also `NO_COLOR=1`, `TERM=dumb`, `--json`), `--verbose`, `--help` (`--help`/`-h` alias). `--parent` is singular (linear history); `--meta` deferred to v2.

| Subcommand | Delegates to | Description |
|---|---|---|
| `record put --session S --ns N --record R (--text T \| --json J \| --blob-hex H \| --file F [--kind text\|json\|blob])` | `Ber.put_record` | Stages one value in the session working set (invisible until commit) |
| `record rm --session S --ns N --record R` | `Ber.delete_record` | Stages a tombstone; the deletion takes effect at commit |
| `record get --ns N --record R --at COMMIT` | `Ber.read_value_at` + `render_read_value` | Reads a namespaced value as of a commit |
| `commit create --session S [--parent P]` | `Ber.create_commit` | Materializes the session stage plus parents into a new commit |
| `commit show-tree --at COMMIT` | `Ber.read_tree_at` | Shows the tree hash and entry count of a commit |
| `diff --from A --to B [--verbose]` | `Ber.compare_commits` + `render_compare_counts` | Counts added/removed/modified keys between two commits (`--verbose` lists them) |
| `merge --first A --second B [--strategy union-disjoint]` | `Ber.merge_commits` + verify | Three-way union-disjoint merge plus verification; prints merged, conflict or unprovable |
| `certificate verify --first A --second B --base C --tree H --strategy S` | `Ber.verify_certificate` | Re-verifies a merge certificate against the stored trees |
| `write --session S --ns N --record R ... [--parent P]` | `Ber.commit_value` | Shortcut: stage and commit in one step, prints the new commit id |
| `compare --from A --to B` | `Ber.compare_summary` | Shortcut: diff rendered as a single counts line |
| `merge-verify --first A --second B` | `Ber.merge_and_verify` | Shortcut: merge plus verify rendered as a verdict |
| `init [--store DIR]` | `Store.open_durable` | Creates the store dir, prints the welcome header |
| `set KEY ... [--parent P]` (`KEY=ns/record`) | `Ber.commit_value` | Friendly alias for `write` with single-arg key |
| `get KEY [--at COMMIT]` | `Ber.read_value_at` | Friendly alias for `record get`; no `--at` reads `<store>/LOG` head |
| `log [--limit N]` | `<store>/LOG` journal | Lists recent commit ids (short); `--limit` defaults to 20 |
| `status [--session S]` | `Staging.load_stage_index` | Shows staged keys not yet committed |
| `help [topic]` | `Args.usage_text` | Per-command help with examples (`set`, `get`, `merge`, …) |

Only `union-disjoint` is accepted as strategy; anything else answers `unprovable:unknown-strategy`.

## Output and exit codes

- Human-readable by default; `--json` emits one canonical line with `status ∈ {ok, merged, conflict, unprovable, absent, usage-error, io-error}`.
- Blobs render as `<blob N bytes>`, never raw bytes.
- Every error carries a next-step hint (`conflict → ber diff … --verbose`, `no-common-ancestor → commit show-tree …`, `verify-failed → certificate verify …`).

| Exit | Meaning |
|---|---|
| `0` | ok / verified merge |
| `10` | conflict |
| `20` | unprovable |
| `30` | absent / not found |
| `3` | IO error |
| `2` | usage error |

## Architecture

```
cli.bend            # main: IO.args -> Args.parse_both -> Run.dispatch -> Render -> print/exit/die
src/Args.bend       # PURE: argv -> Command + GlobalOpts (single structural pass, no string compares)
src/Input.bend      # PURE: value flags -> Value (files resolve in Run, never here)
src/Render.bend     # PURE: Outcome -> human / JSON / hint / exit code
src/Run.bend        # EFFECTS ONLY: mkdir -p, open_durable, run_op_durable per arm
LAWS.bend / PROOF.bend / bolt.bend
```

No tests by explicit decision: pure modules carry machine-checked laws (`bend PROOF.bend`, 33 laws), the effects shell is verified by cross-process binary smoke. Gate before every commit: `bend PROOF.bend` green + `bolt` 0 errors.

See `docs/superpowers/specs/2026-09-27-ber-cli-design.md` for the full design.
