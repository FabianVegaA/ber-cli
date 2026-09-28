# ber-cli friendly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar A1+B2 amable en `ber-cli`: `init/set/get/log/status/help`, `KEY=ns/record` con `/` único, header de bienvenida, tablas, help por tópico y auto-color por TTY, más README con quickstart amable. CLI 100% en inglés.

**Architecture:** Capa shortcut sobre `ber-core` sin breaking: nuevo `src/Key.bend` puro para `split_key`, extensión de `Args` (parse) + `Render` (presentación) + `Run` (efectos + `detect_tty`). Todo lo puro con ley en `LAWS.bend` + prueba en `PROOF.bend`.

**Tech Stack:** Bend puro, `ber-core-store@0.1.2.0`, `bend PROOF.bend` + `bolt` como gate.

---

## File structure

- Create: `src/Key.bend` — `split_key(key) -> Maybe<(ns, record)>`, solo separador `/`. Interfaz usada por `Args`.
- Modify: `src/Args.bend` — `Command += Init/Set/Get/Log/Status`, `GlobalOpts += no_colors`, `resolve_ns_record`, `parse_dispatch += set/get/log/status/init`, `usage_text(topic)` por tópico.
- Modify: `src/Render.bend` — `welcome_header`, `render_table_diff`, `render_tree`, `render_log_line`, `render_status`.
- Modify: `src/Run.bend` — `run_init/set/get/log/status`, `detect_tty`, resolución `color_on`, ramas nuevas en `execute`.
- Modify: `LAWS.bend`, `PROOF.bend` — una ley+prueba por comportamiento puro nuevo.
- Modify: `README.md` — quickstart amable con `KEY`, tabla de alias, nota auto-color. Ejemplos viejos se conservan como "avanzado".
- Reference: `docs/superpowers/specs/2026-09-28-ber-cli-friendly-design.md` (spec, no tocar).

---

### Task 0: Spike Base.String (solo lectura, sin código)

**Files:**
- Inspect: `bend guide` output, `Base` String API, `ber-core-store@0.1.2.0/src/LogicalKey.bend`

- [ ] **Step 1: Inspeccionar API de String disponible**

Run: `bend guide 2>&1 | head -100`
Expected: ver sección Strings (to_list / head / split / find si existe)

Run: `rg -n "def String\." ~/.bend 2>/dev/null || bend doc Base 2>&1 | head -50`
Expected: lista de funciones `String.*` disponibles (al menos `String.eq`, `String.++` ya usados)

- [ ] **Step 2: Inspeccionar LogicalKey para validar segmentos**

Run: `rg -n "def (encode|decode|make|valid)" ber-core-store@0.1.2.0/src/LogicalKey.bend 2>/dev/null || find / -name "LogicalKey.bend" -path "*ber-core*" 2>/dev/null | head -5`
Expected: confirmar que `ns`/`record` no admiten `/` (por eso `a/b/c` → usage-error downstream)

- [ ] **Step 3: Decidir implementación de split_key y anotar**

Elección cerrada: scan del primer `/` char-a-char con helpers `decide_*` estilo `Args.bend` (sin `match` sobre computados, leaf-first). Si `Base` expone `String.to_list` o `split`, usarlo; si no, deconstrucción manual. Anotar la decisión en el PR, no cambia la interfaz:
```bend
def split_key(+key: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>
```

---

### Task 1: src/Key.bend + leyes split_key

**Files:**
- Create: `src/Key.bend`
- Modify: `LAWS.bend`
- Modify: `PROOF.bend`

- [ ] **Step 1: Escribir las leyes primero**

En `LAWS.bend`, añadir al final:

```bend
# Key family: split por primer "/" únicamente.
law split_key_slash:
  {Key.split_key("shop/limits") == Some{("shop", "limits")} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_colon_is_none:
  {Key.split_key("shop:limits") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_no_sep_is_none:
  {Key.split_key("shop") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_empty_seg_is_none:
  {Key.split_key("/limits") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}
```

Importar arriba: `import ./src/Key.bend as Key`.

- [ ] **Step 2: Correr proof y ver que falla (falta Key.bend)**

