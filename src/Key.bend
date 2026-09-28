import Base

# KEY = ns/record split. Only "/" separates; any ":" rejects the whole key
# (single-separator design). Multi-"/" and empty segments reject too.
#
# Built on String.split (Base) so there is no manual char scan and no
# recursion cycle: every helper is a linear decide-chain over parameters
# (ber-core style), leaf-first ordered.

def decide_record_empty(is_empty: Bool, +ns_name: String, +rec_name: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match is_empty:
    case True{}:
      None{}
    case False{}:
      Some{(ns_name, rec_name)}

def finish_ns_empty(is_empty: Bool, +ns_name: String, +rec_name: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match is_empty:
    case True{}:
      None{}
    case False{}:
      decide_record_empty(String.is_empty(rec_name), ns_name, rec_name)

def finish_pair(+ns_name: String, +rec_name: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  finish_ns_empty(String.is_empty(ns_name), ns_name, rec_name)

def split_tail(+ns_name: String, +rec_name: String, tail_parts: List<&2, String>) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match tail_parts:
    case Nil{}:
      finish_pair(ns_name, rec_name)
    case Con{extra_part, more_parts}:
      None{}

def split_rest(+ns_name: String, rest_parts: List<&2, String>) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match rest_parts:
    case Nil{}:
      None{}
    case Con{rec_name, tail_parts}:
      split_tail(ns_name, rec_name, tail_parts)

def split_parts(parts: List<&2, String>) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match parts:
    case Nil{}:
      None{}
    case Con{ns_name, rest_parts}:
      split_rest(ns_name, rest_parts)

def split_nocolon(has_colon: Bool, +key: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  match has_colon:
    case True{}:
      None{}
    case False{}:
      split_parts(String.split(key, Chr{(47 : U32)}))

def split_key(+key: String) -> Maybe<&2, Sigma<&2, &2, String, _ => String>>:
  split_nocolon(String.contains(key, ":"), key)
