import Base
import ber-core-store@0.1.2.0/src/LogicalKey.bend as LogicalKey
import ber-core-store@0.1.2.0/src/Comparison.bend as Comparison

# Pure presentation: every CLI result maps to exactly one Outcome; Run owns
# the Ber.* → Outcome mapping, this module owns Outcome → text/code/hint.
# Color is opt-in via Human{True{}, ...} (--colors); laws pin the plain
# forms so color never breaks proofs.

type Outcome is Data:
  Ok{text: String}
  Merged{commit_id: String}
  Conflict{count_text: String, keys_text: String, first_id: String, second_id: String}
  Unprovable{reason: String}
  Absent{what: String}
  UsageError{message: String}
  IoError{message: String}

type HumanOpts is Data:
  Human{color_on: Bool, verbose: Bool}

def plain_opts() -> HumanOpts:
  Human{False{}, False{}}

def opts_of(colors_on: Bool, verbose: Bool) -> HumanOpts:
  Human{colors_on, verbose}

def exit_code_of(outcome: Outcome) -> U32:
  match outcome:
    case Ok{text}:
      (0 : U32)
    case Merged{commit_id}:
      (0 : U32)
    case Conflict{count_text, keys_text, first_id, second_id}:
      (10 : U32)
    case Unprovable{reason}:
      (20 : U32)
    case Absent{what}:
      (30 : U32)
    case UsageError{message}:
      (2 : U32)
    case IoError{message}:
      (3 : U32)

# True for the two zero-exit outcomes; lets cli.bend branch without U32 ==.
def succeeded(outcome: Outcome) -> Bool:
  match outcome:
    case Ok{text}:
      True{}
    case Merged{commit_id}:
      True{}
    case _:
      False{}

def hint_conflict(+first_id: String, +second_id: String) -> String:
  "hint: ber diff --from " ++ first_id ++ " --to " ++ second_id ++ " --verbose"

def hint_unprovable_verify(is_verify_failed: Bool) -> String:
  match is_verify_failed:
    case True{}:
      "hint: ber certificate verify --first <a> --second <b> --base <c> --tree <h>"
    case False{}:
      "hint: check parents and strategy (only union-disjoint)"

def hint_unprovable_no_ancestor(is_no_ancestor: Bool, +reason: String) -> String:
  match is_no_ancestor:
    case True{}:
      "hint: ber commit show-tree --at <each-parent> to review parents"
    case False{}:
      hint_unprovable_verify(String.eq(reason, "verify-failed"))

def hint_unprovable(+reason: String) -> String:
  hint_unprovable_no_ancestor(String.eq(reason, "no-common-ancestor"), reason)

def hint_for(outcome: Outcome) -> String:
  match outcome:
    case Conflict{count_text, keys_text, first_id, second_id}:
      hint_conflict(first_id, second_id)
    case Unprovable{reason}:
      hint_unprovable(reason)
    case Absent{what}:
      "hint: check --ns/--record/--at; absent reads exit 30"
    case UsageError{message}:
      "hint: ber --help"
    case IoError{message}:
      "hint: check --store dir and file permissions"
    case Ok{text}:
      ""
    case Merged{commit_id}:
      ""

def color_wrap(color_on: Bool, +code: String, +text: String) -> String:
  match color_on:
    case True{}:
      "\u{1B}[" ++ code ++ "m" ++ text ++ "\u{1B}[0m"
    case False{}:
      text

def render_human_colored(outcome: Outcome, color_on: Bool) -> String:
  match outcome:
    case Ok{text}:
      text
    case Merged{commit_id}:
      color_wrap(color_on, "32", "merged:") ++ commit_id
    case Conflict{count_text, keys_text, first_id, second_id}:
      color_wrap(color_on, "31", "conflict:") ++ count_text ++ " " ++ keys_text ++ "\n" ++ hint_conflict(first_id, second_id)
    case Unprovable{+reason}:
      color_wrap(color_on, "33", "unprovable:") ++ reason ++ "\n" ++ hint_unprovable(reason)
    case Absent{what}:
      "absent:" ++ what ++ "\n" ++ "hint: check --ns/--record/--at; absent reads exit 30"
    case UsageError{message}:
      "usage-error:" ++ message ++ "\n" ++ "hint: ber --help"
    case IoError{message}:
      "io-error:" ++ message ++ "\n" ++ "hint: check --store dir and file permissions"

def render_human(outcome: Outcome, +opts: HumanOpts) -> String:
  match opts:
    case Human{color_on, verbose}:
      render_human_colored(outcome, color_on)

def render_json(outcome: Outcome) -> String:
  match outcome:
    case Ok{text}:
      "{\"status\":\"ok\",\"output\":\"" ++ text ++ "\"}"
    case Merged{commit_id}:
      "{\"status\":\"merged\",\"commit\":\"" ++ commit_id ++ "\"}"
    case Conflict{count_text, keys_text, first_id, second_id}:
      "{\"status\":\"conflict\",\"count\":\"" ++ count_text ++ "\",\"keys\":\"" ++ keys_text ++ "\"}"
    case Unprovable{reason}:
      "{\"status\":\"unprovable\",\"reason\":\"" ++ reason ++ "\"}"
    case Absent{what}:
      "{\"status\":\"absent\",\"what\":\"" ++ what ++ "\"}"
    case UsageError{message}:
      "{\"status\":\"usage-error\",\"message\":\"" ++ message ++ "\"}"
    case IoError{message}:
      "{\"status\":\"io-error\",\"message\":\"" ++ message ++ "\"}"

