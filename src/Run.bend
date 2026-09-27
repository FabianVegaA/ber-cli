import Base
import ber-core-store@0.1.1.0/ber.bend as Ber
import ber-core-store@0.1.1.0/src/Store.bend as Store
import ber-core-store@0.1.1.0/src/History.bend as History
import ber-core-store@0.1.1.0/src/Value.bend as Value
import ber-core-store@0.1.1.0/src/Merging.bend as Merging
import ber-core-store@0.1.1.0/src/Comparison.bend as Comparison
import ber-core-store@0.1.1.0/src/LogicalKey.bend as LogicalKey
import ber-core-store@0.1.1.0/src/StateTree.bend as StateTree
import ber-core-store@0.1.1.0/src/Reading.bend as Reading
import ./Args.bend as Args
import ./Input.bend as Input
import ./Render.bend as Render

# Effects shell: every arm opens the store, runs ONE Ber.* delegate chain,
# and maps the answer to a Render.Outcome. No laws here (effects); verified
# by gate (this file must check) plus binary smoke. do-block locals are
# never matched on — run_op pairs flow straight into defs matching on
# parameters (ber-core session_check pattern).

# --- value resolution (flags and files → Value) ---

# How a source resolved: a value, an unreadable payload, or missing bytes.
type Resolved is Data:
  Got{value: Value.Value}
  BadPayload{what: String}
  NotFound{what: String}

def resolve_nonfile_go(+resolved: Maybe<&2, Value.Value>) -> Resolved:
  match resolved:
    case None{}:
      BadPayload{"unreadable-value"}
    case Some{value}:
      Got{value}

def resolve_nonfile(+source: Args.ValueSource) -> Resolved:
  resolve_nonfile_go(Input.source_to_value(source))


def finish_read_text_result(file: File, read_result: Result<&1, &1, U32 & String, String>) -> IO(Resolved):
  match read_result:
    case Fail{error}:
      do IO<Resolved>:
        File.close(file)
        return NotFound{"read-failed"}
    case Done{content}:
      do IO<Resolved>:
        File.close(file)
        return Got{Value.Text{content}}

def finish_read_text_content(read_pair: Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>>) -> IO(Resolved):
  match read_pair:
    case (file, read_result):
      finish_read_text_result(file, read_result)

def finish_read_text_open(+file_path: String, open_result: Result<&1, &1, U32 & String, File>) -> IO(Resolved):
  match open_result:
    case Fail{error}:
      do IO<Resolved>:
        return NotFound{file_path}
    case Done{file}:
      do IO<Resolved>:
        read_pair : Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>> <- File.read(file, (1048576 : U32))
        finish_read_text_content(read_pair)

def read_file_text(+file_path: String) -> IO(Resolved):
  do IO<Resolved>:
    open_result : Result<&1, &1, U32 & String, File> <- File.open(file_path, "r")
    finish_read_text_open(file_path, open_result)

def finish_read_json_result(file: File, read_result: Result<&1, &1, U32 & String, String>) -> IO(Resolved):
  match read_result:
    case Fail{error}:
      do IO<Resolved>:
        File.close(file)
        return NotFound{"read-failed"}
    case Done{content}:
      do IO<Resolved>:
        File.close(file)
        return resolve_nonfile(Args.FromJson{content})

def finish_read_json_content(read_pair: Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>>) -> IO(Resolved):
  match read_pair:
    case (file, read_result):
      finish_read_json_result(file, read_result)

def finish_read_json_open(+file_path: String, open_result: Result<&1, &1, U32 & String, File>) -> IO(Resolved):
  match open_result:
    case Fail{error}:
      do IO<Resolved>:
        return NotFound{file_path}
    case Done{file}:
      do IO<Resolved>:
        read_pair : Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>> <- File.read(file, (1048576 : U32))
        finish_read_json_content(read_pair)

def read_file_json(+file_path: String) -> IO(Resolved):
  do IO<Resolved>:
    open_result : Result<&1, &1, U32 & String, File> <- File.open(file_path, "r")
    finish_read_json_open(file_path, open_result)

