# ber-cli friendly — Design Spec (2026-09-28)

## 1. Propósito

Hacer `ber-cli` amable para un usuario menos experimentado sin convertirlo
en TUI y sin romper compatibilidad con `ber-core` ni con scripts existentes.

Paquetes elegidos: **A1 (alias humanos + defaults) + B2 (formato humano
mejorado)**, más `--help` detallado por comando y `ber init` con header de
bienvenida. CLI puro: sin wizards interactivos, sin prompts `y/N`, sin
`did-you-mean`, sin emoji, sin spinners.

## 2. No-objetivos

- Sin TUI / interactivo. Todo sigue siendo `argv -> dispatch -> print/exit`.
- Sin sintaxis `ns:record`. Separador único: `/`. `:` es usage-error con hint.
- Sin romper salida plain actual ni `--json` ni exit codes.
- Sin lógica propia de merge/diff/hash: todo delega a `Ber.*`.
- Sin `did-you-mean`, sin confirmaciones, sin config persistente más allá de flags/env.

## 3. Superficie nueva (shortcuts, cero breaking)

Todos los comandos viejos siguen funcionando igual.

```
ber init [--store DIR]
ber set KEY (--text T | --json J | --blob-hex H | --file F [--kind text|json|blob]) [--parent P] [--session S]
ber get KEY [--at COMMIT]
ber log [--limit N] [--short]
ber status [--session S]
ber help [comando]
```

- `KEY = ns/record` en un solo posicional (primer posicional tras el comando,
  reutiliza el slot `sub_word` que `args_to_split` ya captura).
- `set` delega a `Ber.commit_value` (= `write`). `get` a `Ber.read_value_at`.
  `log`/`status` leen via `Ber.*` existentes (`read_tree_at`, stage read).
- Fallback legacy: si no hay `KEY`, se acepta `--ns N --record R`.
- Si no hay ni `KEY` ni flags completos → `UsageError` amable (en inglés):
  `missing key. Use shop-config/limits or --ns shop-config --record limits`
  + `hint: ber help set`. Exit 2 (sin cambio).
- Regla global: todo texto visible del CLI (errores, hints, help, header) en
  inglés. Este spec está en español, pero los strings del CLI siempre en inglés.

### Reglas de KEY (separador `/` único)

- Split por el primer `/`: `ns/record` → `(ns, record)`.
- `shop-config:limits` → usage-error `use ns/record`.
- `a/b/c` → `ns=a`, `record=b/c`? NO: se toma primer `/` → `ns=a`,
  `record=b/c` y luego `LogicalKey` lo rechaza si no es segmento válido →
  usage-error. Simple y predecible.
- `/limits`, `shop/`, `shop`, `""` → usage-error con ejemplo.
- `ns`/`record` resultantes siguen las mismas validaciones que hoy.

### Defaults

- `--store` default `./.ber` (sin cambio).
- `--session`: flag `--session` > `BER_SESSION` env > `""` → error amable
  (en inglés) `set --session or export BER_SESSION=ana`. `Run` resuelve, `Args` solo parsea.
- `get` sin `--at` → lee HEAD = última línea del journal `<store>/LOG`
  (append-only, una id por commit; lo actualizan `commit create`, `set`/`write`
  y `merge` verificado; best-effort). Sin LOG → `UsageError` que pide `--at`.
- `log` renderiza las últimas N líneas del LOG (ids cortos 7 chars);
  `--limit` default 20. Sin LOG → `UsageError`.
- `help <topic>` rutea el primer posicional (`ber help set`); sin tópico o
  tópico desconocido → overview. `--help`/`-h` conservan el alias.

## 4. Help detallado

`Args.usage_text(topic)` pasa de 5 líneas a dispatch por tópico:
`"", set, get, log, status, init, merge, diff, record, commit, write`.

Cada tópico (en inglés): qué hace (1 línea) + sintaxis + flags + 1 ejemplo copiable +
qué hacer si falla. Ejemplo:

```
$ ber help merge
Usage: ber merge --first A --second B
What it does: 3-way union-disjoint merge + verification.
If it fails: conflict → ber diff --from A --to B --verbose
Example: ber merge --first $A --second $C
```

`ber --help`, `ber -h`, `ber help` → overview + 3 ejemplos (`init → set → get`).
Ley: `usage_text(t)` nunca vacío para tópicos conocidos.

## 5. Init con header vistoso (logo cerrado)

`ber init` hace `ensure_store_dir` + `open_cli_store` (reusa código actual) y
retorna `Ok{welcome_header}`. Solo en `init`, nunca en otros comandos.

Variante rica (TTY + UTF-8, default a mano):

```
██████╗ ███████╗██████╗
██╔══██╗██╔════╝██╔══██╗
██████╔╝█████╗  ██████╔╝
██╔══██╗██╔══╝  ██╔══██╗
██████╔╝███████╗██║  ██║
╚═════╝ ╚══════╝╚═╝  ╚═╝

Welcome to Ber — save, version, merge.
store ready at ./.ber (session: ana)
→ try: ber set demo/hello --text "world"
→ then: ber get demo/hello
```

