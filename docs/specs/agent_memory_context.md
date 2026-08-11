# Historical PRD: Agent Memory Context (Graph RAG Macros)

> **Status: historical design input, not current API documentation.** The current supported RAG surface is `aarondb/rag.build_query/1`, consumed by the local MCP `recall` tool. There is no `rag.semantic_search` public API and no MCP `semantic_search` endpoint. See [RAG status](../feature_maturity.md#legacy-and-inactive-surfaces) and [Local MCP stdio](../manual/mcp_stdio.md).


**Role:** Lead Product Manager
**Persona:** Rich Hickey (Focus on declarative data and functional composition over novel stateful engines)

## User Story
"As an AI Agent developer, I want a unified, semantically-aware retrieval interface so that my agents can perform Graph RAG and multi-hop memory recall without needing to manually construct complex, multi-join Datalog queries."

## Acceptance Criteria
- **Given** a semantic intent request (e.g., "Find documents related to concept X connected by relationship Y"),
- **When** the request is passed to the `rag.gleam` query planner/macro layer,
- **Then** the request is translated into a pure, optimized AaronDB Datalog AST (combining `Bind`, `ShortestPath`, and vector similarity).
- **And** the results are returned identically to how standard queries operate, maintaining the EAVT foundation without introducing new storage paradigms.

## Technical Constraints
- Must NOT introduce new storage formats or indexing mechanisms. The macro must operate strictly on top of the existing EAVT and HNSW indices.
- Must be a pure-functional translation layer: `f(SemanticIntent) -> DatalogAST`.
- Should leverage existing native traversals (like `ShortestPath` and `PageRank`) inside the AST generation.

## UI/UX Notes
- Developers using AaronDB via Erlang or Gleam will call a new public function `rag.semantic_search(intent)` rather than building raw `q.Query(...)` for these specific highly-reusable Graph RAG patterns.
- AI Agents via MCP will have a simplified `semantic_search` JSON-RPC endpoint.

## Note
PRD Generated. Run `/implement` (or `[/proceed]`) to hand off to the Developer Agent to begin implementation according to the Rich Hickey quality standards.