Run: `bend PROOF.bend`
Expected: FAIL / módulo `Key` no encontrado (prueba roja correcta)

- [ ] **Step 3: Implementación mínima en src/Key.bend**

```bend
import Base

# Split por primer "/". ":" no es separador (diseño cerrado).
# Estilo Args.bend: String.eq viaja como Bool a helpers decide_*,
# defs leaf-first, sin match sobre valores computados.

def decide_sep(is_slash: Bool, is_colon: Bool, +ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match is_slash:
    case True{}:
      finish_key(ns_acc, rest)
    case False{}:
      next_char(ns_acc, rest)

def finish_key_empty(is_empty: Bool, +ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match is_empty:
    case True{}:
      None{}
    case False{}:
      decide_record_empty(String.eq(rest, ""), ns_acc, rest)

def decide_record_empty(is_empty: Bool, +ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match is_empty:
    case True{}:
      None{}
    case False{}:
      Some{(ns_acc, rest)}

def finish_key(+ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  finish_key_empty(String.eq(ns_acc, ""), ns_acc, rest)

def next_char(+ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match String.pop_front(rest):
    case None{}:
      None{}
    case Some{(ch, tail)}:
      decide_sep(String.eq(ch, "/"), String.eq(ch, ":"), ns_acc ++ ch, tail)

def split_go(+ns_acc: String, +rest: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match String.pop_front(rest):
    case None{}:
      None{}
    case Some{(ch, tail)}:
      decide_sep(String.eq(ch, "/"), String.eq(ch, ":"), ns_acc, tail ++ "")

def split_key(+key: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  split_go("", key)
```

Nota: si el spike (Task 0) mostró que `String.pop_front` no existe y sí
`String.to_list`/`head`/`tail`, sustituir solo `pop_front` por esa API.
La interfaz `split_key` y las leyes no cambian. (`:` se detecta para
rechazarlo explícito como `None`, no como separador.)

- [ ] **Step 4: Añadir pruebas en PROOF.bend**

```bend
def Laws.split_key_slash():
  {==}

def Laws.split_key_colon_is_none():
  {==}

def Laws.split_key_no_sep_is_none():
  {==}

def Laws.split_key_empty_seg_is_none():
  {==}
```

- [ ] **Step 5: Correr gate**

Run: `bend PROOF.bend`
Expected: PASS verde

Run: `bolt`
Expected: 0 errors (warnings ok)

---

### Task 2: Args — Init/Set/Get/Log/Status + no_colors + KEY + help por tópico

**Files:**
- Modify: `src/Args.bend`
- Modify: `LAWS.bend`
- Modify: `PROOF.bend`

- [ ] **Step 1: Leyes de parse con KEY**

Añadir en `LAWS.bend`:

```bend
law parse_set_key_slash:
  {Args.parse_command(Con{"set", Con{"shop/limits", Con{"--text", Con{"v1", Nil{}}}}}) == Args.Set{"", "shop", "limits", Args.FromText{"v1"}, Nil{}} : Args.Command}

law parse_set_colon_is_usage:
  {Args.parse_command(Con{"set", Con{"shop:limits", Con{"--text", Con{"v1", Nil{}}}}}) == Args.UsageError{"set-needs-key-ns/record"} : Args.Command}

law parse_get_key_slash:
  {Args.parse_command(Con{"get", Con{"shop/limits", Nil{}}}) == Args.Get{"shop", "limits", ""} : Args.Command}

law parse_get_flags_fallback:
  {Args.parse_command(Con{"get", Con{"--ns", Con{"shop", Con{"--record", Con{"limits", Nil{}}}}}}) == Args.Get{"shop", "limits", ""} : Args.Command}

law parse_init:
  {Args.parse_command(Con{"init", Nil{}}) == Args.Init{} : Args.Command}

law parse_no_colors_flag:
  {Args.no_colors_flag_of(Args.parse_opts(Con{"--no-colors", Nil{}})) == True{} : Bool}

law usage_set_nonempty:
  {String.eq(Args.usage_text("set"), "") == False{} : Bool}
```

