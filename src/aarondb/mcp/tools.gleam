//// # mcp/tools — MCP tool registry
////
//// Tool definitions exposed to MCP clients: `all_tools/0` returns the
//// registry. Pure data over `gleam/json`; no side effects.

import gleam/json

pub type Tool {
  Tool(
    name: String,
    description: String,
    input_schema: json.Json,
    // Represents the JSON schema as a JSON object
  )
}

pub fn precompiled_array(items: List(json.Json)) -> json.Json {
  json.array(items, of: fn(x) { x })
}

pub fn all_tools() -> List(Tool) {
  [
    Tool(
      name: "muninn_remember",
      description: "Store a new piece of information (engram) in long-term memory. IMPORTANT: Keep each memory atomic — one concept, decision, or fact per memory. If a conversation covers multiple topics, use muninn_remember_batch to store them as separate memories. Atomic memories produce sharper recall, better associations, and more accurate contradiction detection. TIP: Provide ‘entities’ and ‘entity_relationships’ whenever you can identify them — this builds the knowledge graph immediately without requiring background enrichment.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "concept",
              json.object([
                #("description", json.string("Short label for this memory.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "confidence",
              json.object([
                #(
                  "description",
                  json.string("Confidence score 0.0-1.0 (default 1.0)."),
                ),
                #("type", json.string("number")),
              ]),
            ),
            #(
              "content",
              json.object([
                #("description", json.string("The information to remember.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "created_at",
              json.object([
                #(
                  "description",
                  json.string(
                    "ISO 8601 timestamp for when this memory was created. Defaults to now. Use to seed memories at past or future times.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "entities",
              json.object([
                #(
                  "description",
                  json.string(
                    "Entities mentioned in this memory. Providing these skips background entity extraction.",
                  ),
                ),
                #(
                  "items",
                  json.object([
                    #(
                      "properties",
                      json.object([
                        #(
                          "capability_token",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "The capability token validating this action.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "name",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Entity name (e.g. 'PostgreSQL', 'Auth Service').",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "type",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Entity type (e.g. 'database', 'service', 'person', 'project').",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                      ]),
                    ),
                    #(
                      "required",
                      precompiled_array([
                        json.string("name"),
                        json.string("type"),
                      ]),
                    ),
                    #("type", json.string("object")),
                  ]),
                ),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "entity_relationships",
              json.object([
                #(
                  "description",
                  json.string(
                    "Typed semantic relationships between named entities in this memory. Populates the entity knowledge graph directly — no LLM enrichment required. Example: [{\"from_entity\":\"PostgreSQL\",\"to_entity\":\"Redis\",\"rel_type\":\"caches_with\",\"weight\":0.9}]. Common rel_types: uses, depends_on, caches_with, manages, owns, contradicts, supports, extends, implements, belongs_to.",
                  ),
                ),
                #(
                  "items",
                  json.object([
                    #(
                      "properties",
                      json.object([
                        #(
                          "capability_token",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "The capability token validating this action.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "from_entity",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Source entity name (must match an entity in 'entities' or already known to the vault).",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "rel_type",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Relationship type (e.g. uses, depends_on, caches_with, manages, contradicts).",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "to_entity",
                          json.object([
                            #("description", json.string("Target entity name.")),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "weight",
                          json.object([
                            #(
                              "description",
                              json.string("Confidence 0.0-1.0 (default 0.9)."),
                            ),
                            #("type", json.string("number")),
                          ]),
                        ),
                      ]),
                    ),
                    #(
                      "required",
                      precompiled_array([
                        json.string("from_entity"),
                        json.string("to_entity"),
                        json.string("rel_type"),
                      ]),
                    ),
                    #("type", json.string("object")),
                  ]),
                ),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "op_id",
              json.object([
                #(
                  "description",
                  json.string(
                    "Optional idempotency key. If set and a receipt exists for this key, the cached engram ID is returned without re-creating.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "relationships",
              json.object([
                #(
                  "description",
                  json.string(
                    "Relationships to existing memories. Creates associations at write time.",
                  ),
                ),
                #(
                  "items",
                  json.object([
                    #(
                      "properties",
                      json.object([
                        #(
                          "capability_token",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "The capability token validating this action.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "relation",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Relationship type (e.g. 'depends_on', 'supports', 'contradicts').",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "target_id",
                          json.object([
                            #(
                              "description",
                              json.string("ID of the target memory (ULID)."),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "weight",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Association weight 0.0-1.0 (default 0.9).",
                              ),
                            ),
                            #("type", json.string("number")),
                          ]),
                        ),
                      ]),
                    ),
                    #(
                      "required",
                      precompiled_array([
                        json.string("target_id"),
                        json.string("relation"),
                      ]),
                    ),
                    #("type", json.string("object")),
                  ]),
                ),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "summary",
              json.object([
                #(
                  "description",
                  json.string(
                    "One-line summary of what this memory captures. Providing this skips background summarization.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "tags",
              json.object([
                #("description", json.string("Optional topic tags.")),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "type",
              json.object([
                #(
                  "description",
                  json.string(
                    "Memory type — either a built-in name (fact, decision, observation, preference, issue, task, procedure, event, goal, constraint, identity, reference) or a free-form label (e.g. 'architectural_decision', 'coding_pattern'). Built-in names set the enum; free-form labels are stored as type_label with enum defaulting to 'fact'.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "type_label",
              json.object([
                #(
                  "description",
                  json.string(
                    "Explicit free-form type label (e.g. 'architectural_decision'). Overrides the label inferred from 'type'.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("content")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_remember_batch",
      description: "Store multiple memories at once. More efficient than calling muninn_remember repeatedly. Maximum 50 per batch. Best practice: break complex topics into individual atomic memories — one concept, decision, or fact each. This produces sharper embeddings, better associations, and more accurate retrieval.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "memories",
              json.object([
                #(
                  "description",
                  json.string("Array of memories to store (max 50)."),
                ),
                #(
                  "items",
                  json.object([
                    #(
                      "properties",
                      json.object([
                        #(
                          "capability_token",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "The capability token validating this action.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "concept",
                          json.object([
                            #(
                              "description",
                              json.string("Short label for this memory."),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "confidence",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Confidence score 0.0-1.0 (default 1.0).",
                              ),
                            ),
                            #("type", json.string("number")),
                          ]),
                        ),
                        #(
                          "content",
                          json.object([
                            #(
                              "description",
                              json.string("The information to remember."),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "created_at",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "ISO 8601 timestamp. Defaults to now.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "entities",
                          json.object([
                            #(
                              "description",
                              json.string("Entities mentioned in this memory."),
                            ),
                            #(
                              "items",
                              json.object([
                                #(
                                  "properties",
                                  json.object([
                                    #(
                                      "capability_token",
                                      json.object([
                                        #(
                                          "description",
                                          json.string(
                                            "The capability token validating this action.",
                                          ),
                                        ),
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "name",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "type",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                  ]),
                                ),
                                #(
                                  "required",
                                  precompiled_array([
                                    json.string("name"),
                                    json.string("type"),
                                  ]),
                                ),
                                #("type", json.string("object")),
                              ]),
                            ),
                            #("type", json.string("array")),
                          ]),
                        ),
                        #(
                          "entity_relationships",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Typed entity-to-entity relationships for this memory.",
                              ),
                            ),
                            #(
                              "items",
                              json.object([
                                #(
                                  "properties",
                                  json.object([
                                    #(
                                      "capability_token",
                                      json.object([
                                        #(
                                          "description",
                                          json.string(
                                            "The capability token validating this action.",
                                          ),
                                        ),
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "from_entity",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "rel_type",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "to_entity",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "weight",
                                      json.object([
                                        #("type", json.string("number")),
                                      ]),
                                    ),
                                  ]),
                                ),
                                #(
                                  "required",
                                  precompiled_array([
                                    json.string("from_entity"),
                                    json.string("to_entity"),
                                    json.string("rel_type"),
                                  ]),
                                ),
                                #("type", json.string("object")),
                              ]),
                            ),
                            #("type", json.string("array")),
                          ]),
                        ),
                        #(
                          "relationships",
                          json.object([
                            #(
                              "description",
                              json.string("Relationships to existing memories."),
                            ),
                            #(
                              "items",
                              json.object([
                                #(
                                  "properties",
                                  json.object([
                                    #(
                                      "capability_token",
                                      json.object([
                                        #(
                                          "description",
                                          json.string(
                                            "The capability token validating this action.",
                                          ),
                                        ),
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "relation",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "target_id",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #(
                                      "weight",
                                      json.object([
                                        #("type", json.string("number")),
                                      ]),
                                    ),
                                  ]),
                                ),
                                #(
                                  "required",
                                  precompiled_array([
                                    json.string("target_id"),
                                    json.string("relation"),
                                  ]),
                                ),
                                #("type", json.string("object")),
                              ]),
                            ),
                            #("type", json.string("array")),
                          ]),
                        ),
                        #(
                          "summary",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "One-line summary. Skips background summarization.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "tags",
                          json.object([
                            #(
                              "description",
                              json.string("Optional topic tags."),
                            ),
                            #(
                              "items",
                              json.object([#("type", json.string("string"))]),
                            ),
                            #("type", json.string("array")),
                          ]),
                        ),
                        #(
                          "type",
                          json.object([
                            #(
                              "description",
                              json.string(
                                "Memory type — built-in name or free-form label.",
                              ),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                        #(
                          "type_label",
                          json.object([
                            #(
                              "description",
                              json.string("Explicit free-form type label."),
                            ),
                            #("type", json.string("string")),
                          ]),
                        ),
                      ]),
                    ),
                    #("required", precompiled_array([json.string("content")])),
                    #("type", json.string("object")),
                  ]),
                ),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("memories")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_recall",
      description: "Search long-term memory using semantic context. Returns the most relevant memories.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "before",
              json.object([
                #(
                  "description",
                  json.string(
                    "ISO 8601 timestamp (e.g. 2026-01-20T00:00:00Z). Only return memories created before this time.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "context",
              json.object([
                #("description", json.string("Search context phrases.")),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string("Max results to return (default 10)."),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "mode",
              json.object([
                #(
                  "description",
                  json.string(
                    "Recall mode preset.
• semantic  — high-precision vector search (threshold=0.3)
• recent    — recency-biased, 1 hop (threshold=0.2)
• balanced  — engine defaults (no override)
• deep      — exhaustive graph traversal, 4 hops (threshold=0.1)",
                  ),
                ),
                #(
                  "enum",
                  precompiled_array([
                    json.string("semantic"),
                    json.string("recent"),
                    json.string("balanced"),
                    json.string("deep"),
                  ]),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "profile",
              json.object([
                #(
                  "description",
                  json.string(
                    "Traversal profile for BFS graph traversal. Leave unset for automatic inference from your context phrases.
• default       — balanced retrieval across all edge types; contradiction edges dampened (0.3×)
• causal        — follow cause/effect/dependency chains (Causes, DependsOn, Blocks, PrecededBy, FollowedBy)
• confirmatory  — find supporting evidence; contradiction edges excluded (Supports, Implements, Refines, References)
• adversarial   — surface conflicts and contradictions (Contradicts, Supersedes, Blocks; Contradicts boosted 1.5×)
• structural    — follow project/person/hierarchy edges (IsPartOf, BelongsToProject, CreatedByPerson)

When to specify explicitly:
  Use 'causal' when asking why something happened or what something depends on.
  Use 'adversarial' when auditing for inconsistencies or contradictions.
  Use 'confirmatory' when looking for supporting evidence for a claim.
  Use 'structural' when navigating project or organizational structure.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "since",
              json.object([
                #(
                  "description",
                  json.string(
                    "ISO 8601 timestamp (e.g. 2026-01-15T00:00:00Z). Only return memories created after this time.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "threshold",
              json.object([
                #(
                  "description",
                  json.string("Minimum relevance score 0.0-1.0 (default 0.5)."),
                ),
                #("type", json.string("number")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("context")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_read",
      description: "Fetch a single memory by its ID.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("Memory ID (ULID).")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_forget",
      description: "Soft-delete a memory. It remains recoverable but is excluded from recall.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("Memory ID to forget.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_link",
      description: "Create or strengthen an association between two memories.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "relation",
              json.object([
                #(
                  "description",
                  json.string(
                    "Type of relationship between the two memories. Choose the most specific type:
• supports          — this memory provides evidence or backing for the other
• contradicts       — this memory conflicts with or refutes the other
• depends_on        — this memory requires the other to be understood or true first
• supersedes        — this memory replaces or updates the other (other is now outdated)
• relates_to        — general association when no specific type fits (safe default)
• is_part_of        — this memory is a component or section of the other
• causes            — this memory is a cause or contributing factor to the other
• preceded_by       — this memory chronologically follows the other
• followed_by       — this memory chronologically precedes the other
• created_by_person — this memory was authored or owned by the person in the other
• belongs_to_project — this memory belongs to the project or context in the other
• references        — this memory cites or links to the other without strong semantic weight
• implements        — this memory is the concrete realization of the other (e.g. code for a spec)
• blocks            — this memory is an obstacle preventing progress on the other
• resolves          — this memory is the solution or fix for the other
• refines           — this memory is a near-duplicate refinement or correction of the other",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "source_id",
              json.object([
                #("description", json.string("Source memory ID.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "target_id",
              json.object([
                #("description", json.string("Target memory ID.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "weight",
              json.object([
                #(
                  "description",
                  json.string("Association weight 0.0-1.0 (default 0.8)."),
                ),
                #("type", json.string("number")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([
            json.string("source_id"),
            json.string("target_id"),
            json.string("relation"),
          ]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_contradictions",
      description: "Check for known contradictions in this vault.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_status",
      description: "Get health and capacity statistics for the vault.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_evolve",
      description: "Update a memory with new information. Creates a new version and archives the old one.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("ID of the memory to evolve.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "new_content",
              json.object([
                #("description", json.string("Updated information.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "reason",
              json.object([
                #(
                  "description",
                  json.string("Why this memory is being updated."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([
            json.string("id"),
            json.string("new_content"),
            json.string("reason"),
          ]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_consolidate",
      description: "Merge multiple related memories into one. Archives the originals. Maximum 50 IDs.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "ids",
              json.object([
                #(
                  "description",
                  json.string("IDs of memories to merge (max 50)."),
                ),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "merged_content",
              json.object([
                #(
                  "description",
                  json.string("Content for the consolidated memory."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("ids"), json.string("merged_content")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_session",
      description: "Get a summary of recent memory activity since a timestamp.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "since",
              json.object([
                #(
                  "description",
                  json.string(
                    "ISO 8601 timestamp. Return activity after this time.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("since")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_decide",
      description: "Record a decision with rationale and link it to supporting evidence.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "alternatives",
              json.object([
                #(
                  "description",
                  json.string("Other options that were considered."),
                ),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "decision",
              json.object([
                #("description", json.string("The decision made.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "evidence_ids",
              json.object([
                #(
                  "description",
                  json.string("Memory IDs that support this decision."),
                ),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "rationale",
              json.object([
                #("description", json.string("Reasoning behind the decision.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("decision"), json.string("rationale")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_restore",
      description: "Recover a soft-deleted memory within the 7-day recovery window. Use when you realize a memory was deleted by mistake. Returns the restored memory's state.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #(
                  "description",
                  json.string("ID of the deleted memory to restore."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_traverse",
      description: "Explore the memory graph by following associations from a starting memory. Use when you want to discover related memories structurally rather than by semantic search. Returns nodes and edges within the specified hop distance.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "follow_entities",
              json.object([
                #(
                  "description",
                  json.string(
                    "When true, the BFS also traverses through shared entity links (e.g. two memories that both mention 'PostgreSQL' are connected even without a direct association). Entity-hop edges are assigned a lower weight (0.1) than direct association edges. Default false.",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "max_hops",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum BFS depth from the starting node (default 2, max 5).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "max_nodes",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum number of memories to return (default 20, max 100).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "rel_types",
              json.object([
                #(
                  "description",
                  json.string(
                    "Optional: filter to specific relation types (e.g. [\"depends_on\", \"supports\"]).",
                  ),
                ),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "start_id",
              json.object([
                #("description", json.string("ID of the memory to start from.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("start_id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_explain",
      description: "Show the full score breakdown for why a specific memory would be returned for a given query. Use for debugging recall quality — to understand why a memory ranked high or low.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "engram_id",
              json.object([
                #(
                  "description",
                  json.string("ID of the memory to score-explain."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "query",
              json.object([
                #(
                  "description",
                  json.string(
                    "Context phrases to evaluate against (same format as muninn_recall context).",
                  ),
                ),
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("engram_id"), json.string("query")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_state",
      description: "Transition a memory's lifecycle state. Use to mark work as active, completed, paused, blocked, or archived. Valid states: planning, active, paused, blocked, completed, cancelled, archived.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("ID of the memory to update.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "reason",
              json.object([
                #(
                  "description",
                  json.string("Optional: why the state is being changed."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "state",
              json.object([
                #("description", json.string("The new lifecycle state.")),
                #(
                  "enum",
                  precompiled_array([
                    json.string("planning"),
                    json.string("active"),
                    json.string("paused"),
                    json.string("blocked"),
                    json.string("completed"),
                    json.string("cancelled"),
                    json.string("archived"),
                  ]),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("id"), json.string("state")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_list_deleted",
      description: "List soft-deleted memories that are still within the 7-day recovery window. Use before calling muninn_restore to find what can be recovered.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string("Max results to return (default 20, max 100)."),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_retry_enrich",
      description: "Re-queue a memory for enrichment processing by active plugins (e.g. embedding or LLM summarization) that have not yet completed. Use when a memory was stored before a plugin was activated.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("ID of the memory to re-enrich.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_guide",
      description: "Get instructions on how to use MuninnDB effectively. Call this when you first connect or need a reminder of available capabilities and best practices.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_where_left_off",
      description: "Surface what was being worked on at the end of the last session. Returns the most recently accessed active memories, sorted by recency. Call this at session start to orient yourself before any user queries.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string("Max memories to return (default 10, max 50)."),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_find_by_entity",
      description: "Return all memories that mention a given named entity. Uses the entity reverse index for fast O(matches) lookup.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "entity_name",
              json.object([
                #(
                  "description",
                  json.string(
                    "The entity name to look up (e.g. 'PostgreSQL', 'Alice')",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #("description", json.string("Max results (1-50, default 20)")),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("entity_name")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_entity_state",
      description: "Set the lifecycle state of a named entity (active, deprecated, merged, resolved). For state=merged, provide merged_into with the canonical entity name.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "entity_name",
              json.object([
                #("description", json.string("The entity name to update")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "merged_into",
              json.object([
                #(
                  "description",
                  json.string(
                    "Canonical entity name (required when state=merged)",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "state",
              json.object([
                #(
                  "description",
                  json.string(
                    "New state: active, deprecated, merged, or resolved",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("entity_name"), json.string("state")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_remember_tree",
      description: "Store a nested hierarchy (project plan, task tree, outline) as a collection of linked engrams. Each node becomes a full engram with cognitive properties. Children are ordered by their position in the tree. Returns root_id and a node_map for future reference.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "root",
              json.object([
                #(
                  "description",
                  json.string(
                    "The root node of the tree. Each node may have a 'children' array for nesting.",
                  ),
                ),
                #(
                  "properties",
                  json.object([
                    #(
                      "capability_token",
                      json.object([
                        #(
                          "description",
                          json.string(
                            "The capability token validating this action.",
                          ),
                        ),
                        #("type", json.string("string")),
                      ]),
                    ),
                    #(
                      "children",
                      json.object([
                        #(
                          "description",
                          json.string("Child nodes (same schema, recursive)."),
                        ),
                        #(
                          "items",
                          json.object([
                            #(
                              "properties",
                              json.object([
                                #(
                                  "capability_token",
                                  json.object([
                                    #(
                                      "description",
                                      json.string(
                                        "The capability token validating this action.",
                                      ),
                                    ),
                                    #("type", json.string("string")),
                                  ]),
                                ),
                                #(
                                  "children",
                                  json.object([
                                    #(
                                      "description",
                                      json.string("Child nodes (recursive)."),
                                    ),
                                    #(
                                      "items",
                                      json.object([
                                        #(
                                          "description",
                                          json.string("Nested child node."),
                                        ),
                                        #(
                                          "properties",
                                          json.object([
                                            #(
                                              "capability_token",
                                              json.object([
                                                #(
                                                  "description",
                                                  json.string(
                                                    "The capability token validating this action.",
                                                  ),
                                                ),
                                                #("type", json.string("string")),
                                              ]),
                                            ),
                                            #(
                                              "children",
                                              json.object([
                                                #(
                                                  "description",
                                                  json.string(
                                                    "Further nested children.",
                                                  ),
                                                ),
                                                #(
                                                  "items",
                                                  json.object([
                                                    #(
                                                      "description",
                                                      json.string(
                                                        "Deeply nested child node.",
                                                      ),
                                                    ),
                                                    #(
                                                      "properties",
                                                      json.object([
                                                        #(
                                                          "capability_token",
                                                          json.object([
                                                            #(
                                                              "description",
                                                              json.string(
                                                                "The capability token validating this action.",
                                                              ),
                                                            ),
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "string",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                        #(
                                                          "children",
                                                          json.object([
                                                            #(
                                                              "description",
                                                              json.string(
                                                                "Deeper nesting - allows arbitrary depth.",
                                                              ),
                                                            ),
                                                            #(
                                                              "items",
                                                              json.object([]),
                                                            ),
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "array",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                        #(
                                                          "concept",
                                                          json.object([
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "string",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                        #(
                                                          "content",
                                                          json.object([
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "string",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                        #(
                                                          "tags",
                                                          json.object([
                                                            #(
                                                              "items",
                                                              json.object([
                                                                #(
                                                                  "type",
                                                                  json.string(
                                                                    "string",
                                                                  ),
                                                                ),
                                                              ]),
                                                            ),
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "array",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                        #(
                                                          "type",
                                                          json.object([
                                                            #(
                                                              "type",
                                                              json.string(
                                                                "string",
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                      ]),
                                                    ),
                                                    #(
                                                      "type",
                                                      json.string("object"),
                                                    ),
                                                  ]),
                                                ),
                                                #("type", json.string("array")),
                                              ]),
                                            ),
                                            #(
                                              "concept",
                                              json.object([
                                                #(
                                                  "description",
                                                  json.string("Short label."),
                                                ),
                                                #("type", json.string("string")),
                                              ]),
                                            ),
                                            #(
                                              "content",
                                              json.object([
                                                #(
                                                  "description",
                                                  json.string("Content."),
                                                ),
                                                #("type", json.string("string")),
                                              ]),
                                            ),
                                            #(
                                              "tags",
                                              json.object([
                                                #(
                                                  "items",
                                                  json.object([
                                                    #(
                                                      "type",
                                                      json.string("string"),
                                                    ),
                                                  ]),
                                                ),
                                                #("type", json.string("array")),
                                              ]),
                                            ),
                                            #(
                                              "type",
                                              json.object([
                                                #(
                                                  "description",
                                                  json.string("Memory type."),
                                                ),
                                                #("type", json.string("string")),
                                              ]),
                                            ),
                                          ]),
                                        ),
                                        #("type", json.string("object")),
                                      ]),
                                    ),
                                    #("type", json.string("array")),
                                  ]),
                                ),
                                #(
                                  "concept",
                                  json.object([
                                    #(
                                      "description",
                                      json.string("Short label for this node."),
                                    ),
                                    #("type", json.string("string")),
                                  ]),
                                ),
                                #(
                                  "content",
                                  json.object([
                                    #(
                                      "description",
                                      json.string("Content for this node."),
                                    ),
                                    #("type", json.string("string")),
                                  ]),
                                ),
                                #(
                                  "tags",
                                  json.object([
                                    #(
                                      "items",
                                      json.object([
                                        #("type", json.string("string")),
                                      ]),
                                    ),
                                    #("type", json.string("array")),
                                  ]),
                                ),
                                #(
                                  "type",
                                  json.object([
                                    #(
                                      "description",
                                      json.string(
                                        "Memory type (goal, task, etc.).",
                                      ),
                                    ),
                                    #("type", json.string("string")),
                                  ]),
                                ),
                              ]),
                            ),
                            #(
                              "required",
                              precompiled_array([
                                json.string("concept"),
                                json.string("content"),
                              ]),
                            ),
                            #("type", json.string("object")),
                          ]),
                        ),
                        #("type", json.string("array")),
                      ]),
                    ),
                    #(
                      "concept",
                      json.object([
                        #(
                          "description",
                          json.string("Short label for this node."),
                        ),
                        #("type", json.string("string")),
                      ]),
                    ),
                    #(
                      "content",
                      json.object([
                        #("description", json.string("Content for this node.")),
                        #("type", json.string("string")),
                      ]),
                    ),
                    #(
                      "tags",
                      json.object([
                        #(
                          "items",
                          json.object([#("type", json.string("string"))]),
                        ),
                        #("type", json.string("array")),
                      ]),
                    ),
                    #(
                      "type",
                      json.object([
                        #(
                          "description",
                          json.string("Memory type (goal, task, etc.)."),
                        ),
                        #("type", json.string("string")),
                      ]),
                    ),
                  ]),
                ),
                #(
                  "required",
                  precompiled_array([
                    json.string("concept"),
                    json.string("content"),
                  ]),
                ),
                #("type", json.string("object")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("root")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_recall_tree",
      description: "Retrieve the complete, ordered hierarchy rooted at root_id. Returns all nodes in their original structured order, with state and metadata at each level. Use after muninn_recall finds the root engram's ID.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "include_completed",
              json.object([
                #(
                  "description",
                  json.string(
                    "Include completed nodes and their subtrees (default: true).",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string(
                    "Max children per node per level. 0 = no limit (default: 0).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "max_depth",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum recursion depth. 0 = unlimited (default: 10).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "root_id",
              json.object([
                #("description", json.string("ULID of the root engram.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("root_id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_entity_clusters",
      description: "Return entity pairs that frequently co-occur in the same memories. Uses the co-occurrence index for fast O(pairs) lookup. Useful for discovering implicit relationships between entities.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "min_count",
              json.object([
                #(
                  "description",
                  json.string(
                    "Minimum co-occurrence count to include a pair (default 2).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "top_n",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum number of entity pairs to return, sorted by count descending (default 20).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_export_graph",
      description: "Export the entity relationship graph for a vault as JSON-LD or GraphML. Nodes are named entities; edges are typed entity-to-entity relationships extracted from memories. Useful for visualisation, graph analysis, or knowledge-base integration.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "format",
              json.object([
                #(
                  "description",
                  json.string(
                    "Output format: 'json-ld' (default) or 'graphml'.",
                  ),
                ),
                #(
                  "enum",
                  precompiled_array([
                    json.string("json-ld"),
                    json.string("graphml"),
                  ]),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "include_engrams",
              json.object([
                #(
                  "description",
                  json.string(
                    "When true, entity types are enriched from the entity record table (default false).",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_add_child",
      description: "Add a single child node to an existing parent in a tree. Writes the engram and wires the is_part_of association and ordinal key. Use for incremental tree updates without resending the whole tree.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "concept",
              json.object([
                #("description", json.string("Short label for the new child.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "content",
              json.object([
                #("description", json.string("Content for the new child.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "ordinal",
              json.object([
                #(
                  "description",
                  json.string(
                    "Explicit ordinal position. Omit to append at end.",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "parent_id",
              json.object([
                #("description", json.string("ULID of the parent engram.")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "tags",
              json.object([
                #("items", json.object([#("type", json.string("string"))])),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "type",
              json.object([
                #("description", json.string("Memory type (task, goal, etc.).")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([
            json.string("parent_id"),
            json.string("concept"),
            json.string("content"),
          ]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_similar_entities",
      description: "Find entity names in a vault that are likely duplicates based on trigram similarity. Returns pairs of similar names that may need merging. Use muninn_merge_entity to merge confirmed duplicates.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "threshold",
              json.object([
                #(
                  "description",
                  json.string(
                    "Minimum similarity score 0.0-1.0 to include a pair (default 0.85).",
                  ),
                ),
                #("type", json.string("number")),
              ]),
            ),
            #(
              "top_n",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum number of similar pairs to return, sorted by similarity descending (default 20).",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_merge_entity",
      description: "Merge entity_a into entity_b (canonical). Sets entity_a state to merged, relinks all engrams in the vault from entity_a to entity_b, and updates entity_b mention count. Use dry_run=true to preview the operation without writing.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "dry_run",
              json.object([
                #(
                  "description",
                  json.string(
                    "When true, report what would happen without writing any data (default false).",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "entity_a",
              json.object([
                #(
                  "description",
                  json.string(
                    "The entity name to be merged away (becomes state=merged).",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "entity_b",
              json.object([
                #(
                  "description",
                  json.string("The canonical entity name to keep."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #(
          "required",
          precompiled_array([json.string("entity_a"), json.string("entity_b")]),
        ),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_replay_enrichment",
      description: "Re-run the enrichment pipeline for memories in a vault that are missing specific digest stages (entities, relationships, classification, summary). Use this to retroactively enrich memories that were stored before an LLM provider was configured, or to fill in specific pipeline stages that were skipped. Supports dry_run=true to preview what would be processed without writing.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "dry_run",
              json.object([
                #(
                  "description",
                  json.string(
                    "When true, scan and count how many memories would be enriched without actually running enrichment. Use to gauge scope before committing (default false).",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string(
                    "Maximum number of memories to process in this call (default 50, max 200). Use multiple calls to process larger vaults incrementally.",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "stages",
              json.object([
                #(
                  "description",
                  json.string(
                    "Which enrichment stages to re-run. Defaults to all four: entities, relationships, classification, summary. Only memories missing these stages will be processed.",
                  ),
                ),
                #(
                  "items",
                  json.object([
                    #(
                      "enum",
                      precompiled_array([
                        json.string("entities"),
                        json.string("relationships"),
                        json.string("classification"),
                        json.string("summary"),
                      ]),
                    ),
                    #("type", json.string("string")),
                  ]),
                ),
                #("type", json.string("array")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_provenance",
      description: "Returns the ordered audit trail for an engram — who wrote it, what changed, and why.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "id",
              json.object([
                #("description", json.string("Engram ID (ULID).")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_entity_timeline",
      description: "Return a chronological view of when an entity first appeared in memory and how it has evolved. Shows all engrams mentioning the entity, sorted by creation time (oldest first).",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "entity_name",
              json.object([
                #(
                  "description",
                  json.string(
                    "The entity name to look up (e.g. 'PostgreSQL', 'Alice')",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string(
                    "Max timeline entries to return (1-50, default 10)",
                  ),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("entity_name")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_feedback",
      description: "Record explicit feedback on an engram. Use useful=false when a retrieved engram was not helpful. Updates the vault's learned scoring weights via SGD.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "engram_id",
              json.object([
                #("description", json.string("Engram ID that was retrieved")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "useful",
              json.object([
                #(
                  "description",
                  json.string(
                    "Whether the engram was helpful (default false = negative signal)",
                  ),
                ),
                #("type", json.string("boolean")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("engram_id")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_entity",
      description: "Returns the full aggregate view for a named entity: metadata, engrams mentioning it, relationships, and co-occurring entities.",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #(
                  "description",
                  json.string("Max engrams to include (default 20)"),
                ),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "name",
              json.object([
                #("description", json.string("Entity name (case-insensitive)")),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([json.string("name")])),
        #("type", json.string("object")),
      ]),
    ),
    Tool(
      name: "muninn_entities",
      description: "Lists all known entities in a vault, sorted by mention count. Optionally filter by state (active, deprecated, merged, resolved).",
      input_schema: json.object([
        #(
          "properties",
          json.object([
            #(
              "capability_token",
              json.object([
                #(
                  "description",
                  json.string("The capability token validating this action."),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "limit",
              json.object([
                #("description", json.string("Max results (default 50)")),
                #("type", json.string("integer")),
              ]),
            ),
            #(
              "state",
              json.object([
                #(
                  "description",
                  json.string(
                    "Filter by state: active, deprecated, merged, resolved",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
            #(
              "vault",
              json.object([
                #(
                  "description",
                  json.string(
                    "Vault name to scope the operation (default: 'default'). Optional when connected via a vault-pinned MCP session.",
                  ),
                ),
                #("type", json.string("string")),
              ]),
            ),
          ]),
        ),
        #("required", precompiled_array([])),
        #("type", json.string("object")),
      ]),
    ),
  ]
}
