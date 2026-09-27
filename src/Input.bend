import Base
import ./Args.bend as Args
import ber-core-store@0.1.1.0/src/Value.bend as Value
import ber-core-store@0.1.1.0/src/JsonAdapter.bend as JsonAdapter
import bend-kit-json@0.3.0.0/json.bend as Json

# Pure flag→Value mapping. Files need IO so FromFile always answers None
# here; Run reads the bytes and re-enters with FromText/FromJson/FromBlobHex.

def json_text_to_object_go(parsed: Maybe<&2, Json.Val>) -> Maybe<&2, Value.Value>:
  match parsed:
    case None{}:
      None{}
    case Some{document}:
      Some{Value.Object{document}}

def json_text_to_object(+json_text: String) -> Maybe<&2, Value.Value>:
  json_text_to_object_go(JsonAdapter.parse_text(json_text))

def source_to_value(+source: Args.ValueSource) -> Maybe<&2, Value.Value>:
  match source:
    case Args.FromText{content}:
      Some{Value.Text{content}}
    case Args.FromJson{json_text}:
      json_text_to_object(json_text)
    case Args.FromBlobHex{hex_text}:
      Value.blob_from_hex(Some{hex_text})
    case Args.FromFile{file_path, kind_name}:
      None{}
