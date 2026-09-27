import Base

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

def render_human(outcome: Outcome, +opts: HumanOpts) -> String:
  match outcome:
    case Ok{text}:
      text
    case Merged{commit_id}:
      "merged:" ++ commit_id
    case Conflict{count_text, keys_text, first_id, second_id}:
      "conflict:" ++ count_text ++ " " ++ keys_text ++ "\n" ++ hint_conflict(first_id, second_id)
    case Unprovable{+reason}:
      "unprovable:" ++ reason ++ "\n" ++ hint_unprovable(reason)
    case Absent{what}:
      "absent:" ++ what ++ "\n" ++ "hint: check --ns/--record/--at; absent reads exit 30"
    case UsageError{message}:
      "usage-error:" ++ message ++ "\n" ++ "hint: ber --help"
    case IoError{message}:
      "io-error:" ++ message ++ "\n" ++ "hint: check --store dir and file permissions"

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
