import Base

# CLI syntax types. ValueSource is syntax-level: FromFile resolves in Run
# (needs File IO), never in pure code.
#
# Bend forbids matching on computed values AND mutual recursion, so flag
# lookup never compares strings: args_to_map links every token to its
# successor in a Map (purely structural recursion), and flag_value/has_flag
# read through Map.get/Map.has (Base's own checked code). Positional slots
# (subcommands) are consumed by structural matches; stray positional keys in
# the map are simply never looked up. Every String.eq result travels as a
# Bool argument into a decide-style helper matching on the parameter
# (ber-core style). Defs are ordered leaf-first: no def calls one written
# below it.

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
  Help{topic: String}
  UsageError{message: String}

# Global flags (spec §4 header).
type GlobalOpts is Data:
  Opts{store_dir: String, session_id: String, json_out: Bool, colors_on: Bool, verbose: Bool}

def default_opts() -> GlobalOpts:
  Opts{"./.ber", "", False{}, False{}, False{}}

def store_dir_of(opts: GlobalOpts) -> String:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose}:
      store_dir

def json_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose}:
      json_out

def colors_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose}:
      colors_on

def verbose_flag_of(opts: GlobalOpts) -> Bool:
  match opts:
    case Opts{store_dir, session_id, json_out, colors_on, verbose}:
      verbose

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

# Sliding window over argv; the list itself always shrinks.
def args_to_map_go(args: List<&2, String>, +acc: Map<&2, String>, +prev: Maybe<&2, String>) -> Map<&2, String>:
  match args:
    case Nil{}:
      args_to_map_end(prev, acc)
    case Con{+head_arg, tail_args}:
      args_to_map_go(tail_args, args_to_map_ins(prev, head_arg, acc), Some{head_arg})

def args_to_map(args: List<&2, String>) -> Map<&2, String>:
  args_to_map_go(args, Map.new(&2, String), None{})