def render_outcome(outcome: Outcome, json_out: Bool, +opts: HumanOpts) -> String:
  match json_out:
    case True{}:
      render_json(outcome)
    case False{}:
      render_human(outcome, opts)

# Space-joined "ns/record" list; empty reads as "".
def render_key_list_tail(+tail_keys: List<&2, LogicalKey.LogicalKey>, +acc: String) -> String:
  match tail_keys:
    case Nil{}:
      acc
    case Con{head_key, rest_keys}:
      render_key_list_tail(rest_keys, acc ++ " " ++ LogicalKey.encode_logical_key(head_key))

def render_key_list(keys: List<&2, LogicalKey.LogicalKey>) -> String:
  match keys:
    case Nil{}:
      ""
    case Con{head_key, tail_keys}:
      render_key_list_tail(tail_keys, LogicalKey.encode_logical_key(head_key))

def render_modified_line(+entry: Comparison.ModifiedEntry) -> String:
  match entry:
    case Comparison.Changed{changed_key, before_hash, after_hash}:
      "\nmodified:" ++ LogicalKey.encode_logical_key(changed_key) ++ " " ++ before_hash ++ "->" ++ after_hash

def render_modified_go(+entries: List<&2, Comparison.ModifiedEntry>, +acc: String) -> String:
  match entries:
    case Nil{}:
      acc
    case Con{head_entry, rest_entries}:
      render_modified_go(rest_entries, acc ++ render_modified_line(head_entry))

def render_modified_detail(+entries: List<&2, Comparison.ModifiedEntry>) -> String:
  render_modified_go(entries, "")

# Pinned to pack.json name@version; bump together.
def version_text() -> String:
  "ber-cli 0.2.2.0"

# Friendly header: box-drawing logo on TTY, plain fallback otherwise.
# English only; Ok{text} never carries ANSI (existing laws untouched).
def ber_logo() -> String:
  "██████╗ ███████╗██████╗\n██╔══██╗██╔════╝██╔══██╗\n██████╔╝█████╗  ██████╔╝\n██╔══██╗██╔══╝  ██╔══██╗\n██████╔╝███████╗██║  ██║\n╚═════╝ ╚══════╝╚═╝  ╚═╝"

def welcome_body() -> String:
  "Welcome to Ber — save, version, merge.\n→ try: ber set demo/hello --text \"world\"\n→ then: ber get demo/hello"

def welcome_fallback() -> String:
  version_text() ++ "\n" ++ welcome_body()

def welcome_header_colored(color_on: Bool) -> String:
  match color_on:
    case True{}:
      color_wrap(True{}, "36", ber_logo()) ++ "\n" ++ version_text() ++ "\n" ++ welcome_body()
    case False{}:
      ber_logo() ++ "\n" ++ version_text() ++ "\n" ++ welcome_body()

def welcome_header(+opts: HumanOpts) -> String:
  match opts:
    case Human{color_on, verbose}:
      welcome_header_colored(color_on)

# Aligned table diff: header counts plus one line per key.
def render_added_lines_go(+keys: List<&2, LogicalKey.LogicalKey>, +acc: String) -> String:
  match keys:
    case Nil{}:
      acc
    case Con{head_key, rest_keys}:
      render_added_lines_go(rest_keys, acc ++ "\n  + " ++ LogicalKey.encode_logical_key(head_key))

def render_added_lines(keys: List<&2, LogicalKey.LogicalKey>) -> String:
  render_added_lines_go(keys, "")

def render_removed_lines_go(+keys: List<&2, LogicalKey.LogicalKey>, +acc: String) -> String:
  match keys:
    case Nil{}:
      acc
    case Con{head_key, rest_keys}:
      render_removed_lines_go(rest_keys, acc ++ "\n  - " ++ LogicalKey.encode_logical_key(head_key))

def render_removed_lines(keys: List<&2, LogicalKey.LogicalKey>) -> String:
  render_removed_lines_go(keys, "")

def render_table_diff(+from_id: String, +to_id: String, +added: List<&2, LogicalKey.LogicalKey>, +removed: List<&2, LogicalKey.LogicalKey>, +mods: List<&2, Comparison.ModifiedEntry>) -> String:
  "≡ diff " ++ from_id ++ ".." ++ to_id ++ "  (+" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, added)) ++ " ~" ++ Nat.show(List.length(&2, Comparison.ModifiedEntry, mods)) ++ " -" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, removed)) ++ ")" ++ render_added_lines(added) ++ render_removed_lines(removed) ++ render_modified_detail(mods)

# Tree view for show-tree / status.
def render_tree_lines_go(+keys: List<&2, LogicalKey.LogicalKey>, +acc: String) -> String:
  match keys:
    case Nil{}:
      acc
    case Con{head_key, rest_keys}:
      render_tree_lines_go(rest_keys, acc ++ "\n├─ " ++ LogicalKey.encode_logical_key(head_key))

def render_tree_lines(keys: List<&2, LogicalKey.LogicalKey>) -> String:
  render_tree_lines_go(keys, "")

def render_tree(+tree_hash: String, +keys: List<&2, LogicalKey.LogicalKey>) -> String:
  "tree:" ++ tree_hash ++ " (" ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, keys)) ++ " entries)" ++ render_tree_lines(keys)

def render_log_line(+short_id: String, +summary: String) -> String:
  short_id ++ " - " ++ summary

def render_status(+session_id: String, +keys: List<&2, LogicalKey.LogicalKey>) -> String:
  "staged (session " ++ session_id ++ "): " ++ Nat.show(List.length(&2, LogicalKey.LogicalKey, keys)) ++ " keys" ++ render_tree_lines(keys)
