import Base
import ./src/Args.bend as Args
import ./src/Input.bend as Input
import ber-core-store@0.1.1.0/src/Value.bend as Value
import ./src/Render.bend as Render
import ber-core-store@0.1.1.0/src/LogicalKey.bend as LogicalKey

# CLI laws land here, one family per task (Args, Input, Render).
# Empty shell so the gate compiles before any law exists.

# Args family: concrete parse instances, each computes to its Command.
# record get parses to its Command.
law parse_record_get:
  {Args.parse_command(Con{"record", Con{"get", Con{"--ns", Con{"ledger", Con{"--record", Con{"r1", Con{"--at", Con{"c1", Nil{}}}}}}}}}) == Args.RecordGet{"ledger", "r1", "c1"} : Args.Command}

# record put with --text parses to its Command.
law parse_record_put_text:
  {Args.parse_command(Con{"record", Con{"put", Con{"--ns", Con{"ledger", Con{"--record", Con{"r1", Con{"--text", Con{"v1", Nil{}}}}}}}}}) == Args.RecordPut{"", "ledger", "r1", Args.FromText{"v1"}} : Args.Command}

# diff parses from/to without verbose.
law parse_diff:
  {Args.parse_command(Con{"diff", Con{"--from", Con{"a", Con{"--to", Con{"b", Nil{}}}}}}) == Args.Diff{"a", "b", False{}} : Args.Command}

# merge pins the union-disjoint strategy.
law parse_merge:
  {Args.parse_command(Con{"merge", Con{"--first", Con{"a", Con{"--second", Con{"b", Nil{}}}}}}) == Args.Merge{"a", "b", "union-disjoint"} : Args.Command}

# bare commit create parses with empty parents.
law parse_commit_create:
  {Args.parse_command(Con{"commit", Con{"create", Nil{}}}) == Args.CommitCreate{"", Nil{}, Nil{}} : Args.Command}

# empty argv is a usage error.
law parse_empty_is_usage_error:
  {Args.parse_command(Nil{}) == Args.UsageError{"empty-argv"} : Args.Command}

# unknown head word is a usage error.
law parse_unknown_is_usage_error:
  {Args.parse_command(Con{"frobnicate", Nil{}}) == Args.UsageError{"unknown-command"} : Args.Command}

# usage text never renders empty.
law usage_text_nonempty:
  {String.eq(Args.usage_text("record"), "") == False{} : Bool}

# default store dir is ./.ber.
law default_store_dir:
  {Args.store_dir_of(Args.default_opts()) == "./.ber" : String}

# --colors opts in color.
law colors_flag_on:
  {Args.colors_flag_of(Args.parse_opts(Con{"--colors", Nil{}})) == True{} : Bool}

# color stays off without the flag.
law colors_flag_default_off:
  {Args.colors_flag_of(Args.parse_opts(Nil{})) == False{} : Bool}

# Input family: pure flag→Value mapping instances.
# --text rebuilds its Text value.
law input_text_roundtrip:
  for content: String
  {Input.source_to_value(Args.FromText{content}) == Some{Value.Text{content}} : Maybe<&2, Value.Value>}

# files never resolve in pure code.
law input_file_is_none:
  for file_path: String
  for kind_name: String
  {Input.source_to_value(Args.FromFile{file_path, kind_name}) == None{} : Maybe<&2, Value.Value>}

# malformed hex resolves to nothing.
law input_bad_hex_is_none:
  {Input.source_to_value(Args.FromBlobHex{"zz"}) == None{} : Maybe<&2, Value.Value>}

# empty hex is the empty blob.
law input_empty_blob_hex:
  {Input.source_to_value(Args.FromBlobHex{""}) == Some{Value.Blob{Nil{}}} : Maybe<&2, Value.Value>}

# Render family: exit codes, plain renders, hints, JSON shapes.
# merged exits zero.
law exit_merge_success:
  {Render.exit_code_of(Render.Merged{"c1"}) == (0 : U32) : U32}

# conflicts exit ten.
law exit_conflict:
  {Render.exit_code_of(Render.Conflict{"2", "ledger/r1", "a", "b"}) == (10 : U32) : U32}

# unprovable exits twenty.
law exit_unprovable:
  {Render.exit_code_of(Render.Unprovable{"no-common-ancestor"}) == (20 : U32) : U32}

# absent exits thirty.
law exit_absent:
  {Render.exit_code_of(Render.Absent{"ledger/r1"}) == (30 : U32) : U32}

# usage errors exit two.
law exit_usage:
  {Render.exit_code_of(Render.UsageError{"unknown-command"}) == (2 : U32) : U32}

# plain ok exits zero.
law exit_ok:
  {Render.exit_code_of(Render.Ok{"read=v1"}) == (0 : U32) : U32}

# blob renders stay opaque.
law blob_never_expands:
  {Render.render_human(Render.Ok{"read=<blob 3 bytes>"}, Render.plain_opts()) == "read=<blob 3 bytes>" : String}

# conflict hints point at diff.
law conflict_hint_mentions_diff:
  {Render.hint_for(Render.Conflict{"2", "ledger/r1", "a", "b"}) == "hint: ber diff --from a --to b --verbose" : String}

# ok renders its JSON shape.
law json_status_ok:
  {Render.render_json(Render.Ok{"read=v1"}) == "{\"status\":\"ok\",\"output\":\"read=v1\"}" : String}

# ok counts as success.
law succeeded_ok:
  {Render.succeeded(Render.Ok{"read=v1"}) == True{} : Bool}

# conflict counts as failure.
law succeeded_conflict_false:
  {Render.succeeded(Render.Conflict{"2", "ledger/r1", "a", "b"}) == False{} : Bool}

# per-command session beats the global one.
law session_cmd_wins:
  {Args.session_or(Args.Opts{"./.ber", "s2", False{}, False{}, False{}}, "s1") == "s1" : String}

# empty command session falls back to global.
law session_opts_fallback:
  {Args.session_or(Args.Opts{"./.ber", "s2", False{}, False{}, False{}}, "") == "s2" : String}

# two keys join with one space.
law render_key_list_two:
  {Render.render_key_list(Con{LogicalKey.Make{"a", "r1"}, Con{LogicalKey.Make{"a", "r2"}, Nil{}}}) == "a/r1 a/r2" : String}

# no keys render empty.
law render_key_list_empty:
  {Render.render_key_list(Nil{}) == "" : String}
