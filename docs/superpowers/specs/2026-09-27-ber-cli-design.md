# ber-cli — Design Spec (2026-09-27)

## 1. Propósito

`ber-cli` expone la API pública de `ber-core` (`ber.bend`, niveles 1 y 2) como
una interfaz de línea de comandos en Bend puro. No imita a git ni compite como
VCS: es una cáscara fina 1:1 sobre los dominios de ber-core (`record`, `commit`,
`diff`/`compare`, `merge`, `certificate`), con salida bonita (humana + `--json`)
y errores que guían al siguiente paso.

## 2. No-objetivos (fase 1)

- Ninguna lógica de merge/diff/hash propia: todo delega a `Ber.*`. El CLI nunca
  nombra MyLSM directo; solo vía `Store.Handle / Store.Op / run_op`.
- Sin réplica de renders ricos (tablas complejas, paginado, inspección de
  historia/árboles más allá de `read_tree_at`). Eso es v2.
- Sin locks, daemon, red, ni control de concurrencia sobre `--store`.
- Sin configuración persistente más allá de flags (`--store`, `--session`).

## 3. Stack y workflow

- Bend puro, ber-core como dependencia publicada:
  `import ber-core-store@0.1.2.0/ber.bend as Ber` (pins heredados: mylsm,
  bend-kit-json, bend-codec-lib, SHA vendored).
- Proof-driven (heredado de `AGENT.md`): leyes en `LAWS.bend`, código + prueba
  en `PROOF.bend`, tests (`tests/*_check.bend`) SOLO para IO/Sess wiring.
  Gate: `bend PROOF.bend` verde + `bolt` 0 errores antes de cada commit.
- Entrada/salida: `IO.args()` para argv, `IO.print / print_err / die(code,msg)`
  para salida y exit codes, `File.open/read` para `--file`.

## 4. Superficie de comandos

Flags globales: `--store DIR` (default `./.ber`), `--session ID`, `--json`
(salida máquina), `--colors` (opt-in: colorea veredictos con ANSI; por defecto
salida plana), `--verbose`, `--help`. `--help` y `-h` son alias de `help`.
`--parent` es singular (historia lineal); multi-parent queda para v2.

| Subcomando | Delegación ber-core |
|---|---|
| `record put --session S --ns N --record R (--text T \| --json J \| --blob-hex H \| --file F [--kind text\|json\|blob])` | `Ber.put_record` |
| `record rm --session S --ns N --record R` | `Ber.delete_record` |
| `record get --ns N --record R --at COMMIT` | `Ber.read_value_at` + `render_read_value` |
| `commit create --session S [--parent P] [--meta k=v...]` (meta diferido a v2) | `Ber.create_commit` (metas Nil) |
| `commit show-tree --at COMMIT` | `Ber.read_tree_at` |
| `diff --from A --to B [--verbose]` | `Ber.compare_commits` + `render_compare_counts` (+ detalle por clave en verbose) |
| `merge --first A --second B [--strategy union-disjoint]` | `Ber.merge_commits` + `verify_merge_outcome` |
| `certificate verify --first A --second B --base C --tree H --strategy S [--law name=pass...]` | `Ber.verify_certificate` |
| `write --session S --ns N --record R ... [--parent P]` (atajo) | `Ber.commit_value` / `Ber.remove_record` |
| `compare --from A --to B` (atajo) | `Ber.compare_summary` |
| `merge-verify --first A --second B` (atajo) | `Ber.merge_and_verify` |

`--strategy` solo acepta `union-disjoint`; otro valor ⇒
`unprovable:unknown-strategy` (refleja `Merging.decide_strategy_name`).

## 5. Entrada de valores

- `--text T` → `Value.Text{T}`.
- `--json J` → parse a `Json.Val` → `Value.Object{...}` (vía `JsonAdapter`;
  JSON inválido = error de uso, exit 2).
- `--blob-hex H` → decode hex (codec pineado) → `Value.Blob{...}`; hex
  malformado = error de uso, exit 2.
