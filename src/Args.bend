import Base
import ./Key.bend as NsKey

# CLI syntax types. ValueSource is syntax-level: FromFile resolves in Run
# (needs File IO), never in pure code.
#
# Bend forbids matching on computed values AND mutual recursion, and the
# List<String> from IO.args is single-use (no +). So argv is consumed in
# exactly ONE structural pass (args_to_split_go): flag lookup never compares
# strings — every token links to its successor in a Map (Base's own checked
# Map.get/Map.has do the lookup) — while head/sub positional slots are
# tracked by matching the Nat counter (0n / 1n+p patterns). Every String.eq
# result travels as a Bool argument into a decide-style helper matching on
# the parameter (ber-core style). Defs are ordered leaf-first: no def calls
# one written below it.

# One CLI value source; exactly one required per record put / write.
type ValueSource is Data:
  FromText{content: String}
  FromJson{json_text: String}
  FromBlobHex{hex_text: String}
  FromFile{file_path: String, kind_name: String}

# Every subcommand (spec table §4) plus Help and UsageError.
type Command is Data:
  RecordPut{session_id: String, namespace_name: String, record_id: String, source: ValueSource}
  RecordRm{session_id: String, namespace_name: String, record_id: String}
  RecordGet{namespace_name: String, record_id: String, commit_id: String}
  CommitCreate{session_id: String, parents: List<&2, String>, metas: List<&2, String>}
  CommitShowTree{commit_id: String}
  Diff{first_id: String, second_id: String, verbose: Bool}
  Merge{first_id: String, second_id: String, strategy_name: String}
  CertVerify{first_id: String, second_id: String, base_id: String, tree_hash: String, strategy_name: String, laws: List<&2, String>}
  Write{session_id: String, namespace_name: String, record_id: String, source: ValueSource, parents: List<&2, String>}
  Compare{first_id: String, second_id: String}
  MergeVerify{first_id: String, second_id: String}
  Set{session_id: String, namespace_name: String, record_id: String, source: ValueSource, parents: List<&2, String>}
  Get{namespace_name: String, record_id: String, commit_id: String}
  Log{limit_text: String}
  Status{session_id: String}
  Init{}
  Version{}
  Help{topic: String}
  UsageError{message: String}

# Global flags (spec §4 header).
type GlobalOpts is Data:
  Opts{store_dir: String, session_id: String, json_out: Bool, colors_on: Bool, verbose: Bool, no_colors: Bool}

# One-pass argv shape: head/sub positionals plus the token→successor map.
type ArgvSplit is Data:
  Split{head_word: String, sub_word: String, flag_map: Map<&2, String>}

def default_opts() -> GlobalOpts:
  Opts{"./.ber", "", False{}, False{}, False{}, False{}}

def store_dir_of(opts: GlobalOpts) -> String:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      store_dir

def session_of(opts: GlobalOpts) -> String:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      session_id

def json_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      json_out

def colors_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      colors_on

def verbose_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      verbose

def no_colors_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose, no_colors}:
      no_colors

# Prefers the per-command session; falls back to the global one.
def session_or_go(cmd_missing: Bool, +opts: GlobalOpts, +cmd_session: String) -> String:
  match cmd_missing:
    case True{}:
      session_of(opts)
    case False{}:
      cmd_session

def session_or(+opts: GlobalOpts, +cmd_session: String) -> String:
  session_or_go(String.eq(cmd_session, ""), opts, cmd_session)

# Links the pending previous token to the current one; first token links nothing.
def args_to_map_ins(+prev: Maybe<&2, String>, +head_arg: String, +acc: Map<&2, String>) -> Map<&2, String>:
  match prev:
    case None{}:
      acc
    case Some{prev_arg}:
      Map.set(&2, String, acc, prev_arg, head_arg)

# Links a trailing token to "" so dangling flags read as present-but-empty.
def args_to_map_end(+prev: Maybe<&2, String>, +acc: Map<&2, String>) -> Map<&2, String>:
  match prev:
    case None{}:
      acc
    case Some{prev_arg}:
      Map.set(&2, String, acc, prev_arg, "")

