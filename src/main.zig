//! CLI demo: build a small agent context graph, run BFS, emit JSON.
const std = @import("std");
const graph = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var g = graph.Graph.init(allocator);
    defer g.deinit();

    // Build a small agent context graph:
    //
    //   agent --uses--------> mcp.search-tool
    //   agent --uses--------> mcp.kb-lookup
    //   mcp.search-tool --produces---> fact:cve-2026-001
    //   mcp.kb-lookup   --references-> citation:nist-sp-800-53
    //   fact:cve-2026-001 --supports--> result:risk-score:high
    const a = try g.addNode("agent:incident-triage", .agent);
    const t1 = try g.addNode("mcp.search-tool", .tool);
    const t2 = try g.addNode("mcp.kb-lookup", .tool);
    const f1 = try g.addNode("cve-2026-001", .fact);
    const c1 = try g.addNode("nist-sp-800-53", .citation);
    const r1 = try g.addNode("risk-score:high", .result);

    _ = try g.addEdge(a, t1, "uses");
    _ = try g.addEdge(a, t2, "uses");
    _ = try g.addEdge(t1, f1, "produces");
    _ = try g.addEdge(t2, c1, "references");
    _ = try g.addEdge(f1, r1, "supports");

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "agent_graph_db: {d} nodes, {d} edges\n",
        .{ g.nodeCount(), g.edgeCount() },
    );

    const order = try g.bfs(a, allocator);
    defer allocator.free(order);

    try stdout.writeAll("\nBFS order from agent:\n");
    for (order) |id| {
        const node = g.nodes.get(id).?;
        try stdout.print("  [{s}] {s}\n", .{ node.kind.toString(), node.label });
    }

    try stdout.writeAll("\nJSON serialization:\n");
    try g.toJson(stdout);
    try stdout.writeAll("\n");
}

test "main module compiles with library import" {
    const allocator = std.testing.allocator;
    var g = graph.Graph.init(allocator);
    defer g.deinit();
    _ = try g.addNode("test", .agent);
    try std.testing.expectEqual(@as(usize, 1), g.nodeCount());
}