- `--file F` requiere `--kind`: `text` lee UTF-8 → `Text`, `json` parsea → `Object`,
  `blob` lee bytes → `Blob`. Fichero ilegible = error IO (exit 3).
- Exactamente una fuente de valor en `record put` / `write`; cero o más de una
  = error de uso (exit 2).

## 6. Salida y exit codes

- Humana por defecto, reutilizando `render_*` de ber-core. Con `--colors` los
  veredictos se colorean (verde `merged:`, rojo `conflict:`, amarillo
  `unprovable:`); sin el flag la salida es plana (apta para tuberías y logs).
- Con `--verbose`, `diff` añade el detalle por clave (added/removed/modified).
- `--json` emite JSON canónico de una sola línea: `{"status":...,...}` con
  `status ∈ {ok, merged, conflict, unprovable, absent, usage-error, io-error}`.
- Blobs muestran `<blob N bytes>`, nunca bytes crudos (hereda
  `render_found_value`).
- Exit codes: `0` ok / merge verificado, `10` conflicto, `20` unprovable,
  `30` absent / no-encontrado, `3` error IO, `2` uso incorrecto.
- Errores con hint de siguiente paso:
  - `conflict:<n> <claves>` → `ber diff --from A --to B --verbose`.
  - `unprovable:no-common-ancestor` → `commit show-tree --at A/B` para revisar padres.
  - `unprovable:verify-failed` → `certificate verify ...` para re-verificar.
  - `read=absent` → sugiere commit/namespace/record correctos (exit 30).

## 7. Arquitectura

```
cli.bend            # main: IO.args -> Args.parse_both -> Run.dispatch -> Render -> print/exit/die
src/Args.bend       # PURO: List String -> Command (Data). Sin IO ni Store.
src/Input.bend      # PURO: flags de valor -> Value. Sin IO (bytes ya leídos).
src/Render.bend     # PURO: Command/Result -> String humano / JSON / hint / exit-code.
src/Run.bend        # FINO: Command -> Store.Op delegando 1:1 a Ber.*. Solo orquestación.
LAWS.bend / PROOF.bend / bolt.bend
```

Sin tests por decisión explícita: verificación = `bend PROOF.bend` verde +
`bolt` 0 errores + smoke manual del binario (§9, cross-process sobre un
mismo `--store`). El shell de efectos (`Run` + `cli.bend`) se valida
ejecutándolo, no con `*_check.bend`.

Bordes: solo `Run.bend` + `cli.bend` tocan `Store`/`IO`/`File`. `Args/Input/Render`
puros, probables y paralelizables (`!` en renders de listas grandes).

## 8. Leyes (a formalizar en LAWS.bend)

1. `parse-roundtrip`: todo `Command` parseado re-serializa a uso válido.
2. `render-total`: todo `MergeResult / Maybe Value / CompareResult` tiene
   exactamente un render humano y uno JSON, nunca vacío.
3. `exit-code-inyectivo`: `Success→0, Conflict→10, Unprovable→20, Absent→30,
   IO→3, Usage→2`, sin solapes.
4. `blob-opaco`: ningún render expande bytes de `Blob`.
5. `strategy-cerrada`: strategy ≠ `union-disjoint` ⇒ `unprovable:unknown-strategy`.
6. `value-roundtrip`: `Text/Object/Blob` → flags → `Value` → canónico, sin pérdida.

## 9. Criterios de aceptación

- Los 11 comandos delegan al `Ber.*` indicado (revisión por tabla §4).
- `--json` siempre parsea como JSON válido; humana nunca vacía.
- Exit codes según §6 en: ok, conflicto, unprovable (ancestro ausente +
  strategy desconocida), absent, uso incorrecto, IO.
- Gate verde: `bend PROOF.bend` + `bolt` 0 errores + binario `bend cli.bend -o ber`
  con smoke test de los 8 comandos base.
