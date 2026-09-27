import Base
import ./src/Args.bend as Args

# CLI laws land here, one family per task (Args, Input, Render).
# Empty shell so the gate compiles before any law exists.

# Args family: concrete parse instances, each computes to its Command.
law parse_record_get:
  {Args.parse_command(Con{"record", Con{"get", Con{"--ns", Con{"ledger", Con{"--record", Con{"r1", Con{"--at", Con{"c1", Nil{}}}}}}}}}) == Args.RecordGet{"ledger", "r1", "c1"} : Args.Command}

law parse_record_put_text:
  {Args.parse_command(Con{"record", Con{"put", Con{"--ns", Con{"ledger", Con{"--record", Con{"r1", Con{"--text", Con{"v1", Nil{}}}}}}}}}) == Args.RecordPut{"", "ledger", "r1", Args.FromText{"v1"}} : Args.Command}

law parse_diff:
  {Args.parse_command(Con{"diff", Con{"--from", Con{"a", Con{"--to", Con{"b", Nil{}}}}}}) == Args.Diff{"a", "b", False{}} : Args.Command}

law parse_merge:
  {Args.parse_command(Con{"merge", Con{"--first", Con{"a", Con{"--second", Con{"b", Nil{}}}}}}) == Args.Merge{"a", "b", "union-disjoint"} : Args.Command}

law parse_commit_create:
  {Args.parse_command(Con{"commit", Con{"create", Nil{}}}) == Args.CommitCreate{"", Nil{}, Nil{}} : Args.Command}

law parse_empty_is_usage_error:
  {Args.parse_command(Nil{}) == Args.UsageError{"empty-argv"} : Args.Command}

law parse_unknown_is_usage_error:
  {Args.parse_command(Con{"frobnicate", Nil{}}) == Args.UsageError{"unknown-command"} : Args.Command}

law usage_text_nonempty:
  {String.eq(Args.usage_text("record"), "") == False{} : Bool}

law default_store_dir:
  {Args.store_dir_of(Args.default_opts()) == "./.ber" : String}

law colors_flag_on:
  {Args.colors_flag_of(Args.parse_opts(Con{"--colors", Nil{}})) == True{} : Bool}

law colors_flag_default_off:
  {Args.colors_flag_of(Args.parse_opts(Nil{})) == False{} : Bool}
