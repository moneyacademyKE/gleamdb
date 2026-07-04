import aarondb/fact
import aarondb/q.{type QueryBuilder, QueryBuilder}
import aarondb/shared/ast
import gleam/list
import gleam/option.{None, Some}

/// Rich Hickey 🧙🏾‍♂️:
/// A macro expands high-level declarative intent into fundamental, composable data structures.
/// This module avoids building a new "Graph RAG Engine", instead mapping Semantic Intents
/// purely into Datalog ASTs which AaronDB already computes efficiently.
pub type SemanticIntent {
  /// Basic vector similarity recall
  ConceptRecall(context: String, threshold: Float, limit: Int)

  /// Find shortest path between a known entity and a semantic concept
  ConnectedConcept(from_entity_id: Int, target_context: String, edge: String)

  /// Find evidence/reasoning supporting a connection
  EvidenceGraph(entity_a_id: Int, entity_b_id: Int, max_depth: Int)
}

/// Compiles a semantic intent into a pure AaronDB Query AST.
/// Time Complexity: O(1) AST generation.
/// Space Complexity: O(1) AST size.
pub fn build_query(intent: SemanticIntent) -> ast.Query {
  let builder = case intent {
    ConceptRecall(ctx, threshold, lim) -> {
      q.select(["?engram"])
      |> add_clause(ast.Cognitive(
        concept: q.s(ctx),
        context: q.s(ctx),
        threshold: threshold,
        engram_var: "?engram",
      ))
      |> set_limit(lim)
    }

    ConnectedConcept(from_id, target_ctx, edge) -> {
      q.select(["?path", "?engram"])
      |> add_clause(ast.Cognitive(
        concept: q.s(target_ctx),
        context: q.s(target_ctx),
        threshold: 0.5,
        engram_var: "?engram",
      ))
      |> add_clause(ast.ShortestPath(
        from: ast.Uid(fact.ref(from_id)),
        to: q.v("?engram"),
        edge: edge,
        path_var: "?path",
        cost_var: None,
        max_depth: Some(5),
      ))
    }

    EvidenceGraph(a_id, b_id, max_depth) -> {
      q.select(["?path"])
      |> add_clause(ast.ShortestPath(
        from: ast.Uid(fact.ref(a_id)),
        to: ast.Uid(fact.ref(b_id)),
        edge: "engram/supports",
        path_var: "?path",
        cost_var: None,
        max_depth: Some(max_depth),
      ))
    }
  }

  // Convert builder to the final Query AST
  ast.Query(
    find: builder.find,
    where: builder.clauses,
    order_by: builder.order_by,
    limit: builder.limit,
    offset: builder.offset,
  )
}

fn add_clause(builder: QueryBuilder, clause: ast.BodyClause) -> QueryBuilder {
  QueryBuilder(..builder, clauses: list.append(builder.clauses, [clause]))
}

fn set_limit(builder: QueryBuilder, lim: Int) -> QueryBuilder {
  QueryBuilder(..builder, limit: Some(lim))
}
