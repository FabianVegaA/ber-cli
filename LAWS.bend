import Base
import ./src/Args.bend as Args
import ./src/Key.bend as NsKey
import ./src/Run.bend as Run
import ./src/Input.bend as Input
import ber-core-store@0.1.2.0/src/Value.bend as Value
import ./src/Render.bend as Render
import ber-core-store@0.1.2.0/src/LogicalKey.bend as LogicalKey

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
  {Args.session_or(Args.Opts{"./.ber", "s2", False{}, False{}, False{}, False{}}, "s1") == "s1" : String}

# empty command session falls back to global.
law session_opts_fallback:
  {Args.session_or(Args.Opts{"./.ber", "s2", False{}, False{}, False{}, False{}}, "") == "s2" : String}

# two keys join with one space.
law render_key_list_two:
  {Render.render_key_list(Con{LogicalKey.Make{"a", "r1"}, Con{LogicalKey.Make{"a", "r2"}, Nil{}}}) == "a/r1 a/r2" : String}

# no keys render empty.
law render_key_list_empty:
  {Render.render_key_list(Nil{}) == "" : String}

# Colored merge wraps the verdict in green.
law colored_merge_wraps:
  {Render.render_human(Render.Merged{"c1"}, Render.Human{True{}, False{}}) == "[32mmerged:[0mc1" : String}

# commit create threads a single parent.
law parse_commit_create_parent:
  {Args.parse_command(Con{"commit", Con{"create", Con{"--parent", Con{"p1", Nil{}}}}}) == Args.CommitCreate{"", Con{"p1", Nil{}}, Nil{}} : Args.Command}

# --help flag is an alias for help.
law parse_help_flag_alias:
  {Args.parse_command(Con{"--help", Nil{}}) == Args.Help{""} : Args.Command}

# Key family: split on first "/" only; ":" never separates.
law split_key_slash:
  {NsKey.split_key("shop/limits") == Some{("shop", "limits")} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_colon_is_none:
  {NsKey.split_key("shop:limits") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_inner_colon_is_none:
  {NsKey.split_key("shop/li:mits") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_no_sep_is_none:
  {NsKey.split_key("shop") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_empty_seg_is_none:
  {NsKey.split_key("/limits") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

law split_key_multi_slash_is_none:
  {NsKey.split_key("a/b/c") == None{} : Maybe<&2, Sigma<&2, &2, String, _ => String>>}

# Friendly shortcuts: KEY form, flags fallback, init, no-colors, help topics.
law parse_set_key_slash:
  {Args.parse_command(Con{"set", Con{"shop/limits", Con{"--text", Con{"v1", Con{"--session", Con{"ana", Nil{}}}}}}}) == Args.Set{"ana", "shop", "limits", Args.FromText{"v1"}, Nil{}} : Args.Command}

law parse_set_colon_is_usage:
  {Args.parse_command(Con{"set", Con{"shop:limits", Con{"--text", Con{"v1", Nil{}}}}}) == Args.UsageError{"set-needs-key-ns/record"} : Args.Command}

law parse_set_flags_fallback:
  {Args.parse_command(Con{"set", Con{"--ns", Con{"shop", Con{"--record", Con{"limits", Con{"--text", Con{"v1", Nil{}}}}}}}}) == Args.Set{"", "shop", "limits", Args.FromText{"v1"}, Nil{}} : Args.Command}

law parse_get_key_slash:
  {Args.parse_command(Con{"get", Con{"shop/limits", Nil{}}}) == Args.Get{"shop", "limits", ""} : Args.Command}

law parse_get_flags_fallback:
  {Args.parse_command(Con{"get", Con{"--ns", Con{"shop", Con{"--record", Con{"limits", Con{"--at", Con{"c1", Nil{}}}}}}}}) == Args.Get{"shop", "limits", "c1"} : Args.Command}

law parse_init:
  {Args.parse_command(Con{"init", Nil{}}) == Args.Init{} : Args.Command}

law parse_log:
  {Args.parse_command(Con{"log", Nil{}}) == Args.Log{""} : Args.Command}

law parse_status:
  {Args.parse_command(Con{"status", Nil{}}) == Args.Status{""} : Args.Command}

law parse_no_colors_flag:
  {Args.no_colors_flag_of(Args.parse_opts(Con{"--no-colors", Nil{}})) == True{} : Bool}

law usage_set_nonempty:
  {String.eq(Args.usage_text("set"), "") == False{} : Bool}

law parse_help_topic_routes:
  {Args.parse_command(Con{"help", Con{"set", Nil{}}}) == Args.Help{"set"} : Args.Command}

law parse_version_word:
  {Args.parse_command(Con{"version", Nil{}}) == Args.Version{} : Args.Command}

law parse_version_flag:
  {Args.parse_command(Con{"--version", Nil{}}) == Args.Version{} : Args.Command}

law parse_version_short:
  {Args.parse_command(Con{"-V", Nil{}}) == Args.Version{} : Args.Command}

law version_text_pinned:
  {Render.version_text() == "ber-cli 0.1.0.0" : String}

# Friendly render: welcome header, table diff, tree view.
law welcome_plain_has_next_step:
  {String.eq(Render.welcome_header(Render.plain_opts()), "") == False{} : Bool}

law welcome_fallback_has_no_logo:
  {String.eq(Render.welcome_fallback(), "") == False{} : Bool}

law welcome_fallback_mentions_try:
  {String.contains(Render.welcome_fallback(), "ber set") == True{} : Bool}

law table_diff_header:
  {Render.render_table_diff("a3f9c2d", "c71b00e", Con{LogicalKey.Make{"a", "b"}, Nil{}}, Nil{}, Nil{}) == "≡ diff a3f9c2d..c71b00e  (+1 ~0 -0)\n  + a/b" : String}

law tree_renders_entries:
  {Render.render_tree("h", Con{LogicalKey.Make{"a", "limits"}, Nil{}}) == "tree:h (1 entries)\n├─ a/limits" : String}

law status_counts_keys:
  {Render.render_status("ana", Con{LogicalKey.Make{"a", "r1"}, Nil{}}) == "staged (session ana): 1 keys\n├─ a/r1" : String}

# Color auto-off: --colors opts in, vetoes win, default stays plain.
law resolve_color_flag_on:
  {Run.resolve_color(True{}, False{}, False{}, False{}, False{}) == True{} : Bool}

law resolve_color_flag_off:
  {Run.resolve_color(False{}, False{}, False{}, False{}, False{}) == False{} : Bool}

law resolve_color_veto_no_color:
  {Run.resolve_color(True{}, False{}, False{}, False{}, True{}) == False{} : Bool}

law resolve_color_veto_json:
  {Run.resolve_color(True{}, False{}, True{}, False{}, False{}) == False{} : Bool}
