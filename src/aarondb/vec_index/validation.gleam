import aarondb/vector

/// True when a vector has at least one dimension and non-zero magnitude.
pub fn vector_is_valid(vec: List(Float)) -> Bool {
  vector.dimensions(vec) > 0 && vector.magnitude(vec) != 0.0
}

/// True when a query can be evaluated against an index.
pub fn query_is_valid(query: List(Float), threshold: Float, k: Int) -> Bool {
  vector_is_valid(query) && threshold >=. -1.0 && threshold <=. 1.0 && k > 0
}