def finish_read_blob_result(file: File, read_result: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Resolved):
  match read_result:
    case Fail{error}:
      do IO<Resolved>:
        File.close(file)
        return NotFound{"read-failed"}
    case Done{byte_list}:
      do IO<Resolved>:
        File.close(file)
        return Got{Value.Blob{byte_list}}

# --- record arms ---

def finish_read_blob_content(read_pair: Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, List<&2, U32>>>) -> IO(Resolved):
  match read_pair:
    case (file, read_result):
      finish_read_blob_result(file, read_result)

def finish_read_blob_open(+file_path: String, open_result: Result<&1, &1, U32 & String, File>) -> IO(Resolved):
  match open_result:
    case Fail{error}:
      do IO<Resolved>:
        return NotFound{file_path}
    case Done{file}:
      do IO<Resolved>:
        read_pair : Sigma<&1, &1, File, _ => Result<&1, &1, Sigma<&1, &1, U32, _ => String>, List<&2, U32>>> <- File.read_bytes(file, (1048576 : U32))
        finish_read_blob_content(read_pair)

def read_file_blob(+file_path: String) -> IO(Resolved):
  do IO<Resolved>:
    open_result : Result<&1, &1, U32 & String, File> <- File.open(file_path, "r")
    finish_read_blob_open(file_path, open_result)

def read_file_value_text_or(is_text: Bool, +file_path: String) -> IO(Resolved):
  match is_text:
    case True{}:
      read_file_text(file_path)
    case False{}:
      do IO<Resolved>:
        return BadPayload{"bad-kind: want text|json|blob"}

def read_file_value_textual(is_json: Bool, is_text: Bool, +file_path: String) -> IO(Resolved):
  match is_json:
    case True{}:
      read_file_json(file_path)
    case False{}:
      read_file_value_text_or(is_text, file_path)

def read_file_value_kind(is_blob: Bool, is_json: Bool, is_text: Bool, +file_path: String) -> IO(Resolved):
  match is_blob:
    case True{}:
      read_file_blob(file_path)
    case False{}:
      read_file_value_textual(is_json, is_text, file_path)

def read_file_value(+file_path: String, +kind_name: String) -> IO(Resolved):
  read_file_value_kind(String.eq(kind_name, "blob"), String.eq(kind_name, "json"), String.eq(kind_name, "text"), file_path)


def resolve_source(+source: Args.ValueSource) -> IO(Resolved):
  match source:
    case Args.FromText{content}:
      do IO<Resolved>:
        return Got{Value.Text{content}}
    case Args.FromJson{json_text}:
      do IO<Resolved>:
        return resolve_nonfile(Args.FromJson{json_text})
    case Args.FromBlobHex{hex_text}:
      do IO<Resolved>:
        return resolve_nonfile(Args.FromBlobHex{hex_text})
    case Args.FromFile{file_path, kind_name}:
      read_file_value(file_path, kind_name)

def outcome_of_read(+namespace_name: String, +record_id: String, +commit_id: String, read_value: Maybe<&2, Value.Value>) -> Render.Outcome:
  match read_value:
    case None{}:
      Render.Absent{namespace_name ++ "/" ++ record_id ++ " at " ++ commit_id}
    case Some{found_value}:
      Render.Ok{Ber.render_read_value(Some{found_value})}

def finish_get(+namespace_name: String, +record_id: String, +commit_id: String, run_pair: Sigma<&1, &1, Store.Handle, _ => Maybe<&2, Value.Value>>) -> Render.Outcome:
  match run_pair:
    case (unused_store, read_value):
      outcome_of_read(namespace_name, record_id, commit_id, read_value)

