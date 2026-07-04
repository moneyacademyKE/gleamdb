import aarondb/fact
import aarondb/shared/ast.{
  type BodyClause, type Part, Negative, Positive, Val, Var,
}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type QueryBuilder {
  QueryBuilder(
    find: List(String),
    clauses: List(BodyClause),
    order_by: Option(ast.OrderBy),
    limit: Option(Int),
    offset: Option(Int),
  )
}

pub fn new() -> QueryBuilder {
  QueryBuilder(find: [], clauses: [], order_by: None, limit: None, offset: None)
}

pub fn from_clauses(clauses: List(BodyClause)) -> QueryBuilder {
  QueryBuilder(
    find: [],
    clauses: clauses,
    order_by: None,
    limit: None,
    offset: None,
  )
}

pub fn select(vars: List(String)) -> QueryBuilder {
  QueryBuilder(
    find: vars,
    clauses: [],
    order_by: None,
    limit: None,
    offset: None,
  )
}

/// Helper for string value
pub fn s(val: String) -> Part {
  Val(fact.Str(val))
}

/// Helper for int value
pub fn i(val: Int) -> Part {
  Val(fact.Int(val))
}

/// Helper for variable
pub fn v(name: String) -> Part {
  Var(name)
}

/// Helper for vector value
pub fn vec(val: List(Float)) -> Part {
  Val(fact.Vec(val))
}

/// Add a where clause (Entity, Attribute, Value).
pub fn where(
  builder: QueryBuilder,
  entity: Part,
  attr: String,
  value: Part,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, value))
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Add a negative where clause (Entity, Attribute, Value).
pub fn negate(
  builder: QueryBuilder,
  entity: Part,
  attr: String,
  value: Part,
) -> QueryBuilder {
  let clause = Negative(#(entity, attr, value))
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Count aggregate
pub fn count(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Count, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Sum aggregate
pub fn sum(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Sum, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Avg aggregate
pub fn avg(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Avg, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Median aggregate
pub fn median(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Median, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Min aggregate
pub fn min(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Min, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Max aggregate
pub fn max(
  builder: QueryBuilder,
  into: String,
  target: String,
  filter: List(BodyClause),
) -> QueryBuilder {
  let clause = ast.Aggregate(into, ast.Max, Var(target), filter)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Placeholder for similarity search
pub fn similar(
  builder: QueryBuilder,
  entity: Part,
  attr: String,
  vector: List(Float),
  _threshold: Float,
) -> QueryBuilder {
  let clause = Positive(#(entity, attr, Val(fact.Vec(vector))))
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Temporal range query (on Transaction Time)
pub fn temporal(
  builder: QueryBuilder,
  variable: String,
  entity: Part,
  _attr: String,
  start: Int,
  _end: Int,
) -> QueryBuilder {
  let clause = ast.Temporal(ast.Tx, start, ast.At, variable, entity, [])
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Temporal range query (on Valid Time)
pub fn valid_temporal(
  builder: QueryBuilder,
  variable: String,
  entity: Part,
  _attr: String,
  start: Int,
  _end: Int,
) -> QueryBuilder {
  let clause = ast.Temporal(ast.Valid, start, ast.At, variable, entity, [])
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Filter results since a specific value (exclusive)
pub fn since(
  builder: QueryBuilder,
  variable: String,
  val: Part,
) -> QueryBuilder {
  let clause = ast.Filter(ast.Gt(Var(variable), val))
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Limit results
pub fn limit(builder: QueryBuilder, n: Int) -> QueryBuilder {
  QueryBuilder(..builder, limit: Some(n))
}

/// Offset results
pub fn offset(builder: QueryBuilder, n: Int) -> QueryBuilder {
  QueryBuilder(..builder, offset: Some(n))
}

/// Order results
pub fn order_by(
  builder: QueryBuilder,
  variable: String,
  direction: ast.OrderDirection,
) -> QueryBuilder {
  QueryBuilder(..builder, order_by: Some(ast.OrderBy(variable, direction)))
}

/// Find the shortest path between two entities via an edge attribute.
pub fn shortest_path(
  builder: QueryBuilder,
  from: Part,
  to: Part,
  edge: String,
  path_var: String,
  cost_var cost_var: Option(String),
  max_depth max_depth: Option(Int),
) -> QueryBuilder {
  let clause = ast.ShortestPath(from, to, edge, path_var, cost_var, max_depth)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Calculate PageRank for nodes connected by an edge.
pub fn pagerank(
  builder: QueryBuilder,
  entity_var: String,
  edge: String,
  rank_var: String,
  damping damping: Float,
  iterations iterations: Int,
) -> QueryBuilder {
  let clause = ast.PageRank(entity_var, edge, rank_var, damping, iterations)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Query an external data source (Virtual Predicate).
pub fn virtual(
  builder: QueryBuilder,
  predicate: String,
  args: List(Part),
  outputs: List(String),
) -> QueryBuilder {
  let clause = ast.Virtual(predicate, args, outputs)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Label each node with a connected component ID.
pub fn connected_components(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  component_var: String,
) -> QueryBuilder {
  let clause = ast.ConnectedComponents(edge, entity_var, component_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Find all nodes reachable from a starting node.
pub fn reachable(
  builder: QueryBuilder,
  from: Part,
  edge: String,
  node_var: String,
) -> QueryBuilder {
  let clause = ast.Reachable(from, edge, node_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Find all nodes within K hops of a starting node.
pub fn neighbors(
  builder: QueryBuilder,
  from: Part,
  edge: String,
  depth: Int,
  node_var: String,
) -> QueryBuilder {
  let clause = ast.Neighbors(from, edge, depth, node_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Detect cycles in directed graph. Each result binds a List of entity refs forming a cycle.
pub fn cycle_detect(
  builder: QueryBuilder,
  edge: String,
  cycle_var: String,
) -> QueryBuilder {
  let clause = ast.CycleDetect(edge, cycle_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Calculate betweenness centrality (Brandes' algorithm) for each node.
pub fn betweenness_centrality(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  score_var: String,
) -> QueryBuilder {
  let clause = ast.BetweennessCentrality(edge, entity_var, score_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Topological ordering of a DAG. Returns empty if cycles exist.
pub fn topological_sort(
  builder: QueryBuilder,
  edge: String,
  entity_var: String,
  order_var: String,
) -> QueryBuilder {
  let clause = ast.TopologicalSort(edge, entity_var, order_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Generic filter expression.
pub fn filter(builder: QueryBuilder, expr: ast.Expression) -> QueryBuilder {
  let clause = ast.Filter(expr)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Pull attributes for an entity into a variable.
pub fn pull(
  builder: QueryBuilder,
  variable: String,
  entity: Part,
  pattern: ast.PullPattern,
) -> QueryBuilder {
  let clause = ast.Pull(variable, entity, pattern)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Semantic cognitive search using ACT-R Decay and Hebbian weights
pub fn cognitive(
  builder: QueryBuilder,
  concept: Part,
  context: Part,
  threshold: Float,
  engram_var: String,
) -> QueryBuilder {
  let clause = ast.Cognitive(concept, context, threshold, engram_var)
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

/// Convert builder to a list of clauses for backwards compatibility.
/// NOTE: This will lose find/limit/offset/order info.
pub fn to_clauses(builder: QueryBuilder) -> List(BodyClause) {
  builder.clauses
}

/// Convert builder to a full Query AST.
pub fn to_query(builder: QueryBuilder) -> ast.Query {
  ast.Query(
    find: builder.find,
    where: builder.clauses,
    order_by: builder.order_by,
    limit: builder.limit,
    offset: builder.offset,
  )
}