# Tracks the head positional by counter value.
def args_to_split_head(+count: Nat, +head_word: String, +head_arg: String) -> String:
  match count:
    case 0n:
      head_arg
    case 1n+rest_count:
      head_word

# Tracks the sub positional by counter value.
def args_to_split_sub_inner(+rest_count: Nat, +sub_word: String, +head_arg: String) -> String:
  match rest_count:
    case 0n:
      head_arg
    case 1n+rest_count_two:
      sub_word

def args_to_split_sub(+count: Nat, +sub_word: String, +head_arg: String) -> String:
  match count:
    case 0n:
      sub_word
    case 1n+rest_count:
      args_to_split_sub_inner(rest_count, sub_word, head_arg)

# Single pass over argv; the list itself always shrinks.
def args_to_split_go(args: List<String>, +acc: Map<&2, String>, +prev: Maybe<&2, String>, +count: Nat, +head_word: String, +sub_word: String) -> ArgvSplit:
  match args:
    case Nil{}:
      Split{head_word, sub_word, args_to_map_end(prev, acc)}
    case Con{+head_arg, tail_args}:
      args_to_split_go(tail_args, args_to_map_ins(prev, head_arg, acc), Some{head_arg}, 1n+count, args_to_split_head(count, head_word, head_arg), args_to_split_sub(count, sub_word, head_arg))

def args_to_split(args: List<String>) -> ArgvSplit:
  args_to_split_go(args, Map.new(&2, String), None{}, 0n, "", "")