# Projects the value out of a Map.get pair; the map half is dropped.
def flag_value_get(found: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
  match found:
    case (unused_map, value_text):
      value_text

# Reads --flag value pairs; missing flag yields "".
def flag_value(+flag_name: String, +args: List<&2, String>) -> String:
  flag_value_get(Map.get(String, "", args_to_map(args), flag_name))

# Projects the presence bit out of a Map.has pair.
def has_flag_found(found: Sigma<&1, &1, Map<&2, String>, _ => Bool>) -> Bool:
  match found:
    case (unused_map, is_present):
      is_present

def has_flag(+flag_name: String, +args: List<&2, String>) -> Bool:
  has_flag_found(Map.has(&2, String, args_to_map(args), flag_name))

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

def parse_source(+args: List<&2, String>) -> ValueSource:
  parse_source_pick(flag_value("--text", args), flag_value("--json", args), flag_value("--blob-hex", args), flag_value("--file", args), flag_value("--kind", args))

def decide_source_missing(is_empty: Bool, +namespace_name: String, +record_id: String) -> Command:
  match is_empty:
    case True{}:
      UsageError{"record-put-needs-value"}
    case False{}:
      RecordPut{"", namespace_name, record_id, FromText{""}}

def parse_record_put_text_go(text_empty: Bool, +namespace_name: String, +record_id: String, +content: String, +file_val: String) -> Command:
  match text_empty:
    case True{}:
      decide_source_missing(String.eq(file_val, ""), namespace_name, record_id)
    case False{}:
      RecordPut{"", namespace_name, record_id, FromText{content}}

def parse_record_put_text(+namespace_name: String, +record_id: String, +content: String, +file_val: String) -> Command:
  parse_record_put_text_go(String.eq(content, ""), namespace_name, record_id, content, file_val)

def parse_record_put_source(+source: ValueSource, +namespace_name: String, +record_id: String, +file_val: String) -> Command:
  match source:
    case FromText{content}:
      parse_record_put_text(namespace_name, record_id, content, file_val)
    case FromJson{json_text}:
      RecordPut{"", namespace_name, record_id, FromJson{json_text}}
    case FromBlobHex{hex_text}:
      RecordPut{"", namespace_name, record_id, FromBlobHex{hex_text}}
    case FromFile{file_path, kind_name}:
      RecordPut{"", namespace_name, record_id, FromFile{file_path, kind_name}}

def parse_record_put(+args: List<&2, String>) -> Command:
  parse_record_put_source(parse_source(args), flag_value("--ns", args), flag_value("--record", args), flag_value("--file", args))

def parse_record_is_get(is_get: Bool, +rest_args: List<&2, String>) -> Command:
  match is_get:
    case True{}:
      RecordGet{flag_value("--ns", rest_args), flag_value("--record", rest_args), flag_value("--at", rest_args)}
    case False{}:
      UsageError{"unknown-record-subcommand"}

def parse_record_is_rm(is_rm: Bool, +sub_name: String, +rest_args: List<&2, String>) -> Command:
  match is_rm:
    case True{}:
      RecordRm{"", flag_value("--ns", rest_args), flag_value("--record", rest_args)}
    case False{}:
      parse_record_is_get(String.eq(sub_name, "get"), rest_args)

def parse_record_is_put(is_put: Bool, +sub_name: String, +rest_args: List<&2, String>) -> Command:
  match is_put:
    case True{}:
      parse_record_put(rest_args)
    case False{}:
      parse_record_is_rm(String.eq(sub_name, "rm"), sub_name, rest_args)

def parse_record_sub(+sub_name: String, +rest_args: List<&2, String>) -> Command:
  parse_record_is_put(String.eq(sub_name, "put"), sub_name, rest_args)

def parse_record(args: List<&2, String>) -> Command:
  match args:
    case Nil{}:
      UsageError{"record-needs-subcommand"}
    case Con{+sub_name, rest_args}:
      parse_record_sub(sub_name, rest_args)

def parse_commit_is_show_tree(is_show_tree: Bool, +rest_args: List<&2, String>) -> Command:
  match is_show_tree:
    case True{}:
      CommitShowTree{flag_value("--at", rest_args)}
    case False{}:
      UsageError{"unknown-commit-subcommand"}

def parse_commit_is_create(is_create: Bool, +sub_name: String, +rest_args: List<&2, String>) -> Command:
  match is_create:
    case True{}:
      CommitCreate{"", Nil{}, Nil{}}
    case False{}:
      parse_commit_is_show_tree(String.eq(sub_name, "show-tree"), rest_args)

def parse_commit_sub(+sub_name: String, +rest_args: List<&2, String>) -> Command:
  parse_commit_is_create(String.eq(sub_name, "create"), sub_name, rest_args)

def parse_commit(args: List<&2, String>) -> Command:
  match args:
    case Nil{}:
      UsageError{"commit-needs-subcommand"}
    case Con{+sub_name, rest_args}:
      parse_commit_sub(sub_name, rest_args)

def parse_certificate_is_verify(is_verify: Bool, +rest_args: List<&2, String>) -> Command:
  match is_verify:
    case True{}:
      CertVerify{flag_value("--first", rest_args), flag_value("--second", rest_args), flag_value("--base", rest_args), flag_value("--tree", rest_args), "union-disjoint", Nil{}}
    case False{}:
      UsageError{"unknown-certificate-subcommand"}

def parse_certificate_sub(+sub_name: String, +rest_args: List<&2, String>) -> Command:
  parse_certificate_is_verify(String.eq(sub_name, "verify"), rest_args)

def parse_certificate(args: List<&2, String>) -> Command:
  match args:
    case Nil{}:
      UsageError{"certificate-needs-subcommand"}
    case Con{+sub_name, rest_args}:
      parse_certificate_sub(sub_name, rest_args)

def parse_is_help(+rest_words: List<&2, String>) -> Command:
  Help{flag_value("--for", rest_words)}

def parse_is_merge_verify(+rest_words: List<&2, String>) -> Command:
  MergeVerify{flag_value("--first", rest_words), flag_value("--second", rest_words)}

def parse_is_compare(+rest_words: List<&2, String>) -> Command:
  Compare{flag_value("--from", rest_words), flag_value("--to", rest_words)}

def parse_is_write(+rest_words: List<&2, String>) -> Command:
  Write{"", flag_value("--ns", rest_words), flag_value("--record", rest_words), parse_source(rest_words), Nil{}}

def parse_is_merge(+rest_words: List<&2, String>) -> Command:
  Merge{flag_value("--first", rest_words), flag_value("--second", rest_words), "union-disjoint"}

def parse_is_diff(+rest_words: List<&2, String>) -> Command:
  Diff{flag_value("--from", rest_words), flag_value("--to", rest_words), has_flag("--verbose", rest_words)}

def parse_is_certificate(+rest_words: List<&2, String>) -> Command:
  parse_certificate(rest_words)

def parse_is_commit(+rest_words: List<&2, String>) -> Command:
  parse_commit(rest_words)

def parse_is_record(+rest_words: List<&2, String>) -> Command:
  parse_record(rest_words)

def parse_dispatch_help(is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_help:
    case True{}:
      parse_is_help(rest_words)
    case False{}:
      UsageError{"unknown-command"}

def parse_dispatch_merge_verify(is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_merge_verify:
    case True{}:
      parse_is_merge_verify(rest_words)
    case False{}:
      parse_dispatch_help(is_help, rest_words)

def parse_dispatch_compare(is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_compare:
    case True{}:
      parse_is_compare(rest_words)
    case False{}:
      parse_dispatch_merge_verify(is_merge_verify, is_help, rest_words)

def parse_dispatch_write(is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_write:
    case True{}:
      parse_is_write(rest_words)
    case False{}:
      parse_dispatch_compare(is_compare, is_merge_verify, is_help, rest_words)

def parse_dispatch_merge(is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_merge:
    case True{}:
      parse_is_merge(rest_words)
    case False{}:
      parse_dispatch_write(is_write, is_compare, is_merge_verify, is_help, rest_words)

def parse_dispatch_diff(is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_diff:
    case True{}:
      parse_is_diff(rest_words)
    case False{}:
      parse_dispatch_merge(is_merge, is_write, is_compare, is_merge_verify, is_help, rest_words)

def parse_dispatch_certificate(is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_certificate:
    case True{}:
      parse_is_certificate(rest_words)
    case False{}:
      parse_dispatch_diff(is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, rest_words)

def parse_dispatch_commit(is_commit: Bool, is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_commit:
    case True{}:
      parse_is_commit(rest_words)
    case False{}:
      parse_dispatch_certificate(is_certificate, is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, rest_words)

def parse_dispatch(is_record: Bool, is_commit: Bool, is_certificate: Bool, is_diff: Bool, is_merge: Bool, is_write: Bool, is_compare: Bool, is_merge_verify: Bool, is_help: Bool, +rest_words: List<&2, String>) -> Command:
  match is_record:
    case True{}:
      parse_is_record(rest_words)
    case False{}:
      parse_dispatch_commit(is_commit, is_certificate, is_diff, is_merge, is_write, is_compare, is_merge_verify, is_help, rest_words)

def parse_head(+head_word: String, +rest_words: List<&2, String>) -> Command:
  parse_dispatch(String.eq(head_word, "record"), String.eq(head_word, "commit"), String.eq(head_word, "certificate"), String.eq(head_word, "diff"), String.eq(head_word, "merge"), String.eq(head_word, "write"), String.eq(head_word, "compare"), String.eq(head_word, "merge-verify"), String.eq(head_word, "help"), rest_words)

def parse_command(argv: List<&2, String>) -> Command:
  match argv:
    case Nil{}:
      UsageError{"empty-argv"}
    case Con{+head_word, rest_words}:
      parse_head(head_word, rest_words)

def parse_opts_store_go(store_missing: Bool, +store_val: String, +argv: List<&2, String>) -> GlobalOpts:
  match store_missing:
    case True{}:
      Opts{"./.ber", flag_value("--session", argv), has_flag("--json", argv), has_flag("--colors", argv), has_flag("--verbose", argv)}
    case False{}:
      Opts{store_val, flag_value("--session", argv), has_flag("--json", argv), has_flag("--colors", argv), has_flag("--verbose", argv)}

def parse_opts_store(+store_val: String, +argv: List<&2, String>) -> GlobalOpts:
  parse_opts_store_go(String.eq(store_val, ""), store_val, argv)

def parse_opts(+argv: List<&2, String>) -> GlobalOpts:
  parse_opts_store(flag_value("--store", argv), argv)

def usage_text(+topic: String) -> String:
  "ber record put --ns N --record R (--text T | --json J | --blob-hex H | --file F --kind K)\nber record get --ns N --record R --at COMMIT\nber diff --from A --to B [--verbose]\nber merge --first A --second B\nber --help"
