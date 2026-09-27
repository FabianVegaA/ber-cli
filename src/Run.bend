import Base
import ber-core-store@0.1.2.0/ber.bend as Ber
import ber-core-store@0.1.2.0/src/Store.bend as Store
import ber-core-store@0.1.2.0/src/History.bend as History
import ber-core-store@0.1.2.0/src/Value.bend as Value
import ber-core-store@0.1.2.0/src/Merging.bend as Merging
import ber-core-store@0.1.2.0/src/Comparison.bend as Comparison
import ber-core-store@0.1.2.0/src/LogicalKey.bend as LogicalKey
import ber-core-store@0.1.2.0/src/StateTree.bend as StateTree
import ber-core-store@0.1.2.0/src/Reading.bend as Reading
import ./Args.bend as Args
import ./Input.bend as Input
import ./Render.bend as Render

# Effects shell on the durable store (ber-core 0.1.2.0): every arm opens
# (mkdir -p, then WAL replay) and flushes exactly its journal, so separate
# CLI processes share state through <store>/wal.log. Pure reads never
# fsync (Store.flush_clean). No laws here (effects); verified by gate
# (this file must check) plus binary smoke. do-block locals are never
# matched on — pairs flow straight into defs matching on parameters
# (ber-core session_check pattern). Defs are leaf-first.

# --- durable runner (shared by all arms) ---

