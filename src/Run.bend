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
import ber-core-store@0.1.2.0/src/Staging.bend as Staging
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

# Environment signals for display: Bend has no TTY primitive, so color is
# opt-in (--colors) with automatic vetoes (NO_COLOR, TERM=dumb, --no-colors,
# --json). The rich logo shows unless the terminal is dumb, LANG=C or --json.
type EnvFlags is Data:
  Env{term_dumb: Bool, no_color_env: Bool, lang_c: Bool}

def decide_color_off_env(no_color_env: Bool) -> Bool:
  match no_color_env:
    case True{}:
      True{}
    case False{}:
      False{}

def decide_color_off_term(term_dumb: Bool, no_color_env: Bool) -> Bool:
  match term_dumb:
    case True{}:
      True{}
    case False{}:
      decide_color_off_env(no_color_env)

def decide_color_off_json(json_out: Bool, term_dumb: Bool, no_color_env: Bool) -> Bool:
  match json_out:
    case True{}:
      True{}
    case False{}:
      decide_color_off_term(term_dumb, no_color_env)

def decide_color_off(no_colors: Bool, json_out: Bool, term_dumb: Bool, no_color_env: Bool) -> Bool:
  match no_colors:
    case True{}:
      True{}
    case False{}:
      decide_color_off_json(json_out, term_dumb, no_color_env)

def decide_color_veto(is_off: Bool) -> Bool:
  match is_off:
    case True{}:
      False{}
    case False{}:
      True{}

def decide_color_on(colors_flag: Bool, is_off: Bool) -> Bool:
  match colors_flag:
    case True{}:
      decide_color_veto(is_off)
    case False{}:
      False{}

def resolve_color(colors_flag: Bool, no_colors: Bool, json_out: Bool, term_dumb: Bool, no_color_env: Bool) -> Bool:
  decide_color_on(colors_flag, decide_color_off(no_colors, json_out, term_dumb, no_color_env))

def color_of(+opts: Args.GlobalOpts, +env: EnvFlags) -> Bool:
  match env:
    case Env{term_dumb, no_color_env, lang_c}:
      resolve_color(Args.colors_flag_of(opts), Args.no_colors_flag_of(opts), Args.json_flag_of(opts), term_dumb, no_color_env)

def rich_json(json_out: Bool) -> Bool:
  match json_out:
    case True{}:
      False{}
    case False{}:
      True{}

def rich_lang(lang_c: Bool, json_out: Bool) -> Bool:
  match lang_c:
    case True{}:
      False{}
    case False{}:
      rich_json(json_out)

def rich_go(term_dumb: Bool, lang_c: Bool, json_out: Bool) -> Bool:
  match term_dumb:
    case True{}:
      False{}
    case False{}:
      rich_lang(lang_c, json_out)

def rich_of(+opts: Args.GlobalOpts, +env: EnvFlags) -> Bool:
  match env:
    case Env{term_dumb, no_color_env, lang_c}:
      rich_go(term_dumb, lang_c, Args.json_flag_of(opts))

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

# --- friendly arms: LOG journal, get-head, log, status, init ---
# ber-core has no HEAD/latest pointer and Bend forbids data-dependent IO
# loops, so the CLI keeps a best-effort append-only <store>/LOG journal
# (one commit id per line). Every commit-creating arm appends; head is the
# last line, log renders the last N lines. No storage walk needed.
def log_path(+store_dir: String) -> String:
  store_dir ++ "/LOG"
def log_appended(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (file, res):
      File.close(file)
def log_append_file(+commit_id: String, file: File) -> IO(Unit):
  do IO<Unit>:
    pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, commit_id ++ "\n")
    log_appended(pair)