- [ ] **Step 2: Ver rojo**

Run: `bend PROOF.bend`
Expected: FAIL (faltan `Set/Get/Init`, `no_colors_flag_of`)

- [ ] **Step 3: Extender tipos en src/Args.bend**

```bend
type Command is Data:
  RecordPut{session_id: String, namespace_name: String, record_id: String, source: ValueSource}
  RecordRm{session_id: String, namespace_id: String, record_id: String}
  # ... (existentes intactos)
  Set{session_id: String, namespace_name: String, record_id: String, source: ValueSource, parents: List<&2, String>}
  Get{namespace_name: String, record_id: String, commit_id: String}
  Log{limit_text: String}
  Status{session_id: String}
  Init{}
  # ... (Help, UsageError intactos)

type GlobalOpts is Data:
  Opts{store_dir: String, session_id: String, json_out: Bool, colors_on: Bool, verbose: Bool, no_colors: Bool}
```

Actualizar `default_opts()` a `Opts{"./.ber", "", False{}, False{}, False{}, False{}}`
y todos los `match opts: case Opts{store_dir, session_id, json_out, colors_on, verbose}`
a 6 campos (añadir `no_colors`), más:

```bend
def no_colors_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      no_colors
```

- [ ] **Step 4: resolve_ns_record + parse set/get/init/log/status**

```bend
def resolve_split(+split: Maybe<&2, Sigma<&2, &2, String, _ => String>>, +ns_flag: String, +rec_flag: String) -> Sigma<&2, &2, String, _ => String>:
  match split:
    case None{}:
      (ns_flag, rec_flag)
    case Some{pair}:
      pair

def resolve_pair_empty(is_empty: Bool, +ns_name: String, +rec_name: String) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  match is_empty:
    case True{}:
      (True{}, (ns_name, rec_name))
    case False{}:
      (String.eq(rec_name, ""), (ns_name, rec_name))

def resolve_check(+ns_name: String, +rec_name: String) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  resolve_pair_empty(String.eq(ns_name, ""), ns_name, rec_name)

def key_or_flags(+sub_word: String, +ns_flag: String, +rec_flag: String) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  resolve_check(fst(resolve_split(Key.split_key(sub_word), ns_flag, rec_flag)), snd(resolve_split(Key.split_key(sub_word), ns_flag, rec_flag)))
```

Para no duplicar el split, en la versión final extraer `Key.split_key(sub_word)`
una vez en el llamador y pasarlo como arg (el boceto duplica por brevedad;
el implementador debe pasar el `Maybe` ya computado).

Ramas de dispatch (añadir a la cadena `parse_dispatch_*` existente):

```bend
def parse_is_set(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_set_resolved(key_or_flags(sub_word, flag_at(flag_map, "--ns"), flag_at(flag_map, "--record")), flag_map)

def parse_set_resolved(+checked: Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>, +flag_map: Map<&2, String>) -> Command:
  match checked:
    case (True{}, pair):
      UsageError{"set-needs-key-ns/record"}
    case (False{}, (ns_name, rec_name)):
      Set{flag_at(flag_map, "--session"), ns_name, rec_name, parse_source(flag_map), parse_parent_list(flag_at(flag_map, "--parent"))}
```

`Get` análogo (con `flag_at(flag_map, "--at")`); `Init` → `Init{}`;
`Log` → `Log{flag_at(flag_map, "--limit")}`; `Status` →
`Status{flag_at(flag_map, "--session")}`. `:` cae en `split_key=None` +
flags vacíos → `UsageError{"set-needs-key-ns/record"}` (ley pineada).

`usage_text(topic)`: dispatch con `String.eq(topic, "set")` etc. vía helpers
`decide_*` (mismo patrón que el resto del archivo). Cada rama retorna texto
con sintaxis + ejemplo. Default `""` → overview con 3 ejemplos.

- [ ] **Step 5: Pruebas + gate**

Añadir en `PROOF.bend` un `def Laws.<nombre>(): {==}` por cada ley nueva del
Step 1. Run: `bend PROOF.bend` → PASS. Run: `bolt` → 0 errors.