# Drops a mkdir outcome; best effort, failures surface at open time.
def sink_mkdir(mkdir_result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Unit:
  match mkdir_result:
    case Fail{error}:
      Unit{}
    case Done{triple}:
      Unit{}

# open_durable requires the directory to exist; Bend IO has no mkdir, so
# the POSIX one runs as a child process (best effort).
def ensure_store_dir(+store_dir: String) -> IO(Unit):
  do IO<Unit>:
    mkdir_result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mkdir", Con{"-p", Con{store_dir, Nil{}}}, "", (65536 : U32), (5000 : U32))
    return sink_mkdir(mkdir_result)

def open_cli_store(+store_dir: String) -> IO(Result<&1, &1, U32 & String, Store.Handle>):
  do IO<Result<&1, &1, U32 & String, Store.Handle>>:
    _dir : Unit <- ensure_store_dir(store_dir)
    Store.open_durable(store_dir)

def run_durable_done(a, -A: Kind(a), pair: Sigma<&1, &1, Store.Handle, _ => A>) -> IO(Result<&1, &1, U32 & String, A>):
  match pair:
    case (unused_store, answer):
      do IO<Result<&1, &1, U32 & String, A>>:
        return Done{answer}

def run_durable_flushed(a, -A: Kind(a), flushed: Result<&1, &1, U32 & String, Sigma<&1, &1, Store.Handle, _ => A>>) -> IO(Result<&1, &1, U32 & String, A>):
  match flushed:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, A>>:
        return Fail{error}
    case Done{pair}:
      run_durable_done(a, A, pair)

def run_durable_open(a, -A: Kind(a), op: Store.Op<a, A>, open_result: Result<&1, &1, U32 & String, Store.Handle>) -> IO(Result<&1, &1, U32 & String, A>):
  match open_result:
    case Fail{error}:
      do IO<Result<&1, &1, U32 & String, A>>:
        return Fail{error}
    case Done{store}:
      do IO<Result<&1, &1, U32 & String, A>>:
        flushed : Result<&1, &1, U32 & String, Sigma<&1, &1, Store.Handle, _ => A>> <- Store.run_op_durable(a, A, store, op)
        run_durable_flushed(a, A, flushed)

# Runs one op chain durably: mkdir, WAL replay, run, flush. Failures read
# as Fail and map to IoError at each arm.
def run_durable(a, -A: Kind(a), +store_dir: String, op: Store.Op<a, A>) -> IO(Result<&1, &1, U32 & String, A>):
  do IO<Result<&1, &1, U32 & String, A>>:
    open_result : Result<&1, &1, U32 & String, Store.Handle> <- open_cli_store(store_dir)
    run_durable_open(a, A, op, open_result)

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

def finish_read_text_result(file: File, read_result: Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>) -> IO(Resolved):
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

def finish_read_json_result(file: File, read_result: Result<&1, &1, Sigma<&1, &1, U32, _ => String>, String>) -> IO(Resolved):
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

def finish_read_blob_result(file: File, read_result: Result<&1, &1, Sigma<&1, &1, U32, _ => String>, List<&2, U32>>) -> IO(Resolved):
  match read_result:
    case Fail{error}:
      do IO<Resolved>:
        File.close(file)
        return NotFound{"read-failed"}
    case Done{byte_list}:
      do IO<Resolved>:
        File.close(file)
        return Got{Value.Blob{byte_list}}

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

# --- record arms ---

def outcome_of_read(+namespace_name: String, +record_id: String, +commit_id: String, read_value: Maybe<&2, Value.Value>) -> Render.Outcome:
  match read_value:
    case None{}:
      Render.Absent{namespace_name ++ "/" ++ record_id ++ " at " ++ commit_id}
    case Some{found_value}:
      Render.Ok{Ber.render_read_value(Some{found_value})}

def finish_get_answer(+namespace_name: String, +record_id: String, +commit_id: String, answer: Result<&1, &1, U32 & String, Maybe<&2, Value.Value>>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{read_value}:
      do IO<Render.Outcome>:
        return outcome_of_read(namespace_name, record_id, commit_id, read_value)

def run_get(+store_dir: String, +namespace_name: String, +record_id: String, +commit_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Maybe<&2, Value.Value>> <- run_durable(&2, Maybe<&2, Value.Value>, store_dir, Ber.read_value_at(namespace_name, record_id, commit_id))
    finish_get_answer(namespace_name, record_id, commit_id, answer)

def finish_put_answer(+namespace_name: String, +record_id: String, answer: Result<&1, &1, U32 & String, LogicalKey.LogicalKey>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{staged_key}:
      do IO<Render.Outcome>:
        return Render.Ok{"staged:" ++ LogicalKey.encode_logical_key(staged_key)}

def run_put(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +value: Value.Value) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, LogicalKey.LogicalKey> <- run_durable(&2, LogicalKey.LogicalKey, store_dir, Ber.put_record(session_id, namespace_name, record_id, value))
    finish_put_answer(namespace_name, record_id, answer)

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

def finish_rm_answer(+namespace_name: String, +record_id: String, answer: Result<&1, &1, U32 & String, LogicalKey.LogicalKey>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{staged_key}:
      do IO<Render.Outcome>:
        return Render.Ok{"staged-delete:" ++ LogicalKey.encode_logical_key(staged_key)}

def run_rm(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, LogicalKey.LogicalKey> <- run_durable(&2, LogicalKey.LogicalKey, store_dir, Ber.delete_record(session_id, namespace_name, record_id))
    finish_rm_answer(namespace_name, record_id, answer)

# --- commit arms ---

def finish_commit_answer(answer: Result<&1, &1, U32 & String, History.Commit>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{new_commit}:
      do IO<Render.Outcome>:
        return Render.Ok{"committed:" ++ History.commit_identifier_of(new_commit)}

# --meta deferred to v2 (splitting k=v needs string ops); parse stores Nil{}
# and the field stays for forward compatibility.
def run_commit_create(+store_dir: String, +session_id: String, +parents: List<&2, String>, +metas: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, History.Commit> <- run_durable(&2, History.Commit, store_dir, Ber.create_commit(session_id, parents, Nil{}))
    finish_commit_answer(answer)

def finish_show_tree_value(+commit_id: String, tree_maybe: Maybe<&2, StateTree.StateTreeNode>) -> Render.Outcome:
  match tree_maybe:
    case None{}:
      Render.Absent{"tree at " ++ commit_id}
    case Some{+tree_node}:
      Render.Ok{"tree:" ++ StateTree.tree_hash_of(tree_node) ++ " entries:" ++ Nat.show(List.length(&2, Reading.ChainEntry, StateTree.tree_entries(tree_node)))}

def finish_show_tree_answer(+commit_id: String, answer: Result<&1, &1, U32 & String, Maybe<&2, StateTree.StateTreeNode>>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{tree_maybe}:
      do IO<Render.Outcome>:
        return finish_show_tree_value(commit_id, tree_maybe)

def run_show_tree(+store_dir: String, +commit_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Maybe<&2, StateTree.StateTreeNode>> <- run_durable(&2, Maybe<&2, StateTree.StateTreeNode>, store_dir, Ber.read_tree_at(commit_id))
    finish_show_tree_answer(commit_id, answer)

# --- diff arm ---

def finish_diff_value(+compared: Comparison.CompareResult) -> Render.Outcome:
  Render.Ok{Ber.render_compare_counts(compared)}

def finish_diff_verbose(verbose: Bool, +compared: Comparison.CompareResult) -> Render.Outcome:
  match verbose:
    case True{}:
      Render.Ok{Ber.render_compare_counts(compared) ++ "\nadded:" ++ Render.render_key_list(Comparison.added_keys_of(compared)) ++ "\nremoved:" ++ Render.render_key_list(Comparison.removed_keys_of(compared)) ++ Render.render_modified_detail(Comparison.modified_entries_of(compared))}
    case False{}:
      finish_diff_value(compared)

def finish_diff_answer(verbose: Bool, answer: Result<&1, &1, U32 & String, Comparison.CompareResult>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{compared}:
      do IO<Render.Outcome>:
        return finish_diff_verbose(verbose, compared)

def run_diff(+store_dir: String, +first_id: String, +second_id: String, verbose: Bool) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Comparison.CompareResult> <- run_durable(&2, Comparison.CompareResult, store_dir, Ber.compare_commits(first_id, second_id))
    finish_diff_answer(verbose, answer)

# --- merge arms (merge flushes, then verify replays the flushed WAL) ---

def verify_merge_success_go(verified_ok: Bool, +resulting_commit: History.Commit) -> Render.Outcome:
  match verified_ok:
    case True{}:
      Render.Merged{History.commit_identifier_of(resulting_commit)}
    case False{}:
      Render.Unprovable{"verify-failed"}

def finish_verify_answer(+resulting_commit: History.Commit, answer: Result<&1, &1, U32 & String, Bool>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{verified_ok}:
      do IO<Render.Outcome>:
        return verify_merge_success_go(verified_ok, resulting_commit)

def verify_merge_durable(+store_dir: String, +resulting_commit: History.Commit, +certificate: Merging.MergeCertificate) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Bool> <- run_durable(&2, Bool, store_dir, Ber.verify_certificate(certificate))
    finish_verify_answer(resulting_commit, answer)

def finish_merge_done(+first_id: String, +second_id: String, +store_dir: String, merge_result: Merging.MergeResult) -> IO(Render.Outcome):
  match merge_result:
    case Merging.MergeSuccess{resulting_commit, certificate}:
      verify_merge_durable(store_dir, resulting_commit, certificate)
    case Merging.MergeConflict{+conflicting_keys}:
      do IO<Render.Outcome>:
        return Render.Conflict{Nat.show(List.length(&2, LogicalKey.LogicalKey, conflicting_keys)), Render.render_key_list(conflicting_keys), first_id, second_id}
    case Merging.MergeUnprovable{reason}:
      do IO<Render.Outcome>:
        return Render.Unprovable{reason}

def finish_merge_answer(+first_id: String, +second_id: String, +store_dir: String, answer: Result<&1, &1, U32 & String, Merging.MergeResult>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{merge_result}:
      finish_merge_done(first_id, second_id, store_dir, merge_result)

def run_merge(+store_dir: String, +first_id: String, +second_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Merging.MergeResult> <- run_durable(&2, Merging.MergeResult, store_dir, Ber.merge_commits(first_id, second_id, "union-disjoint"))
    finish_merge_answer(first_id, second_id, store_dir, answer)

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

def finish_cert_answer(answer: Result<&1, &1, U32 & String, Bool>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{cert_ok}:
      do IO<Render.Outcome>:
        return finish_cert_verify_bool(cert_ok)

def run_cert_verify(+store_dir: String, +first_id: String, +second_id: String, +base_id: String, +tree_hash: String, +strategy_name: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Bool> <- run_durable(&2, Bool, store_dir, Ber.verify_certificate(Merging.Make{first_id, second_id, base_id, tree_hash, strategy_name, Con{Merging.Check{"pairwise-compatibility", True{}}, Nil{}}}))
    finish_cert_answer(answer)

# --- write shortcut (commit_value) ---

def finish_write_answer(answer: Result<&1, &1, U32 & String, String>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{commit_id}:
      do IO<Render.Outcome>:
        return Render.Ok{"committed:" ++ commit_id}

def run_write(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +value: Value.Value, +parents: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, String> <- run_durable(&2, String, store_dir, Ber.commit_value(session_id, namespace_name, record_id, value, parents))
    finish_write_answer(answer)

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