def log_append_opened(+commit_id: String, open_result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match open_result:
    case Fail{error}:
      do IO<Unit>:
        return Unit{}
    case Done{file}:
      log_append_file(commit_id, file)
def log_append(+store_dir: String, +commit_id: String) -> IO(Unit):
  do IO<Unit>:
    open_result : Result<&1, &1, U32 & String, File> <- File.open(log_path(store_dir), "a")
    log_append_opened(commit_id, open_result)
def bytes_to_chars_go(+bytes: List<&2, U32>, +acc: List<&2, Char>) -> List<&2, Char>:
  match bytes:
    case Nil{}:
      List.reverse(&2, Char, acc)
    case Con{head_byte, rest_bytes}:
      bytes_to_chars_go(rest_bytes, Con{Char.from_u32(head_byte), acc})
def bytes_to_chars(+bytes: List<&2, U32>) -> List<&2, Char>:
  bytes_to_chars_go(bytes, Nil{})
def log_tail_result(file: File, read_result: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(String):
  match read_result:
    case Fail{error}:
      do IO<String>:
        File.close(file)
        return ""
    case Done{byte_list}:
      do IO<String>:
        File.close(file)
        return String.from_list(bytes_to_chars(byte_list))
def log_tail_content(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(String):
  match pair:
    case (file, read_result):
      log_tail_result(file, read_result)
def log_tail_bytes(file: File, offset: U32) -> IO(String):
  do IO<String>:
    pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, offset, (16384 : U32))
    log_tail_content(pair)
def log_tail_offset(file: File, is_big: Bool, size: U32) -> IO(String):
  match is_big:
    case True{}:
      log_tail_bytes(file, U32.sub(size, (16384 : U32)))
    case False{}:
      log_tail_bytes(file, (0 : U32))
def log_tail_read(file: File, size_result: Result<&1, &1, U32 & String, U32>) -> IO(String):
  match size_result:
    case Fail{error}:
      do IO<String>:
        File.close(file)
        return ""
    case Done{+size}:
      log_tail_offset(file, U32.is_ge(size, (16384 : U32)), size)
def log_tail_sized(pair: File & Result<&1, &1, U32 & String, U32>) -> IO(String):
  match pair:
    case (file, size_result):
      log_tail_read(file, size_result)
def log_tail_size(file: File) -> IO(String):
  do IO<String>:
    pair : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
    log_tail_sized(pair)
def log_tail_open(open_result: Result<&1, &1, U32 & String, File>) -> IO(String):
  match open_result:
    case Fail{error}:
      do IO<String>:
        return ""
    case Done{file}:
      log_tail_size(file)
def read_log_tail(+store_dir: String) -> IO(String):
  do IO<String>:
    open_result : Result<&1, &1, U32 & String, File> <- File.open(log_path(store_dir), "r")
    log_tail_open(open_result)
def clean_lines_put(is_empty: Bool, +head_line: String, +cleaned_rest: List<&2, String>) -> List<&2, String>:
  match is_empty:
    case True{}:
      cleaned_rest
    case False{}:
      Con{head_line, cleaned_rest}
def clean_lines(+lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}:
      Nil{}
    case Con{head_line, rest_lines}:
      clean_lines_put(String.is_empty(head_line), head_line, clean_lines(rest_lines))
def take_last(+lines: List<&2, String>, +n: Nat) -> List<&2, String>:
  List.reverse(&2, String, List.take(&2, String, List.reverse(&2, String, lines), n))
def log_last(+lines: List<&2, String>) -> Maybe<&2, String>:
  List.head(&2, String, List.reverse(&2, String, lines))
def short_of(+commit_id: String) -> String:
  String.take(commit_id, 7n)
def short_lines_go(+lines: List<&2, String>, +acc: String) -> String:
  match lines:
    case Nil{}:
      acc
    case Con{head_line, rest_lines}:
      short_lines_go(rest_lines, acc ++ short_of(head_line) ++ "\n")
def short_lines(+lines: List<&2, String>) -> String:
  short_lines_go(lines, "")
def get_head_maybe(+store_dir: String, +namespace_name: String, +record_id: String, +head: Maybe<&2, String>) -> IO(Render.Outcome):
  match head:
    case None{}:
      do IO<Render.Outcome>:
        return Render.UsageError{"get-needs-at-no-head"}
    case Some{head_id}:
      run_get(store_dir, namespace_name, record_id, head_id)
def run_get_head(+store_dir: String, +namespace_name: String, +record_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    tail : String <- read_log_tail(store_dir)
    get_head_maybe(store_dir, namespace_name, record_id, log_last(clean_lines(String.lines(tail))))
def run_get_head_empty(is_empty: Bool, +store_dir: String, +namespace_name: String, +record_id: String, +commit_id: String) -> IO(Render.Outcome):
  match is_empty:
    case True{}:
      run_get_head(store_dir, namespace_name, record_id)
    case False{}:
      run_get(store_dir, namespace_name, record_id, commit_id)
def run_get_maybe_head(+store_dir: String, +namespace_name: String, +record_id: String, +commit_id: String) -> IO(Render.Outcome):
  run_get_head_empty(String.eq(commit_id, ""), store_dir, namespace_name, record_id, commit_id)
def run_log_list(+lines: List<&2, String>) -> IO(Render.Outcome):
  match lines:
    case Nil{}:
      do IO<Render.Outcome>:
        return Render.UsageError{"log-empty-no-commits"}
    case Con{head_line, rest_lines}:
      do IO<Render.Outcome>:
        return Render.Ok{short_lines(lines)}
def run_log_tail_text(+tail: String, +limit: Nat) -> IO(Render.Outcome):
  run_log_list(take_last(clean_lines(String.lines(tail)), limit))
def run_log_head(+store_dir: String, +limit: Nat) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    tail : String <- read_log_tail(store_dir)
    run_log_tail_text(tail, limit)
def run_log_parsed(+parsed: Maybe<&2, Nat>, +store_dir: String) -> IO(Render.Outcome):
  match parsed:
    case None{}:
      do IO<Render.Outcome>:
        return Render.UsageError{"log-needs-numeric-limit"}
    case Some{limit}:
      run_log_head(store_dir, limit)
def run_log_empty(is_empty: Bool, +store_dir: String, +limit_text: String) -> IO(Render.Outcome):
  match is_empty:
    case True{}:
      run_log_head(store_dir, 20n)
    case False{}:
      run_log_parsed(Nat.read(limit_text), store_dir)
def run_log(+store_dir: String, +limit_text: String) -> IO(Render.Outcome):
  run_log_empty(String.is_empty(limit_text), store_dir, limit_text)
def decode_stage_go(+strs: List<&2, String>, +acc: List<&2, LogicalKey.LogicalKey>) -> List<&2, LogicalKey.LogicalKey>:
  match strs:
    case Nil{}:
      List.reverse(&2, LogicalKey.LogicalKey, acc)
    case Con{head_str, rest_strs}:
      decode_stage_go(rest_strs, Con{LogicalKey.split_combined_key(head_str), acc})
def decode_stage(+strs: List<&2, String>) -> List<&2, LogicalKey.LogicalKey>:
  decode_stage_go(strs, Nil{})
def finish_status_answer(+session_id: String, answer: Result<&1, &1, U32 & String, List<&2, String>>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{key_strs}:
      do IO<Render.Outcome>:
        return Render.Ok{Render.render_status(session_id, decode_stage(key_strs))}
def run_status(+store_dir: String, +session_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, List<&2, String>> <- run_durable(&2, List<&2, String>, store_dir, Staging.load_stage_index(session_id))
    finish_status_answer(session_id, answer)
def finish_init_rich(+store_dir: String, +opts: Render.HumanOpts, rich_logo: Bool) -> String:
  match rich_logo:
    case True{}:
      Render.welcome_header(opts) ++ "\nstore ready at " ++ store_dir
    case False{}:
      Render.welcome_fallback() ++ "\nstore ready at " ++ store_dir
def finish_init_ok(+store_dir: String, color_on: Bool, rich_logo: Bool) -> Render.Outcome:
  Render.Ok{finish_init_rich(store_dir, Render.opts_of(color_on, False{}), rich_logo)}
def init_opened(+store_dir: String, color_on: Bool, rich_logo: Bool, open_result: Result<&1, &1, U32 & String, Store.Handle>) -> IO(Render.Outcome):
  match open_result:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{unused_store}:
      do IO<Render.Outcome>:
        return finish_init_ok(store_dir, color_on, rich_logo)
def run_init(+store_dir: String, color_on: Bool, rich_logo: Bool) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    open_result : Result<&1, &1, U32 & String, Store.Handle> <- open_cli_store(store_dir)
    init_opened(store_dir, color_on, rich_logo, open_result)

# --- commit arms ---

def finish_commit_ok(+store_dir: String, +new_commit: History.Commit) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    _wrote : Unit <- log_append(store_dir, History.commit_identifier_of(new_commit))
    return Render.Ok{"committed:" ++ History.commit_identifier_of(new_commit)}

def finish_commit_answer(+store_dir: String, answer: Result<&1, &1, U32 & String, History.Commit>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{new_commit}:
      finish_commit_ok(store_dir, new_commit)

# --meta deferred to v2 (splitting k=v needs string ops); parse stores Nil{}
# and the field stays for forward compatibility.
def run_commit_create(+store_dir: String, +session_id: String, +parents: List<&2, String>, +metas: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, History.Commit> <- run_durable(&2, History.Commit, store_dir, Ber.create_commit(session_id, parents, Nil{}))
    finish_commit_answer(store_dir, answer)

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

def finish_diff_verbose(verbose: Bool, +first_id: String, +second_id: String, +compared: Comparison.CompareResult) -> Render.Outcome:
  match verbose:
    case True{}:
      Render.Ok{Render.render_table_diff(first_id, second_id, Comparison.added_keys_of(compared), Comparison.removed_keys_of(compared), Comparison.modified_entries_of(compared))}
    case False{}:
      finish_diff_value(compared)

def finish_diff_answer(+first_id: String, +second_id: String, verbose: Bool, answer: Result<&1, &1, U32 & String, Comparison.CompareResult>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{compared}:
      do IO<Render.Outcome>:
        return finish_diff_verbose(verbose, first_id, second_id, compared)

def run_diff(+store_dir: String, +first_id: String, +second_id: String, verbose: Bool) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Comparison.CompareResult> <- run_durable(&2, Comparison.CompareResult, store_dir, Ber.compare_commits(first_id, second_id))
    finish_diff_answer(first_id, second_id, verbose, answer)

# --- merge arms (merge flushes, then verify replays the flushed WAL) ---

def merge_verify_ok(+store_dir: String, +resulting_commit: History.Commit, verified_ok: Bool) -> IO(Render.Outcome):
  match verified_ok:
    case True{}:
      do IO<Render.Outcome>:
        _wrote : Unit <- log_append(store_dir, History.commit_identifier_of(resulting_commit))
        return Render.Merged{History.commit_identifier_of(resulting_commit)}
    case False{}:
      do IO<Render.Outcome>:
        return Render.Unprovable{"verify-failed"}

def finish_verify_answer(+store_dir: String, +resulting_commit: History.Commit, answer: Result<&1, &1, U32 & String, Bool>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{verified_ok}:
      merge_verify_ok(store_dir, resulting_commit, verified_ok)

def verify_merge_durable(+store_dir: String, +resulting_commit: History.Commit, +certificate: Merging.MergeCertificate) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, Bool> <- run_durable(&2, Bool, store_dir, Ber.verify_certificate(certificate))
    finish_verify_answer(store_dir, resulting_commit, answer)

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

def finish_write_ok(+store_dir: String, +commit_id: String) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    _wrote : Unit <- log_append(store_dir, commit_id)
    return Render.Ok{"committed:" ++ commit_id}

def finish_write_answer(+store_dir: String, answer: Result<&1, &1, U32 & String, String>) -> IO(Render.Outcome):
  match answer:
    case Fail{error}:
      do IO<Render.Outcome>:
        return Render.IoError{"store-failed"}
    case Done{commit_id}:
      finish_write_ok(store_dir, commit_id)

def run_write(+store_dir: String, +session_id: String, +namespace_name: String, +record_id: String, +value: Value.Value, +parents: List<&2, String>) -> IO(Render.Outcome):
  do IO<Render.Outcome>:
    answer : Result<&1, &1, U32 & String, String> <- run_durable(&2, String, store_dir, Ber.commit_value(session_id, namespace_name, record_id, value, parents))
    finish_write_answer(store_dir, answer)

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

def execute(+opts: Args.GlobalOpts, +cmd: Args.Command, +env: EnvFlags) -> IO(Render.Outcome):
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
    case Args.Set{session_id, namespace_name, record_id, source, parents}:
      run_write_source(Args.store_dir_of(opts), Args.session_or(opts, session_id), namespace_name, record_id, source, parents)
    case Args.Get{namespace_name, record_id, commit_id}:
      run_get_maybe_head(Args.store_dir_of(opts), namespace_name, record_id, commit_id)
    case Args.Log{limit_text}:
      run_log(Args.store_dir_of(opts), limit_text)
    case Args.Status{session_id}:
      run_status(Args.store_dir_of(opts), Args.session_or(opts, session_id))
    case Args.Init{}:
      run_init(Args.store_dir_of(opts), color_of(opts, env), rich_of(opts, env))
    case Args.Version{}:
      do IO<Render.Outcome>:
        return Render.Ok{Render.version_text()}
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

def no_color_set(res: Result<&1, &1, U32 & String, String>) -> Bool:
  match res:
    case Fail{error}:
      False{}
    case Done{val}:
      True{}

def term_is_dumb(res: Result<&1, &1, U32 & String, String>) -> Bool:
  match res:
    case Fail{error}:
      False{}
    case Done{val}:
      String.eq(val, "dumb")

def lang_is_c(res: Result<&1, &1, U32 & String, String>) -> Bool:
  match res:
    case Fail{error}:
      False{}
    case Done{val}:
      String.starts_with(val, "C")

def env_of(term_res: Result<&1, &1, U32 & String, String>, nocolor_res: Result<&1, &1, U32 & String, String>, lang_res: Result<&1, &1, U32 & String, String>) -> EnvFlags:
  Env{term_is_dumb(term_res), no_color_set(nocolor_res), lang_is_c(lang_res)}

def read_env_flags() -> IO(EnvFlags):
  do IO<EnvFlags>:
    term_res : Result<&1, &1, U32 & String, String> <- IO.get_env("TERM")
    nocolor_res : Result<&1, &1, U32 & String, String> <- IO.get_env("NO_COLOR")
    lang_res : Result<&1, &1, U32 & String, String> <- IO.get_env("LANG")
    return env_of(term_res, nocolor_res, lang_res)

def finish_argv(+opts: Args.GlobalOpts, +outcome: Render.Outcome, +env: EnvFlags) -> IO(Unit):
  finish_argv_go(Render.render_outcome(outcome, Args.json_flag_of(opts), Render.opts_of(color_of(opts, env), Args.verbose_flag_of(opts))), outcome, Render.succeeded(outcome))

def run_argv_env(+opts: Args.GlobalOpts, +cmd: Args.Command, +env: EnvFlags) -> IO(Unit):
  do IO<Unit>:
    outcome : Render.Outcome <- execute(opts, cmd, env)
    finish_argv(opts, outcome, env)

def run_argv_exec(+opts: Args.GlobalOpts, +cmd: Args.Command) -> IO(Unit):
  do IO<Unit>:
    env : EnvFlags <- read_env_flags()
    run_argv_env(opts, cmd, env)

def run_argv_go(+both: Sigma<&2, &2, Args.GlobalOpts, _ => Args.Command>) -> IO(Unit):
  match both:
    case (opts, cmd):
      run_argv_exec(opts, cmd)

# Bend >= 2.0.32 passes argv[0] (program path) in IO.args(); older toolchains
# did not. The parser takes user args only, so the head token always drops.
def strip_argv0(argv: List<String>) -> List<String>:
  match argv:
    case Nil{}:
      Nil{}
    case Con{head_arg, tail_args}:
      tail_args

def run_argv(argv: List<String>) -> IO(Unit):
  run_argv_go(Args.parse_both(strip_argv0(argv)))