def run_get(+store_dir: String, +namespace_name: String, +record_id: String, +commit_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_get(namespace_name, record_id, commit_id, Store.run_op(&2, Maybe<&2, Value.Value>, Store.open_store(store_dir), Ber.read_value_at(namespace_name, record_id, commit_id)))

def finish_put(+namespace_name: String, +record_id: String, run_pair: Sigma<&1, &1, Store.Handle, _ => LogicalKey.LogicalKey>) -> Render.Outcome:
  match run_pair:
    case (unused_store, staged_key):
      Render.Ok{"staged:" ++ LogicalKey.encode_logical_key(staged_key)}

def run_put(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +value: Value.Value) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_put(namespace_name, record_id, Store.run_op(&2, LogicalKey.LogicalKey, Store.open_store(store_dir), Ber.put_record(session_id, namespace_name, record_id, value)))

def run_put_resolved(+resolved: Resolved, +store_dir: String, +session_id: String, +namespace_name: String, +record_id: String) -> IO(Render.Outcome):
  match resolved:
    case Got{value}:
      run_put(store_dir, session_id, namespace_name, record_id, value)
    case BadPayload{what}:
      do IO<Render.Outcome>:
        return Render.UsageError{what}
    case NotFound{what}:
      do IO<Render.Outcome>:
        return Render.IoError{what}

def run_put_source(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +source: Args.ValueSource) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    resolved : Resolved <- resolve_source(source)
    run_put_resolved(resolved, store_dir, session_id, namespace_name, record_id)

def finish_rm(+namespace_name: String, +record_id: String, run_pair: Sigma<&1, &1, Store.Handle, _ => LogicalKey.LogicalKey>) -> Render.Outcome:
  match run_pair:
    case (unused_store, staged_key):
      Render.Ok{"staged-delete:" ++ LogicalKey.encode_logical_key(staged_key)}

def run_rm(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_rm(namespace_name, record_id, Store.run_op(&2, LogicalKey.LogicalKey, Store.open_store(store_dir), Ber.delete_record(session_id, namespace_name, record_id)))

# --- commit arms ---

def finish_commit_create(run_pair: Sigma<&1, &1, Store.Handle, _ => History.Commit>) -> Render.Outcome:
  match run_pair:
    case (unused_store, new_commit):
      Render.Ok{"committed:" ++ History.commit_identifier_of(new_commit)}

# --meta deferred to v2 (splitting k=v needs string ops); parse stores Nil{}
# and the field stays for forward compatibility.
def run_commit_create(+store_dir: String, +session_id: String, +parents: List<&2, String>, +metas: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_commit_create(Store.run_op(&2, History.Commit, Store.open_store(store_dir), Ber.create_commit(session_id, parents, Nil{})))

def finish_show_tree_value(+commit_id: String, tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Render.Outcome:
  match tree_maybe:
    case None{}:
      Render.Absent{"tree at " ++ commit_id}
    case Some{+tree_node}:
      Render.Ok{"tree:" ++ StateTree.tree_hash_of(tree_node) ++ " entries:" ++ Nat.show(List.length(&2, Reading.ChainEntry, StateTree.tree_entries(tree_node)))}

def finish_show_tree(+commit_id: String, run_pair: Sigma<&1, &1, Store.Handle, _ => Maybe<&2, StateTree.StateTreeNode>>) -> Render.Outcome:
  match run_pair:
    case (unused_store, tree_maybe):
      finish_show_tree_value(commit_id, tree_maybe)

def run_show_tree(+store_dir: String, +commit_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_show_tree(commit_id, Store.run_op(&2, Maybe<&2, StateTree.StateTreeNode>, Store.open_store(store_dir), Ber.read_tree_at(commit_id)))

# --- diff arm ---

def finish_diff_value(+compared: Comparison.CompareResult) -> Render.Outcome:
  Render.Ok{Ber.render_compare_counts(compared)}

def finish_diff_verbose(verbose: Bool, +compared: Comparison.CompareResult) -> Render.Outcome:
  match verbose:
    case True{}:
      Render.Ok{Ber.render_compare_counts(compared) ++ "\nadded:" ++ Render.render_key_list(Comparison.added_keys_of(compared)) ++ "\nremoved:" ++ Render.render_key_list(Comparison.removed_keys_of(compared)) ++ Render.render_modified_detail(Comparison.modified_entries_of(compared))}
    case False{}:
      finish_diff_value(compared)

def finish_diff(verbose: Bool, run_pair: Sigma<&1, &1, Store.Handle, _ => Comparison.CompareResult>) -> Render.Outcome:
  match run_pair:
    case (unused_store, compared):
      finish_diff_verbose(verbose, compared)

def run_diff(+store_dir: String, +first_id: String, +second_id: String, verbose: Bool) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_diff(verbose, Store.run_op(&2, Comparison.CompareResult, Store.open_store(store_dir), Ber.compare_commits(first_id, second_id)))

# --- merge arms ---

def verify_merge_success_go(verified_ok: Bool, +resulting_commit: History.Commit) -> Render.Outcome:
  match verified_ok:
    case True{}:
      Render.Merged{History.commit_identifier_of(resulting_commit)}
    case False{}:
      Render.Unprovable{"verify-failed"}

def verify_merge_success(+resulting_commit: History.Commit, +certificate: Merging.MergeCertificate) -> Store.Op<&2, Render.Outcome>:
  do Store.Op<&2, Render.Outcome>:
    verified_ok : Bool <- Ber.verify_certificate(certificate)
    return verify_merge_success_go(verified_ok, resulting_commit)

def outcome_of_merge_result(+first_id: String, +second_id: String, merge_result: Merging.MergeResult) -> Store.Op<&2, Render.Outcome>:
  match merge_result:
    case Merging.MergeSuccess{resulting_commit, certificate}:
      verify_merge_success(resulting_commit, certificate)
    case Merging.MergeConflict{+conflicting_keys}:
      Store.Op.pure(&2, Render.Outcome, Render.Conflict{Nat.show(List.length(&2, LogicalKey.LogicalKey, conflicting_keys)), Render.render_key_list(conflicting_keys), first_id, second_id})
    case Merging.MergeUnprovable{reason}:
      Store.Op.pure(&2, Render.Outcome, Render.Unprovable{reason})

def finish_merge_second(second_pair: Sigma<&1, &1, Store.Handle, _ => Render.Outcome>) -> Render.Outcome:
  match second_pair:
    case (unused_store, outcome):
      outcome

def finish_merge(+first_id: String, +second_id: String, run_pair: Sigma<&1, &1, Store.Handle, _ => Merging.MergeResult>) -> Render.Outcome:
  match run_pair:
    case (store_next, merge_result):
      finish_merge_second(Store.run_op(&2, Render.Outcome, store_next, outcome_of_merge_result(first_id, second_id, merge_result)))

def run_merge(+store_dir: String, +first_id: String, +second_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_merge(first_id, second_id, Store.run_op(&2, Merging.MergeResult, Store.open_store(store_dir), Ber.merge_commits(first_id, second_id, "union-disjoint")))

def run_merge_strategy_go(strategy_ok: Bool, +store_dir: String, +first_id: String, +second_id: String) -> IO(Render.Outcome):
  match strategy_ok:
    case True{}:
      run_merge(store_dir, first_id, second_id)
    case False{}:
      do IO<Render.Outcome>:
        return Render.Unprovable{"unknown-strategy"}

def run_merge_strategy(+store_dir: String, +first_id: String, +second_id: String, +strategy_name: String) -> IO(Render.Outcome):
  run_merge_strategy_go(String.eq(strategy_name, "union-disjoint"), store_dir, first_id, second_id)

# --- certificate arm (mirrors exactly what ber merge issues) ---

def finish_cert_verify_bool(cert_ok: Bool) -> Render.Outcome:
  match cert_ok:
    case True{}:
      Render.Ok{"certificate-valid"}
    case False{}:
      Render.Unprovable{"verify-failed"}

def finish_cert_verify(run_pair: Sigma<&1, &1, Store.Handle, _ => Bool>) -> Render.Outcome:
  match run_pair:
    case (unused_store, cert_ok):
      finish_cert_verify_bool(cert_ok)

def run_cert_verify(+store_dir: String, +first_id: String, +second_id: String, +base_id: String, +tree_hash: String, +strategy_name: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_cert_verify(Store.run_op(&2, Bool, Store.open_store(store_dir), Ber.verify_certificate(Merging.Make{first_id, second_id, base_id, tree_hash, strategy_name, Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}})))

# --- write shortcut (commit_value) ---

def finish_write(run_pair: Sigma<&1, &1, Store.Handle, _ => String>) -> Render.Outcome:
  match run_pair:
    case (unused_store, commit_id):
      Render.Ok{"committed:" ++ commit_id}

def run_write(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +value: Value.Value, +parents: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    return finish_write(Store.run_op(&2, String, Store.open_store(store_dir), Ber.commit_value(session_id, namespace_name, record_id, value, parents)))

def run_write_resolved(+resolved: Resolved, +store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +parents: List<&2, String>) -> IO(Render.Outcome):
  match resolved:
    case Got{value}:
      run_write(store_dir, session_id, namespace_name, record_id, value, parents)
    case BadPayload{what}:
      do IO<Render.Outcome>:
        return Render.UsageError{what}
    case NotFound{what}:
      do IO<Render.Outcome>:
        return Render.IoError{what}

def run_write_source(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +source: Args.ValueSource, +parents: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    resolved : Resolved <- resolve_source(source)
    run_write_resolved(resolved, store_dir, session_id, namespace_name, record_id, parents)

# --- top dispatch ---

def execute(+opts: Args.GlobalOpts, +cmd: Args.Command) -> IO(Render.Outcome):
  match cmd:
    case Args.RecordPut{session_id, namespace_name, record_id, source}:
      run_put_source(Args.store_dir_of(opts), Args.session_or(opts, session_id), namespace_name, record_id, source)
    case Args.RecordRm{session_id, namespace_name, record_id}:
      run_rm(Args.store_dir_of(opts), Args.session_or(opts, session_id), namespace_name, record_id)
    case Args.RecordGet{namespace_name, record_id, commit_id}:
      run_get(Args.store_dir_of(opts), namespace_name, record_id, commit_id)
    case Args.CommitCreate{session_id, parents, metas}:
      run_commit_create(Args.store_dir_of(opts), Args.session_or(opts, session_id), parents, metas)
    case Args.CommitShowTree{commit_id}:
      run_show_tree(Args.store_dir_of(opts), commit_id)
    case Args.Diff{first_id, second_id, verbose}:
      run_diff(Args.store_dir_of(opts), first_id, second_id, verbose)
    case Args.Merge{first_id, second_id, strategy_name}:
      run_merge_strategy(Args.store_dir_of(opts), first_id, second_id, strategy_name)
    case Args.CertVerify{first_id, second_id, base_id, tree_hash, strategy_name, laws}:
      run_cert_verify(Args.store_dir_of(opts), first_id, second_id, base_id, tree_hash, strategy_name)
    case Args.Write{session_id, namespace_name, record_id, source, parents}:
      run_write_source(Args.store_dir_of(opts), Args.session_or(opts, session_id), namespace_name, record_id, source, parents)
    case Args.Compare{first_id, second_id}:
      run_diff(Args.store_dir_of(opts), first_id, second_id, False{})
    case Args.MergeVerify{first_id, second_id}:
      run_merge(Args.store_dir_of(opts), first_id, second_id)
    case Args.Help{topic}:
      do IO<Render.Outcome>:
        return Render.Ok{Args.usage_text(topic)}
    case Args.UsageError{message}:
      do IO<Render.Outcome>:
        return Render.UsageError{message}

def finish_argv_err(+out_text: String, +outcome: Render.Outcome) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(out_text)
    IO.die(Unit, Render.exit_code_of(outcome), out_text)

def finish_argv_go(+out_text: String, +outcome: Render.Outcome, went_ok: Bool) -> IO(Unit):
  match went_ok:
    case True{}:
      IO.print(out_text)
    case False{}:
      finish_argv_err(out_text, outcome)

def finish_argv(+opts: Args.GlobalOpts, +outcome: Render.Outcome) -> IO(Unit):
  finish_argv_go(Render.render_outcome(outcome, Args.json_flag_of(opts), Render.opts_of(Args.colors_flag_of(opts), Args.verbose_flag_of(opts))), outcome, Render.succeeded(outcome))

def run_argv_exec(+opts: Args.GlobalOpts, +cmd: Args.Command) -> IO(Unit):
  do IO<Unit>:
    outcome : Render.Outcome <- execute(opts, cmd)
    finish_argv(opts, outcome)

def run_argv_go(+both: Sigma<&2, &2, Args.GlobalOpts, _ => Args.Command>) -> IO(Unit):
  match both:
    case (opts, cmd):
      run_argv_exec(opts, cmd)

def run_argv(argv: List<String>) -> IO(Unit):
  run_argv_go(Args.parse_both(argv))
