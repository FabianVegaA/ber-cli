# ber-cli

`ber-cli` exposes the public API of `ber-core` (`ber.bend`, levels 1 and 2) as a command-line interface written in pure Bend. It is not git-like and does not compete as a VCS: a thin 1:1 shell over the ber-core domains (`record`, `commit`, `diff`/`compare`, `merge`, `certificate`), with pretty output (human + `--json`) and errors that point at the next step.

Built on `ber-core-store@0.1.2.0` (pins inherited: mylsm, bend-kit-json, bend-codec-lib, vendored SHA).

## Quickstart

```bash
bend cli.bend -o ber
export S=/tmp/ber-demo

./ber write --store $S --session s1 --ns ledger --record r1 --text v1 --parents
# committed:<BASE>

A=$(./ber write --store $S --session s1 --ns ledger --record r1 --text v2 --parent <BASE> | sed 's/committed://')
C=$(./ber write --store $S --session s1 --ns ledger --record r2 --text w1 --parent <BASE> | sed 's/committed://')

./ber record get --store $S --ns ledger --record r1 --at $A   # read=v2
./ber diff --store $S --from $A --to $C --verbose
./ber merge --store $S --first $A --second $C                 # merged:<id>, exit 0
```

State is durable: every command replays `<store>/wal.log` on open and flushes its journal with fsync, so separate processes share state.

## Commands

Global flags: `--store DIR` (default `./.ber`), `--session ID`, `--json`, `--colors` (opt-in ANSI), `--verbose`, `--help` (`--help`/`-h` alias). `--parent` is singular (linear history); `--meta` deferred to v2.

| Subcommand | Delegates to |
|---|---|
| `record put --session S --ns N --record R (--text T \| --json J \| --blob-hex H \| --file F [--kind text\|json\|blob])` | `Ber.put_record` |
| `record rm --session S --ns N --record R` | `Ber.delete_record` |
| `record get --ns N --record R --at COMMIT` | `Ber.read_value_at` + `render_read_value` |
| `commit create --session S [--parent P]` | `Ber.create_commit` |
| `commit show-tree --at COMMIT` | `Ber.read_tree_at` |
| `diff --from A --to B [--verbose]` | `Ber.compare_commits` + `render_compare_counts` |
| `merge --first A --second B [--strategy union-disjoint]` | `Ber.merge_commits` + verify |
| `certificate verify --first A --second B --base C --tree H --strategy S` | `Ber.verify_certificate` |
| `write --session S --ns N --record R ... [--parent P]` | `Ber.commit_value` |
| `compare --from A --to B` | `Ber.compare_summary` |
| `merge-verify --first A --second B` | `Ber.merge_and_verify` |

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