---

### Task 3: Render — header + tablas + árbol + log/status

**Files:**
- Modify: `src/Render.bend`
- Modify: `LAWS.bend`
- Modify: `PROOF.bend`

- [ ] **Step 1: Leyes de presentación**

```bend
law welcome_plain_has_next_step:
  {String.eq(Render.welcome_header(False{}), "") == False{} : Bool}

law welcome_fallback_has_no_logo:
  {String.eq(Render.welcome_fallback(), "") == False{} : Bool}

law table_diff_header:
  {Render.render_table_diff("a3f9c2d", "c71b00e", Con{LogicalKey.Make{"shop", "b"}, Nil{}}, Nil{}, Nil{}) == "≡ diff a3f9c2d..c71b00e  (+1 ~0 -0)\n  + shop/b" : String}

law tree_renders_entries:
  {Render.render_tree("h", Con{LogicalKey.Make{"shop", "limits"}, Nil{}}) == "tree:h (1 entries)\n├─ shop/limits" : String}
```

- [ ] **Step 2: Ver rojo**

Run: `bend PROOF.bend`
Expected: FAIL (faltan las 3 defs)

- [ ] **Step 3: Implementación mínima**

```bend
def ber_logo() -> String:
  "██████╗ ███████╗██████╗\n██╔══██╗██╔════╝██╔══██╗\n██████╔╝█████╗  ██████╔╝\n██╔══██╗██╔══╝  ██╔══██╗\n██████╔╝███████╗██║  ██║\n╚═════╝ ╚══════╝╚═╝  ╚═╝"

def welcome_body() -> String:
  "Welcome to Ber — save, version, merge.\n→ try: ber set demo/hello --text \"world\"\n→ then: ber get demo/hello"

def welcome_fallback() -> String:
  "ber\n" ++ welcome_body()

def welcome_header(color_on: Bool) -> String:
  match color_on:
    case True{}:
      color_wrap(True{}, "36", ber_logo()) ++ "\n" ++ welcome_body()
    case False{}:
      ber_logo() ++ "\n" ++ welcome_body()
```

def render_table_diff(+from_id: String, +to_id: String, +added: List<&2, LogicalKey.LogicalKey>, +removed: List<&2, LogicalKey.LogicalKey>, +mods: List<&2, Comparison.ModifiedEntry>) -> String:
  "≡ diff " ++ from_id ++ ".." ++ to_id ++ "  (+" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, added)) ++ " ~" ++ Nat.show(List.length(&2, Comparison.ModifiedEntry, mods)) ++ " -" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, removed)) ++ ")" ++ render_added_lines(added) ++ render_removed_lines(removed) ++ render_modified_detail(mods)

def render_tree(+tree_hash: String, +keys: List<&2, LogicalKey.LogicalKey>) -> String:
  "tree:" ++ tree_hash ++ " (" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, keys)) ++ " entries)" ++ render_tree_lines(keys)

def render_log_line(+short_id: String, +summary: String) -> String:
  short_id ++ " - " ++ summary

def render_status(+session_id: String, +keys: List<&2, LogicalKey.LogicalKey>) -> String:
  "staged (session " ++ session_id ++ "): " ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, keys)) ++ " keys" ++ render_tree_lines(keys)
```

Helpers `render_added_lines` / `render_removed_lines` / `render_tree_lines`:
recursión con `acc ++ "\n  + " ++ encode` / `"\n├─ " ++ encode`, leaf-first,
mismo estilo que `render_key_list_tail` existente. `Ok{text}` sigue sin ANSI.

- [ ] **Step 4: Pruebas + gate**

Añadir `def Laws.welcome_plain_has_next_step(): {==}`,
`def Laws.welcome_fallback_has_no_logo(): {==}` etc. en `PROOF.bend`.
Run: `bend PROOF.bend` → PASS. Run: `bolt` → 0 errors.

---

### Task 4: Run — init/set/get/log/status + auto-color TTY

**Files:**
- Modify: `src/Run.bend`

Sin leyes nuevas (efectos; se verifica con smoke). Respetar: do-locals nunca
matcheados, pares fluyen a defs que matchean parámetros.

- [ ] **Step 1: detect_tty + resolución de color**

```bend
def tty_yes(is_zero: Bool) -> Bool:
  match is_zero:
    case True{}:
      True{}
    case False{}:
      False{}