# Projects the value out of a Map.get pair; the map half is dropped.
def flag_value_get(found: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
  match found:
    case (unused_map, value_text):
      value_text

# Reads a flag value out of the split map; missing flag yields "".
def flag_at(+flag_map: Map<&2, String>, +flag_name: String) -> String:
  flag_value_get(Map.get(String, "", flag_map, flag_name))

# Projects the presence bit out of a Map.has pair.
def has_flag_found(found: Sigma<&1, &1, Map<&2, String>, _ => Bool>) -> Bool:
  match found:
    case (unused_map, is_present):
      is_present

def has_at(+flag_map: Map<&2, String>, +flag_name: String) -> Bool:
  has_flag_found(Map.has(&2, String, flag_map, flag_name))

# Exactly one of --text/--json/--blob-hex/--file wins, in that priority.
# No source at all answers FromText{""}; the caller detects it (see
# parse_record_put_text_go): empty --text counts as missing by design.
def parse_source_pick_file(file_empty: Bool, +file_val: String, +kind_val: String) -> ValueSource:
  match file_empty:
    case False{}:
      FromFile{file_val, kind_val}
    case True{}:
      FromText{""}

def parse_source_pick_hex(hex_empty: Bool, +hex_val: String, +file_val: String, +kind_val: String) -> ValueSource:
  match hex_empty:
    case False{}:
      FromBlobHex{hex_val}
    case True{}:
      parse_source_pick_file(String.eq(file_val, ""), file_val, kind_val)

def parse_source_pick_json(json_empty: Bool, +json_val: String, +hex_val: String, +file_val: String, +kind_val: String) -> ValueSource:
  match json_empty:
    case False{}:
      FromJson{json_val}
    case True{}:
      parse_source_pick_hex(String.eq(hex_val, ""), hex_val, file_val, kind_val)

def parse_source_pick_text(text_empty: Bool, +text_val: String, +json_val: String, +hex_val: String, +file_val: String, +kind_val: String) -> ValueSource:
  match text_empty:
    case False{}:
      FromText{text_val}
    case True{}:
      parse_source_pick_json(String.eq(json_val, ""), json_val, hex_val, file_val, kind_val)

def parse_source_pick(+text_val: String, +json_val: String, +hex_val: String, +file_val: String, +kind_val: String) -> ValueSource:
  parse_source_pick_text(String.eq(text_val, ""), text_val, json_val, hex_val, file_val, kind_val)

def parse_source(+flag_map: Map<&2, String>) -> ValueSource:
  parse_source_pick(flag_at(flag_map, "--text"), flag_at(flag_map, "--json"), flag_at(flag_map, "--blob-hex"), flag_at(flag_map, "--file"), flag_at(flag_map, "--kind"))

def decide_source_missing(is_empty: Bool, +session_id: String, +namespace_name: String, +record_id: String) -> Command:
  match is_empty:
    case True{}:
      UsageError{"record-put-needs-value"}
    case False{}:
      RecordPut{session_id, namespace_name, record_id, FromText{""}}

def parse_record_put_text_go(text_empty: Bool, +session_id: String, +namespace_name: String, +record_id: String, +content: String, +file_val: String) -> Command:
  match text_empty:
    case True{}:
      decide_source_missing(String.eq(file_val, ""), session_id, namespace_name, record_id)
    case False{}:
      RecordPut{session_id, namespace_name, record_id, FromText{content}}

def parse_record_put_text(+session_id: String, +namespace_name: String, +record_id: String, +content: String, +file_val: String) -> Command:
  parse_record_put_text_go(String.eq(content, ""), session_id, namespace_name, record_id, content, file_val)

def parse_record_put_source(+source: ValueSource, +session_id: String, +namespace_name: String, +record_id: String, +file_val: String) -> Command:
  match source:
    case FromText{content}:
      parse_record_put_text(session_id, namespace_name, record_id, content, file_val)
    case FromJson{json_text}:
      RecordPut{session_id, namespace_name, record_id, FromJson{json_text}}
    case FromBlobHex{hex_text}:
      RecordPut{session_id, namespace_name, record_id, FromBlobHex{hex_text}}
    case FromFile{file_path, kind_name}:
      RecordPut{session_id, namespace_name, record_id, FromFile{file_path, kind_name}}

def parse_record_put(+flag_map: Map<&2, String>) -> Command:
  parse_record_put_source(parse_source(flag_map), flag_at(flag_map, "--session"), flag_at(flag_map, "--ns"), flag_at(flag_map, "--record"), flag_at(flag_map, "--file"))

def parse_record_is_get(is_get: Bool, +flag_map: Map<&2, String>) -> Command:
  match is_get:
    case True{}:
      RecordGet{flag_at(flag_map, "--ns"), flag_at(flag_map, "--record"), flag_at(flag_map, "--at")}
    case False{}:
      UsageError{"unknown-record-subcommand"}

def parse_record_is_rm(is_rm: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_rm:
    case True{}:
      RecordRm{flag_at(flag_map, "--session"), flag_at(flag_map, "--ns"), flag_at(flag_map, "--record")}
    case False{}:
      parse_record_is_get(String.eq(sub_word, "get"), flag_map)

def parse_record_is_put(is_put: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_put:
    case True{}:
      parse_record_put(flag_map)
    case False{}:
      parse_record_is_rm(String.eq(sub_word, "rm"), sub_word, flag_map)

def parse_record(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_record_is_put(String.eq(sub_word, "put"), sub_word, flag_map)

def parse_record_empty(is_empty: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_empty:
    case True{}:
      UsageError{"record-needs-subcommand"}
    case False{}:
      parse_record(sub_word, flag_map)

def parse_commit_is_show_tree(is_show_tree: Bool, +flag_map: Map<&2, String>) -> Command:
  match is_show_tree:
    case True{}:
      CommitShowTree{flag_at(flag_map, "--at")}
    case False{}:
      UsageError{"unknown-commit-subcommand"}

def parse_parent_list_go(parent_missing: Bool, +parent_val: String) -> List<&2, String>:
  match parent_missing:
    case True{}:
      Nil{}
    case False{}:
      Con{parent_val, Nil{}}

def parse_parent_list(+parent_val: String) -> List<&2, String>:
  parse_parent_list_go(String.eq(parent_val, ""), parent_val)

def parse_commit_is_create(is_create: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_create:
    case True{}:
      CommitCreate{flag_at(flag_map, "--session"), parse_parent_list(flag_at(flag_map, "--parent")), Nil{}}
    case False{}:
      parse_commit_is_show_tree(String.eq(sub_word, "show-tree"), flag_map)

def parse_commit_sub(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_commit_is_create(String.eq(sub_word, "create"), sub_word, flag_map)

def parse_commit_empty(is_empty: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_empty:
    case True{}:
      UsageError{"commit-needs-subcommand"}
    case False{}:
      parse_commit_sub(sub_word, flag_map)

def parse_commit(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_commit_empty(String.eq(sub_word, ""), sub_word, flag_map)

def parse_certificate_is_verify(is_verify: Bool, +flag_map: Map<&2, String>) -> Command:
  match is_verify:
    case True{}:
      CertVerify{flag_at(flag_map, "--first"), flag_at(flag_map, "--second"), flag_at(flag_map, "--base"), flag_at(flag_map, "--tree"), "union-disjoint", Nil{}}
    case False{}:
      UsageError{"unknown-certificate-subcommand"}

def parse_certificate_sub(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_certificate_is_verify(String.eq(sub_word, "verify"), flag_map)

def parse_certificate_empty(is_empty: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_empty:
    case True{}:
      UsageError{"certificate-needs-subcommand"}
    case False{}:
      parse_certificate_sub(sub_word, flag_map)

def parse_certificate(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_certificate_empty(String.eq(sub_word, ""), sub_word, flag_map)

def help_topic_empty(is_empty: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_empty:
    case True{}:
      Help{flag_at(flag_map, "--for")}
    case False{}:
      Help{sub_word}

def parse_is_help(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  help_topic_empty(String.eq(sub_word, ""), sub_word, flag_map)

def parse_is_merge_verify(+flag_map: Map<&2, String>) -> Command:
  MergeVerify{flag_at(flag_map, "--first"), flag_at(flag_map, "--second")}

def parse_is_compare(+flag_map: Map<&2, String>) -> Command:
  Compare{flag_at(flag_map, "--from"), flag_at(flag_map, "--to")}

def parse_is_write(+flag_map: Map<&2, String>) -> Command:
  Write{flag_at(flag_map, "--session"), flag_at(flag_map, "--ns"), flag_at(flag_map, "--record"), parse_source(flag_map), parse_parent_list(flag_at(flag_map, "--parent"))}

def parse_is_merge(+flag_map: Map<&2, String>) -> Command:
  Merge{flag_at(flag_map, "--first"), flag_at(flag_map, "--second"), "union-disjoint"}

def parse_is_diff(+flag_map: Map<&2, String>) -> Command:
  Diff{flag_at(flag_map, "--from"), flag_at(flag_map, "--to"), has_at(flag_map, "--verbose")}

def parse_is_certificate(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_certificate(sub_word, flag_map)

def parse_is_commit(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_commit(sub_word, flag_map)

def parse_is_record(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_record_empty(String.eq(sub_word, ""), sub_word, flag_map)

def parse_dispatch_help(is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_help:
    case True{}:
      parse_is_help(sub_word, flag_map)
    case False{}:
      UsageError{"unknown-command"}

def parse_dispatch_merge_verify(is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_merge_verify:
    case True{}:
      parse_is_merge_verify(flag_map)
    case False{}:
      parse_dispatch_help(is_help, sub_word, flag_map)

def parse_dispatch_compare(is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_compare:
    case True{}:
      parse_is_compare(flag_map)
    case False{}:
      parse_dispatch_merge_verify(is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch_write(is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_write:
    case True{}:
      parse_is_write(flag_map)
    case False{}:
      parse_dispatch_compare(is_compare, is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch_merge(is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_merge:
    case True{}:
      parse_is_merge(flag_map)
    case False{}:
      parse_dispatch_write(is_write, is_compare, is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch_diff(is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_diff:
    case True{}:
      parse_is_diff(flag_map)
    case False{}:
      parse_dispatch_merge(is_merge, is_write, is_compare, is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch_certificate(is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_certificate:
    case True{}:
      parse_is_certificate(sub_word, flag_map)
    case False{}:
      parse_dispatch_diff(is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch_commit(is_commit: Bool, is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_commit:
    case True{}:
      parse_is_commit(sub_word, flag_map)
    case False{}:
      parse_dispatch_certificate(is_certificate, is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, sub_word, flag_map)

def parse_dispatch(is_record: Bool, is_commit: Bool, is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_record:
    case True{}:
      parse_is_record(sub_word, flag_map)
    case False{}:
      parse_dispatch_commit(is_commit, is_certificate, is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, sub_word, flag_map)

# KEY (ns/record) or legacy --ns/--record flags. Missing/invalid key threads
# True{} so the caller answers a friendly UsageError.
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

def key_or_flags_pair(+pair: Sigma<&2, &2, String, _ => String>) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  match pair:
    case (ns_name, rec_name):
      resolve_check(ns_name, rec_name)

def key_or_flags_split(+split: Maybe<&2, Sigma<&2, &2, String, _ => String>>, +ns_flag: String, +rec_flag: String) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  key_or_flags_pair(resolve_split(split, ns_flag, rec_flag))

def key_or_flags(+sub_word: String, +ns_flag: String, +rec_flag: String) -> Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>:
  key_or_flags_split(NsKey.split_key(sub_word), ns_flag, rec_flag)

def parse_set_pair_ok(+pair: Sigma<&2, &2, String, _ => String>, +flag_map: Map<&2, String>) -> Command:
  match pair:
    case (ns_name, rec_name):
      Set{flag_at(flag_map, "--session"), ns_name, rec_name, parse_source(flag_map), parse_parent_list(flag_at(flag_map, "--parent"))}

def parse_set_pair(is_missing: Bool, +pair: Sigma<&2, &2, String, _ => String>, +flag_map: Map<&2, String>) -> Command:
  match is_missing:
    case True{}:
      UsageError{"set-needs-key-ns/record"}
    case False{}:
      parse_set_pair_ok(pair, flag_map)

def parse_set_resolved(+checked: Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>, +flag_map: Map<&2, String>) -> Command:
  match checked:
    case (is_missing, pair):
      parse_set_pair(is_missing, pair, flag_map)

def parse_is_set(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_set_resolved(key_or_flags(sub_word, flag_at(flag_map, "--ns"), flag_at(flag_map, "--record")), flag_map)

def parse_get_pair_ok(+pair: Sigma<&2, &2, String, _ => String>, +flag_map: Map<&2, String>) -> Command:
  match pair:
    case (ns_name, rec_name):
      Get{ns_name, rec_name, flag_at(flag_map, "--at")}

def parse_get_pair(is_missing: Bool, +pair: Sigma<&2, &2, String, _ => String>, +flag_map: Map<&2, String>) -> Command:
  match is_missing:
    case True{}:
      UsageError{"get-needs-key-ns/record"}
    case False{}:
      parse_get_pair_ok(pair, flag_map)

def parse_get_resolved(+checked: Sigma<&2, &2, Bool, _ => Sigma<&2, &2, String, _ => String>>, +flag_map: Map<&2, String>) -> Command:
  match checked:
    case (is_missing, pair):
      parse_get_pair(is_missing, pair, flag_map)

def parse_is_get(+sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_get_resolved(key_or_flags(sub_word, flag_at(flag_map, "--ns"), flag_at(flag_map, "--record")), flag_map)

def parse_is_log(+flag_map: Map<&2, String>) -> Command:
  Log{flag_at(flag_map, "--limit")}

def parse_is_status(+flag_map: Map<&2, String>) -> Command:
  Status{flag_at(flag_map, "--session")}

def parse_new_init(is_init: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_init:
    case True{}:
      Init{}
    case False{}:
      parse_dispatch(String.eq(head_word, "record"), String.eq(head_word, "commit"), String.eq(head_word, "certificate"), String.eq(head_word, "diff"), String.eq(head_word, "merge"), String.eq(head_word, "write"), String.eq(head_word, "compare"), String.eq(head_word, "merge-verify"), String.eq(head_word, "help"), sub_word, flag_map)

def parse_new_status(is_status: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_status:
    case True{}:
      parse_is_status(flag_map)
    case False{}:
      parse_new_init(String.eq(head_word, "init"), head_word, sub_word, flag_map)

def parse_new_log(is_log: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_log:
    case True{}:
      parse_is_log(flag_map)
    case False{}:
      parse_new_status(String.eq(head_word, "status"), head_word, sub_word, flag_map)

def parse_new_get(is_get: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_get:
    case True{}:
      parse_is_get(sub_word, flag_map)
    case False{}:
      parse_new_log(String.eq(head_word, "log"), head_word, sub_word, flag_map)

def parse_new_set(is_set: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_set:
    case True{}:
      parse_is_set(sub_word, flag_map)
    case False{}:
      parse_new_get(String.eq(head_word, "get"), head_word, sub_word, flag_map)

def parse_split_empty(head_missing: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match head_missing:
    case True{}:
      UsageError{"empty-argv"}
    case False{}:
      parse_new_set(String.eq(head_word, "set"), head_word, sub_word, flag_map)

def parse_split_head_alias_h(is_h_flag: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_h_flag:
    case True{}:
      parse_is_help(sub_word, flag_map)
    case False{}:
      parse_split_empty(String.eq(head_word, ""), head_word, sub_word, flag_map)

def parse_split_version_short(is_short: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_short:
    case True{}:
      Version{}
    case False{}:
      parse_split_head_alias_h(String.eq(head_word, "-h"), head_word, sub_word, flag_map)

def parse_split_version_flag(is_version_flag: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_version_flag:
    case True{}:
      Version{}
    case False{}:
      parse_split_version_short(String.eq(head_word, "-V"), head_word, sub_word, flag_map)

def parse_split_version(is_version: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_version:
    case True{}:
      Version{}
    case False{}:
      parse_split_version_flag(String.eq(head_word, "--version"), head_word, sub_word, flag_map)

def parse_split_head_alias(is_help_flag: Bool, +head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  match is_help_flag:
    case True{}:
      parse_is_help(sub_word, flag_map)
    case False{}:
      parse_split_version(String.eq(head_word, "version"), head_word, sub_word, flag_map)

def parse_split_head(+head_word: String, +sub_word: String, +flag_map: Map<&2, String>) -> Command:
  parse_split_head_alias(String.eq(head_word, "--help"), head_word, sub_word, flag_map)

def parse_split(+split: ArgvSplit) -> Command:
  match split:
    case Split{head_word, sub_word, flag_map}:
      parse_split_head(head_word, sub_word, flag_map)

def parse_command(argv: List<String>) -> Command:
  parse_split(args_to_split(argv))

def parse_opts_store_go(store_missing: Bool, +store_val: String, +flag_map: Map<&2, String>) -> GlobalOpts:
  match store_missing:
    case True{}:
      Opts{"./.ber", flag_at(flag_map, "--session"), has_at(flag_map, "--json"), has_at(flag_map, "--colors"), has_at(flag_map, "--verbose"), has_at(flag_map, "--no-colors")}
    case False{}:
      Opts{store_val, flag_at(flag_map, "--session"), has_at(flag_map, "--json"), has_at(flag_map, "--colors"), has_at(flag_map, "--verbose"), has_at(flag_map, "--no-colors")}

def parse_opts_store(+store_val: String, +flag_map: Map<&2, String>) -> GlobalOpts:
  parse_opts_store_go(String.eq(store_val, ""), store_val, flag_map)

def parse_opts_map(+flag_map: Map<&2, String>) -> GlobalOpts:
  parse_opts_store(flag_at(flag_map, "--store"), flag_map)

def parse_opts_split(+split: ArgvSplit) -> GlobalOpts:
  match split:
    case Split{head_word, sub_word, flag_map}:
      parse_opts_map(flag_map)

def parse_opts(argv: List<String>) -> GlobalOpts:
  parse_opts_split(args_to_split(argv))

def usage_default(+topic: String) -> String:
  "ber — content-addressed store for versioned records\n\nUsage: ber <command> [args] [flags]\n\nCommands:\n  init                     Create the store (default ./.ber)\n  set KEY SOURCE           Stage and commit in one step (KEY = ns/record)\n  get KEY [--at COMMIT]    Read a value (last commit when --at is omitted)\n  log [--limit N]          Recent commits, short ids\n  status [--session S]     Staged, uncommitted keys\n  diff --from A --to B     Compare two commits (--verbose lists keys)\n  merge --first A --second B\n                           Three-way union-disjoint merge + verification\n  help [topic]             Details for a command\n  version                  Print the version\n\nLow-level (1:1 with ber-core):\n  record put|rm|get        Stage/read values inside a session\n  commit create|show-tree  Materialize/inspect commits\n  write, compare, merge-verify, certificate verify\n\nGlobal flags:\n  --store DIR              Store directory (default ./.ber)\n  --session ID             Session name for staging\n  --json                   Machine-readable output (never colored)\n  --colors                 Kept for compatibility (colors are on by default)\n  --no-colors              Force plain output\n  --verbose                Detailed output where supported\n\nValue sources (set / write / record put):\n  --text T | --json J | --blob-hex H | --file F --kind text|json|blob\n\nExit codes: 0 ok/merged  10 conflict  20 unprovable  30 absent  2 usage  3 io\n\nExamples:\n  ber init\n  ber set shop/limits --text \"hello\" --session demo\n  ber get shop/limits --session demo\n  ber diff --from <a> --to <c> --verbose\n\nDetails: ber help <topic>   (topics: init set get log status merge diff)"

def usage_is_diff(is_diff: Bool, +topic: String) -> String:
  match is_diff:
    case True{}:
      "Usage: ber diff --from A --to B [--verbose]\nCounts added/removed/modified keys; --verbose lists them.\nExample: ber diff --from $A --to $B --verbose"
    case False{}:
      usage_default(topic)

def usage_is_merge(is_merge: Bool, +topic: String) -> String:
  match is_merge:
    case True{}:
      "Usage: ber merge --first A --second B\nThree-way union-disjoint merge plus verification.\nOn conflict (exit 10): ber diff --from A --to B --verbose\nExample: ber merge --first $A --second $C"
    case False{}:
      usage_is_diff(String.eq(topic, "diff"), topic)

def usage_is_init(is_init: Bool, +topic: String) -> String:
  match is_init:
    case True{}:
      "Usage: ber init [--store DIR]\nCreates the store dir and prints a welcome header.\nExample: ber init --store ./.ber"
    case False{}:
      usage_is_merge(String.eq(topic, "merge"), topic)

def usage_is_status(is_status: Bool, +topic: String) -> String:
  match is_status:
    case True{}:
      "Usage: ber status [--session S]\nShows staged keys in the session not yet committed.\nExample: ber status --session ana"
    case False{}:
      usage_is_init(String.eq(topic, "init"), topic)

def usage_is_log(is_log: Bool, +topic: String) -> String:
  match is_log:
    case True{}:
      "Usage: ber log [--limit N]\nLists recent commits, newest first (short ids).\nExample: ber log --short"
    case False{}:
      usage_is_status(String.eq(topic, "status"), topic)

def usage_is_get(is_get: Bool, +topic: String) -> String:
  match is_get:
    case True{}:
      "Usage: ber get NS/RECORD [--at COMMIT]\nReads a value as of a commit; without --at reads HEAD.\nExample: ber get shop/limits --at <commit>\nOn absent (exit 30): check the key with ber log --short"
    case False{}:
      usage_is_log(String.eq(topic, "log"), topic)

def usage_is_set(is_set: Bool, +topic: String) -> String:
  match is_set:
    case True{}:
      "Usage: ber set NS/RECORD (--text T | --json J | --blob-hex H | --file F --kind K) [--session S] [--parent P]\nShortcut for write: stage and commit in one step.\nExample: ber set shop/limits --text \"hello\" --session ana\nOn failure: missing key needs NS/RECORD or --ns/--record (exit 2)"
    case False{}:
      usage_is_get(String.eq(topic, "get"), topic)

def usage_text(+topic: String) -> String:
  usage_is_set(String.eq(topic, "set"), topic)

# Both halves from one argv pass: the split is Data so it can be reused.
def parse_both_go(+split: ArgvSplit) -> Sigma<&2, &2, GlobalOpts, _ => Command>:
  (parse_opts_split(split), parse_split(split))

def parse_both(argv: List<String>) -> Sigma<&2, &2, GlobalOpts, _ => Command>:
  parse_both_go(args_to_split(argv))