Fallback plano (pipe / `TERM=dumb` / `LANG=C` / `--no-colors` / `--json`):

```
ber
Welcome to Ber — save, version, merge.
store ready at ./.ber (session: ana)
→ try: ber set demo/hello --text "world"
→ then: ber get demo/hello
```

- El logo es fijo, sin dependencias. Con `color_on=False` sale sin ANSI (ley);
  el fallback además omite el dibujo (regla Unicode).
- Incluye next-steps copiables. No crea session ni commits, solo el store.
- Regla Unicode global: default permite box-drawing estándar (`█ ╗ ╔ ╝ ╚ ═ ║`),
  `→ ≡ ├─ —` en modo humano. Nada de shades/half-blocks (`▓ ▌ ▐`) ni emoji
  por defecto; emoji solo tras `--fancy` futuro (fuera de fase 1).

## 6. Formato humano B2

Todo en `Render` (puro). Formas plain actuales pineadas, no se tocan.

- `diff --verbose` como bloques alineados, no `added: a b`:
```
≡ diff a3f9c2d..c71b00e  (+1 ~1 -0)
  + shop-config/banner
  ~ shop-config/limits  a3f9c2d->c71b00e
```
- `show-tree` como árbol:
```
tree:<hash> (3 entries)
├─ shop-config/limits
├─ shop-config/banner
```
- `log --short`: una línea por commit, hash 7 chars.
- `status`: `staged (session ana): 2 keys` + lista.
- `get`: pretty JSON cuando el valor es `Object` (humano), `--json` sin cambio.
- `Ok{text}` nunca lleva ANSI (ley existente).

## 7. Auto-color por TTY (decisión cerrada + ajuste as-built)

```
color_on = --colors AND NOT (--no-colors OR --json OR TERM==dumb OR NO_COLOR set)
```

- Spikes probaron que Bend no expone primitiva TTY (`Process.run` captura
  stdout del hijo → `test -t 1` siempre falso) y que `match` no entra en
  `do`-blocks ni hay recursión mutua. Sin señal TTY fiable, el default-ON
  fugaría ANSI a pipes: el diseño es **opt-in con auto-off**.
- A mano en terminal: `--colors` colorea. En `NO_COLOR=1` / `TERM=dumb` /
  `--no-colors` / `--json` → plano aunque se pase `--colors`.
- `detect` vive en `Run` vía `IO.get_env("TERM"/"NO_COLOR"/"LANG")`.
  `Render` no cambia de firma, recibe `color_on` resuelto.
- El header vistoso no depende del color: el logo sale por defecto salvo
  `TERM=dumb`, `LANG=C*` o `--json` (fallback `ber` + mismo texto).
- Colores: verde `merged:`, rojo `conflict:`, amarillo `unprovable:`, dim hints.
  `Ok` sin color.

## 8. Arquitectura / toques por archivo

- Nuevo `src/Key.bend` (puro): `split_key(key) -> Maybe<(ns, record)>`,
  scan del primer `/`, leaf-first, `String.eq` → `Bool` → helpers `decide_*`
  (mismo estilo que `Args.bend`). Spike previo: confirmar API de `Base` para
  iterar `String`; si no hay deconstrucción, usar `bend-kit`/`ber-core` o scan
  manual — interfaz estable en todo caso.
- `src/Args.bend`: `Command += Init | Set | Get | Log | Status`,
  `GlobalOpts += no_colors`, `resolve_ns_record(sub_word, ns_flag, record_flag)`,
  `parse_dispatch += set/get/log/status/init`, `usage_text` por tópico.
  Restricciones vigentes: pasada única, leaf-first, sin match sobre computados.
- `src/Render.bend`: `welcome_header`, `render_table_diff`, `render_tree`,
  `render_log_line`, `render_status`. Sin tocar renders plain existentes.
- `src/Run.bend`: `run_init/set/get/log/status`, `get` sin `--at` → head,
  `detect_tty` + resolución `color_on`. Reusa `run_durable`, mismos exits.
- `LAWS.bend/PROOF.bend`: leyes nuevas solo puras
  (`split_key`, `set/get` con `/`, fallback flags, `:`→usage-error,
  `welcome_header` plano, tabla determinista, `usage_text` no vacío,
  `no_colors` flag). Gate: `bend PROOF.bend` + `bolt` 0 errores.
- `README.md`: nueva sección Quickstart amable (`init → set → get → log →
  diff`) con ejemplos copiables usando `KEY`, más tabla de alias
  (`set=get` shortcuts) y nota de auto-color. Los ejemplos viejos con
  `--ns/--record` se conservan como referencia avanzada, no se borran.

## 9. Salida / exits (sin cambios)

`0` ok/merged, `10` conflict, `20` unprovable, `30` absent, `3` IO, `2` usage.
`--json` intacto. Blobs opacos.

## 10. Gate de aceptación

1. `bend PROOF.bend` verde + `bolt` 0 errores.
2. Smoke binario: `init → set shop/limits → get shop/limits → log --short →
   status → diff --verbose`, en TTY y en pipe, con `/` y con flags legacy,
   más `:` → usage-error esperado.
3. README con quickstart amable verificable copiando los comandos.
