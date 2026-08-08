import aarondb/fact.{type Datom, type EntityId, type Value}
import gleam/dynamic
import gleam/list
import gleam/option.{type Option, None, Some}

pub type TableName =
  String

pub fn init_tables(db_name: String) -> Nil {
  let eavt = db_name <> "_eavt"
  let aevt = db_name <> "_aevt"
  let avet = db_name <> "_avet"

  do_init_table(eavt, DuplicateBag)
  do_init_table(aevt, DuplicateBag)
  do_init_table(avet, Set)
  Nil
}

pub type TableType {
  Set
  OrderedSet
  Bag
  DuplicateBag
}

@external(erlang, "aarondb_ets_ffi", "init_table")
fn do_init_table(name: String, table_type: TableType) -> Nil

pub fn insert_datom(table: TableName, key: any, datom: Datom) -> Nil {
  do_insert(table, #(key, datom))
}

pub fn insert_avet(
  table: TableName,
  key: #(String, Value),
  eid: EntityId,
) -> Nil {
  do_insert(table, #(key, eid))
}

@external(erlang, "aarondb_ets_ffi", "insert")
fn do_insert(table: TableName, object: any) -> Nil

pub fn lookup_datoms(table: TableName, key: any) -> List(Datom) {
  do_lookup_datoms(table, key)
  |> list.map(fn(obj) {
    let #(_key, val) = obj
    val
  })
}

@external(erlang, "aarondb_ets_ffi", "lookup")
fn do_lookup_datoms(table: TableName, key: any) -> List(#(any, Datom))

pub fn delete(table: TableName, key: any) -> Nil {
  do_delete(table, key)
}

@external(erlang, "aarondb_ets_ffi", "delete")
fn do_delete(table: TableName, key: any) -> Nil

pub fn get_av(table: TableName, attr: String, val: Value) -> Option(EntityId) {
  case do_lookup_avet(table, #(attr, val)) {
    [#(_key, eid)] -> Some(eid)
    _ -> None
  }
}

@external(erlang, "aarondb_ets_ffi", "lookup")
fn do_lookup_avet(table: TableName, key: any) -> List(#(any, EntityId))

pub fn prune_historical(table: TableName, eid: EntityId, attr: String) -> Nil {
  do_prune_eavt(table, eid, attr)
}

pub fn serialize_term(term: any) -> BitArray {
  do_term_to_binary(term)
}

@external(erlang, "erlang", "term_to_binary")
fn do_term_to_binary(data: any) -> BitArray

pub fn deserialize_term(b: BitArray) -> Result(dynamic.Dynamic, Nil) {
  do_binary_to_term(b)
}

@external(erlang, "aarondb_term_ffi", "decode_term")
fn do_binary_to_term(data: BitArray) -> Result(dynamic.Dynamic, Nil)

pub fn get_raw_binary(table: TableName, key: any) -> Result(BitArray, Nil) {
  do_get_raw_binary(table, key)
}

@external(erlang, "aarondb_ets_ffi", "get_raw_binary")
fn do_get_raw_binary(table: TableName, key: any) -> Result(BitArray, Nil)

pub fn prune_historical_aevt(
  table: TableName,
  attr: String,
  eid: EntityId,
) -> Nil {
  do_prune_aevt(table, attr, eid)
}

@external(erlang, "aarondb_ets_ffi", "prune_eavt")
fn do_prune_eavt(table: TableName, eid: EntityId, attr: String) -> Nil

@external(erlang, "aarondb_ets_ffi", "prune_aevt")
fn do_prune_aevt(table: TableName, attr: String, eid: EntityId) -> Nil
