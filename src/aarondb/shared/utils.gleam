import gleam/string

/// Extract the largest balanced JSON object from a string.
/// This is useful for parsing LLM outputs that may contain preamble or postscript noise.
pub fn extract_json(input: String) -> String {
  case string.split_once(input, "{") {
    Ok(#(_, rest)) -> {
      let candidate = "{" <> rest
      do_extract(candidate, 0, False, "")
    }
    Error(_) -> ""
  }
}

fn do_extract(
  input: String,
  depth: Int,
  in_quote: Bool,
  acc: String,
) -> String {
  case string.pop_grapheme(input) {
    Ok(#("\"", rest)) -> do_extract(rest, depth, !in_quote, acc <> "\"")
    Ok(#("{", rest)) if !in_quote ->
      do_extract(rest, depth + 1, False, acc <> "{")
    Ok(#("}", rest)) if !in_quote -> {
      let new_depth = depth - 1
      let new_acc = acc <> "}"
      case new_depth <= 0 {
        True -> new_acc
        False -> do_extract(rest, new_depth, False, new_acc)
      }
    }
    Ok(#(c, rest)) -> do_extract(rest, depth, in_quote, acc <> c)
    Error(_) -> acc
  }
}
