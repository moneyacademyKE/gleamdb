import aarondb/storage/internal
import gleam/dict
import gleam/option.{type Option, None, Some}

pub fn merge_optional_stores(
  s1: Option(dict.Dict(String, List(internal.StorageChunk))),
  s2: Option(dict.Dict(String, List(internal.StorageChunk))),
) -> Option(dict.Dict(String, List(internal.StorageChunk))) {
  case s1, s2 {
    Some(m1), Some(m2) -> Some(dict.merge(m1, m2))
    Some(_), None -> s1
    None, Some(_) -> s2
    None, None -> None
  }
}
