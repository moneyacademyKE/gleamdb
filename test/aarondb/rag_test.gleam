import aarondb/fact
import aarondb/rag.{ConceptRecall, ConnectedConcept, EvidenceGraph}
import aarondb/shared/ast
import gleam/option.{None, Some}
import gleeunit/should

pub fn build_concept_recall_test() {
  let query = rag.build_query(ConceptRecall("machine learning", 0.7, 10))

  query.find |> should.equal(["?engram"])
  query.limit |> should.equal(Some(10))

  case query.where {
    [ast.Cognitive(ast.Val(_), ast.Val(_), 0.7, "?engram")] -> Nil
    _ -> should.fail()
  }
}

pub fn build_connected_concept_test() {
  let query = rag.build_query(ConnectedConcept(42, "AI Safety", "depends_on"))

  query.find |> should.equal(["?path", "?engram"])

  case query.where {
    [
      ast.Cognitive(_, _, 0.5, "?engram"),
      ast.ShortestPath(
        ast.Uid(id),
        ast.Var("?engram"),
        "depends_on",
        "?path",
        None,
        Some(5),
      ),
    ] -> {
      id |> should.equal(fact.ref(42))
      Nil
    }
    _ -> should.fail()
  }
}

pub fn build_evidence_graph_test() {
  let query = rag.build_query(EvidenceGraph(100, 200, 3))

  query.find |> should.equal(["?path"])

  case query.where {
    [
      ast.ShortestPath(
        ast.Uid(a),
        ast.Uid(b),
        "engram/supports",
        "?path",
        None,
        Some(3),
      ),
    ] -> {
      a |> should.equal(fact.ref(100))
      b |> should.equal(fact.ref(200))
      Nil
    }
    _ -> should.fail()
  }
}
