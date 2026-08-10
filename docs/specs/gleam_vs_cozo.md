# Historical Comparison Notes: GleamDB vs CozoDB

> **Status: historical comparison, not a current architecture or capability claim.** The distributed Erlang, Mnesia replication, hot-reload, scale, and maturity statements below predate the v4.1.0 embedded/local boundary and must not be read as supported behavior. Current claims are defined by [Feature Maturity](../feature_maturity.md) and [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md).


> "Simple is often mistakenly associated with easy."

## The Core Trade-off: Native BEAM vs Hybrid Rust

### 1. GleamDB (Native BEAM)
**Philosophy**: Simplicity, purity, and leverage of the existing VM capabilities (Mnesia, ETS, Distributed Erlang).

#### Pros
- **Fault Tolerance**: Inherits the BEAM's supervision trees. A crash in the DB engine is just a process restart, managed by OTP.
- **Introspection**: You can `observer:start()` and inspect the database state, message queues, and memory usage in real-time.
- **Distribution**: Uses Distributed Erlang for clustering. Nodes join, data replicates naturally (if using Mnesia backend).
- **Deployment**: A single binary/beam release. No NIFs (Native Implemented Functions) to compile or link against system libraries.
- **Hot Code Reloading**: The database engine logic can be upgraded without stopping the system.

#### Cons
- **Performance Ceiling**: The BEAM is not optimized for raw number crunching or heavy loop unrolling like Rust/C++. Complex joins on millions of rows will be slower.
- **Maturity**: Evolving rapidly. Now features **Navigator** (cost-based planner), **Chronos** (bitemporal), **Graph Suite** (9 predicates), and **HNSW** vector search ($O(\log N)$).

### 2. CozoDB (Rust / NIFs)
**Philosophy**: Performance, features, and polyglot flexibility.

#### Pros
- **Raw Speed**: Written in Rust, it uses bleeding-edge optimizations (SIMD, zero-copy) for query execution.
- **Durability Engines**: Pluggable storage (RocksDB, Sled, SQLite, S3) with proven reliability.
- **Graph Algorithms**: Built-in PageRank, shortest path, etc., optimized in native code.
- **Time Travel**: Robust implementation of validity time and transaction time.

#### Cons
- **Complexity**: Integrating NIFs introduces risk. If the Rust code panics or leaks memory, it can bring down the entire BEAM VM.
- **Operational Overhead**: Cross-compilation for different architectures (ARM vs x86) can be painful. Debugging across the language boundary is hard.
- **"Black Box"**: The engine is opaque to the BEAM's introspection tools. You monitor it via external metrics, not `sys:get_status`.

## Conclusion

**Choose GleamDB if**:
- You prioritize system stability and total ownership of the stack.
- Your dataset fits in memory (ETS) or you are okay with Mnesia's trade-offs.
- You want "Database as a Value" semantics strictly within Gleam constructs.

**Choose CozoDB if**:
- You need to perform complex graph analytics on large datasets (> 1GB).
- You need robust, proven durability on disk immediately.
- You are comfortable managing NIFs and the associated build pipeline.