def detect_tty() -> IO(Bool):
  do IO<Bool>:
    res : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("test", Con{"-t", Con{"1", Nil{}}}, "", (65536 : U32), (5000 : U32))
    match res:
      case Fail{error}:
        return False{}
      case Done{triple}:
        match triple:
          case (code, pair):
            return tty_yes(code == (0 : U32))
```

Resolución (pura, testeable a mano):

```bend
def resolve_color(colors_flag: Bool, no_colors: Bool, json_out: Bool, is_tty: Bool, term_dumb: Bool, no_color_env: Bool) -> Bool:
  match colors_flag:
    case True{}:
      True{}
    case False{}:
      decide_auto(no_colors, json_out, is_tty, term_dumb, no_color_env)
```

`decide_auto` anidado con `Bool` args: si cualquiera de
`no_colors/json_out/term_dumb/no_color_env` es `True` → `False`;
si no y `is_tty` → `True`; si no → `False`. `TERM` y `NO_COLOR` se leen vía
`Process.run("printenv", ...)` o `IO.getenv` si existe; si la API no existe,
fase 1 usa `test -t 1` + flags y deja `TERM/NO_COLOR` como follow-up anotado.

`finish_argv` ahora: `is_tty <- detect_tty()` antes de `render_outcome`,
`color_on = resolve_color(...)`.

- [ ] **Step 2: run_init / run_set / run_get / run_log / run_status**

```bend
def run_init(+store_dir: String, color_on: Bool, rich_logo: Bool) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    open_result : Result<&1, &1, U32 & String, Store.Handle> <- open_cli_store(store_dir)
    match open_result:
      case Fail{error}:
        return Render.IoError{"store-failed"}
      case Done{store}:
        return finish_init_ok(store_dir, color_on, rich_logo)

def finish_init_rich(use_rich: Bool, color_on: Bool) -> String:
  match use_rich:
    case True{}:
      Render.welcome_header(color_on)
    case False{}:
      Render.welcome_fallback()

def finish_init_ok(+store_dir: String, color_on: Bool, rich_logo: Bool) -> Render.Outcome:
  Render.Ok{finish_init_rich(rich_logo, color_on) ++ "\nstore ready at " ++ store_dir}
```

`rich_logo = is_tty AND NOT term_dumb AND NOT lang_c` (se resuelve en `Run`
junto a `color_on`; el fallback también se usa en pipe). `color_on=False`
además implica sin ANSI aunque haya logo.

`run_set` = `run_write_source` existente con `(ns, record)` ya resueltos.
`run_get_head`: si `commit_id == ""`, primero resuelve head (nuevo
`Ber.read_head` o `latest_commit`; si `ber-core` no lo expone, usar
`read_tree_at` sobre lista conocida — spike en implementación, fallback:
exigir `--at` con usage-error amable `get needs --at or HEAD` si no hay API).
Ramas nuevas en `execute` para `Init/Set/Get/Log/Status`.

- [ ] **Step 3: Smoke manual (no commit aún)**

Run:
```bash
bend cli.bend -o /tmp/ber-friendly
export S=/tmp/.ber-friendly; rm -rf $S
/tmp/ber-friendly init
/tmp/ber-friendly set shop/limits --text "hello" --session ana
/tmp/ber-friendly get shop/limits --session ana
/tmp/ber-friendly log --short
/tmp/ber-friendly status --session ana
/tmp/ber-friendly set shop:limits --text x --session ana
/tmp/ber-friendly diff --from A --to B --verbose | cat
```
Expected: `init` header + `store ready`; `set` → `committed:<id>`; `get` →
`read=hello`; `:` → `usage-error: set-needs-key-ns/record` exit 2; pipe →
sin ANSI.

---

### Task 5: README — quickstart amable

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Añadir sección sin borrar la vieja**

Insertar tras `## Quickstart` una subsección `### Amable (recomendado)`:

```markdown
### Amable (recomendado)

```bash
bend cli.bend -o ber
./ber init
export S=./.ber-shop
./ber set shop-config/limits --json '{"max_items": 100}' --session ana
./ber get shop-config/limits --session ana
./ber log --short
./ber diff --from $BASE --to $A --verbose
```

Atajos: `set` = `write`, `get` = `record get`. Clave en un solo arg
`ns/record` (`:` no válido). Color automático en terminal, plano en pipes;
`--no-colors` lo apaga, `--colors` lo fuerza, `--json` nunca colorea.
Referencia avanzada con `--ns/--record`: ver sección Comandos.
```

- [ ] **Step 2: Verificar ejemplos copiables**

Run: copiar cada comando del nuevo quickstart en `/tmp` y confirmar que
funcionan (mismo smoke que Task 4). Si alguno falla, corregir README, no el
código (el código ya pasó smoke).

---

### Task 6: Gate final

- [ ] **Step 1: Proof + lint**

Run: `bend PROOF.bend`
Expected: PASS verde (33 leyes viejas + ~12 nuevas)

Run: `bolt`
Expected: 0 errors

- [ ] **Step 2: Smoke cruzado TTY + pipe**

Run: todo el smoke de Task 4 más `./ber help set`, `./ber help merge`,
`./ber --help`. Confirmar: header visible, tablas alineadas, `:` → exit 2,
`--json` sin ANSI, pipe sin ANSI.

## Self-Review

1. **Spec coverage:** (ver nota as-built debajo) §3 KEY/`:`/fallback/defaults → Tasks 1-2+4. §4 help →
   Task 2 (`usage_text`) + Task 6 (`help` smoke). §5 init header → Tasks 3-4.
   §6 tablas/árbol/log/status → Tasks 3-4. §7 auto-color → Task 4.
   §8 archivos → Tasks 0-5. §10 gate/README → Tasks 5-6. Sin huecos.
2. **Placeholder scan:** sin TBD/TODO; cada paso trae código Bend concreto,
   comandos exactos y expected output. `decide_auto` y `render_*_lines` se
   describen con patrón existente (`render_key_list_tail`), no como
   "manejar edge cases".
3. **Type consistency:** `Command{Set/Get/Log/Status/Init}` y
   `Opts{..., no_colors}` se definen en Task 2 y se usan igual en Task 4.
   `Key.split_key` retorna `Maybe<(ns, record)>` en Tasks 1-2. `color_on: Bool`
   fluye igual en Tasks 3-4.

## As-built deviations (2026-09-28, verificadas en smoke)

1. **Task 0/1:** `split_key` usa `String.split` nativo (no scan manual):
   sin riesgo de recursión mutua, `:` se rechaza vía `String.contains`.
   Leyes extra: `split_key_inner_colon_is_none`, `split_key_multi_slash_is_none`
   (`a/b/c` → `None` directo, mismo `UsageError` observable).
2. **Task 2 extra:** `ber help <topic>` no ruteaba (el tópico solo venía de
   `--for`): `parse_is_help` ahora prefiere `sub_word` + ley
   `parse_help_topic_routes`. `--help`/`-h` intactos.
3. **Task 4 reescrita:** sin primitiva TTY en Bend → color **opt-in con
   auto-off** (`NO_COLOR`/`TERM=dumb`/`--no-colors`/`--json` vetan `--colors`);
   `U32.is_eq` en vez de `==`; `match` no entra en `do` y la recursión mutua
   está prohibida → `log`/`get`-HEAD no caminan padres: journal append-only
   `<store>/LOG` (una id por línea; `log` = últimas N líneas cortas,
   head = última línea; tail acotado a 16 KiB vía `size`+`read_at`).
   `Result`/`File`/`Sigma` con recursos nunca llevan `+`; orden leaf-first
   estricto en todo `Run.bend`.
4. **B2 cableado:** `diff --verbose` usa `render_table_diff` (antes solo
   existía + ley). `bolt` no instalado en este entorno → gate = PROOF + smoke.
