# zig-agent-graph-db

An in-memory directed-graph data structure in **Zig**, designed for the kind of context graph an AI agent builds during a task: nodes are typed entities (agent, tool, fact, result, citation), edges are labeled relationships (`uses`, `produces`, `references`, `supports`, `contradicts`).

Zero dependencies beyond the Zig standard library. Compiles to a tiny native binary (about 200 KB stripped on Linux x86_64).

## Why a custom graph?

General-purpose graph libraries are overpowered for the working memory of a single agent task. This crate stays small, owns its memory, and exposes only the operations an agent actually needs:

- `addNode(label, kind) -> id` — entity insertion
- `addEdge(from, to, label) -> id` — labeled relationship
- `neighbors(id) -> []id` — immediate successors
- `bfs(start) -> []id` — full traversal order
- `toJson(writer)` — durable serialization

`NodeKind` is a closed enum (`agent`, `tool`, `fact`, `result`, `citation`, `other`) so traversal code can branch cleanly without a string match.

## Quickstart

```bash
zig build run
```

Output:

```
agent_graph_db: 6 nodes, 5 edges

BFS order from agent:
  [agent] agent:incident-triage
  [tool] mcp.search-tool
  [tool] mcp.kb-lookup
  [fact] cve-2026-001
  [citation] nist-sp-800-53
  [result] risk-score:high

JSON serialization:
{"nodes":[...],"edges":[...]}
```

That's a complete agent reasoning trace: agent invoked two tools, each tool produced one downstream node, and a derived `result` node was supported by one of the facts.

## Library usage

```zig
const graph = @import("zig-agent-graph-db");

var g = graph.Graph.init(allocator);
defer g.deinit();

const agent = try g.addNode("agent:foo", .agent);
const tool = try g.addNode("mcp.search", .tool);
const fact = try g.addNode("fact:x", .fact);
_ = try g.addEdge(agent, tool, "uses");
_ = try g.addEdge(tool, fact, "produces");

const order = try g.bfs(agent, allocator);
defer allocator.free(order);
// order is [agent, tool, fact]
```

## Tests

Seven unit tests cover:

- `addNode` assigns sequential ids and counts nodes correctly
- `addEdge` returns `error.UnknownNode` when either endpoint is missing
- `neighbors(id)` returns all immediate successors
- `bfs(start)` visits all reachable nodes; unreachable nodes are not included
- `bfs(unknown_id)` returns `error.UnknownNode`
- `toJson` emits a structure containing both `nodes` and `edges` arrays with the expected labels
- `NodeKind.fromString` and `NodeKind.toString` round-trip cleanly for every variant

```bash
zig build test --summary all
```

## Build artifacts

| Mode | Approximate size |
|---|---|
| `zig build` (debug) | ~500 KB |
| `zig build -Doptimize=ReleaseSafe` | ~250 KB |
| `zig build -Doptimize=ReleaseSmall` | ~80 KB |

## Memory ownership

The graph owns every node label and edge label allocation. `deinit()` frees all of them. Caller-allocated slices returned by `neighbors()` and `bfs()` are caller-owned — free with the same allocator you passed.

## Roadmap

- DFS in addition to BFS
- Reverse edges / `predecessors(id)`
- JSON `fromJson` (parse) — currently only `toJson` (serialize) is implemented
- Shortest path between two nodes (Dijkstra over uniform edges)

## License

AGPL-3.0.

---

**Connect:** [LinkedIn](https://www.linkedin.com/in/mirzacausevic/) · [Kinetic Gain](https://kineticgain.com) · [Medium](https://medium.com/@mizcausevic/) · [Skills](https://mizcausevic.com/skills/)
