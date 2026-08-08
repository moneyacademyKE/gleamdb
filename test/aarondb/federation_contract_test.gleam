import aarondb
import aarondb/fact.{Str}
import aarondb/federation
import aarondb/shared/ast
import gleam/dict
import gleam/option.{None}
import gleeunit/should

fn people_query() -> ast.Query {
  ast.Query(
    find: ["name"],
    where: [ast.Positive(#(ast.Var("e"), "person/name", ast.Var("name")))],
    order_by: None,
    limit: None,
    offset: None,
  )
}

pub fn local_federation_retains_source_provenance_in_name_order_test() {
  let alpha = aarondb.new()
  let zeta = aarondb.new()
  let assert Ok(_) =
    aarondb.transact(alpha, [
      #(fact.Uid(fact.EntityId(1)), "person/name", Str("Ada")),
    ])
  let assert Ok(_) =
    aarondb.transact(zeta, [
      #(fact.Uid(fact.EntityId(2)), "person/name", Str("Zoe")),
    ])
  let assert Ok(federation) =
    federation.new([
      federation.Source("zeta", zeta),
      federation.Source("alpha", alpha),
    ])

  let federation.FederatedResult(rows:, sources:) =
    federation.query(federation, people_query())

  sources |> should.equal(["alpha", "zeta"])
  let assert [
    federation.FederatedRow(source: first_source, row: first_row),
    federation.FederatedRow(source: second_source, row: second_row),
  ] = rows
  first_source |> should.equal("alpha")
  second_source |> should.equal("zeta")
  dict.get(first_row, "name") |> should.equal(Ok(Str("Ada")))
  dict.get(second_row, "name") |> should.equal(Ok(Str("Zoe")))
}

pub fn local_federation_rejects_duplicate_source_names_test() {
  let db = aarondb.new()

  federation.new([
    federation.Source("primary", db),
    federation.Source("primary", db),
  ])
  |> should.equal(Error("Duplicate federation source: primary"))
}

pub fn local_federation_rejects_empty_sources_test() {
  federation.new([])
  |> should.equal(Error("A federation requires at least one source"))
}
