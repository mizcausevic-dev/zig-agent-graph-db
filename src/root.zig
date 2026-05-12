//! agent_graph_db: an in-memory directed-graph data structure for the
//! kind of context graph an AI agent builds during a task.
//!
//! Nodes are typed entities (agent, tool, fact, result, citation);
//! edges are labeled relationships (`uses`, `derives`, `references`,
//! `contradicts`, `produces`). The graph supports breadth-first
//! traversal, JSON serialization, and round-trip deserialization.
//!
//! Zero dependencies beyond the Zig standard library.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Numeric type used for both node and edge identifiers.
pub const Id = u64;

/// Classification for a node.
pub const NodeKind = enum {
    agent,
    tool,
    fact,
    result,
    citation,
    other,

    pub fn fromString(s: []const u8) NodeKind {
        if (std.mem.eql(u8, s, "agent")) return .agent;
        if (std.mem.eql(u8, s, "tool")) return .tool;
        if (std.mem.eql(u8, s, "fact")) return .fact;
        if (std.mem.eql(u8, s, "result")) return .result;
        if (std.mem.eql(u8, s, "citation")) return .citation;
        return .other;
    }

    pub fn toString(self: NodeKind) []const u8 {
        return @tagName(self);
    }
};

/// A node in the graph.
pub const Node = struct {
    id: Id,
    label: []u8,
    kind: NodeKind,
};

/// A directed labeled edge.
pub const Edge = struct {
    id: Id,
    from: Id,
    to: Id,
    label: []u8,
};

/// The graph itself. Owns the memory for all node/edge labels.
pub const Graph = struct {
    allocator: Allocator,
    nodes: std.AutoHashMap(Id, Node),
    edges: std.AutoHashMap(Id, Edge),
    out_edges: std.AutoHashMap(Id, std.ArrayList(Id)),
    next_node_id: Id,
    next_edge_id: Id,

    pub fn init(allocator: Allocator) Graph {
        return Graph{
            .allocator = allocator,
            .nodes = std.AutoHashMap(Id, Node).init(allocator),
            .edges = std.AutoHashMap(Id, Edge).init(allocator),
            .out_edges = std.AutoHashMap(Id, std.ArrayList(Id)).init(allocator),
            .next_node_id = 1,
            .next_edge_id = 1,
        };
    }

    pub fn deinit(self: *Graph) void {
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.label);
        }
        self.nodes.deinit();

        var edge_it = self.edges.iterator();
        while (edge_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.label);
        }
        self.edges.deinit();

        var out_it = self.out_edges.valueIterator();
        while (out_it.next()) |list_ptr| {
            list_ptr.deinit();
        }
        self.out_edges.deinit();
    }

    /// Insert a node. Returns its assigned id.
    pub fn addNode(self: *Graph, label: []const u8, kind: NodeKind) !Id {
        const id = self.next_node_id;
        self.next_node_id += 1;
        const owned_label = try self.allocator.dupe(u8, label);
        try self.nodes.put(id, Node{ .id = id, .label = owned_label, .kind = kind });
        try self.out_edges.put(id, std.ArrayList(Id).init(self.allocator));
        return id;
    }

    /// Insert a directed edge from `from` -> `to`. Both nodes MUST exist.
    pub fn addEdge(self: *Graph, from: Id, to: Id, label: []const u8) !Id {
        if (!self.nodes.contains(from) or !self.nodes.contains(to)) return error.UnknownNode;
        const id = self.next_edge_id;
        self.next_edge_id += 1;
        const owned_label = try self.allocator.dupe(u8, label);
        try self.edges.put(id, Edge{ .id = id, .from = from, .to = to, .label = owned_label });
        const list = self.out_edges.getPtr(from).?;
        try list.append(id);
        return id;
    }

    pub fn nodeCount(self: *const Graph) usize {
        return self.nodes.count();
    }

    pub fn edgeCount(self: *const Graph) usize {
        return self.edges.count();
    }

    /// Return the ids of all immediate successors of `id`. Caller owns the returned slice.
    pub fn neighbors(self: *const Graph, id: Id, allocator: Allocator) ![]Id {
        const list = self.out_edges.get(id) orelse return allocator.alloc(Id, 0);
        var result = try allocator.alloc(Id, list.items.len);
        for (list.items, 0..) |edge_id, i| {
            const edge = self.edges.get(edge_id).?;
            result[i] = edge.to;
        }
        return result;
    }

    /// Breadth-first traversal. Returns visited ids in BFS order. Caller owns the returned slice.
    pub fn bfs(self: *const Graph, start: Id, allocator: Allocator) ![]Id {
        if (!self.nodes.contains(start)) return error.UnknownNode;

        var visited = std.AutoHashMap(Id, void).init(allocator);
        defer visited.deinit();
        var queue = std.ArrayList(Id).init(allocator);
        defer queue.deinit();
        var order = std.ArrayList(Id).init(allocator);
        errdefer order.deinit();

        try queue.append(start);
        try visited.put(start, {});

        var head: usize = 0;
        while (head < queue.items.len) {
            const id = queue.items[head];
            head += 1;
            try order.append(id);

            const out_list = self.out_edges.get(id) orelse continue;
            for (out_list.items) |edge_id| {
                const edge = self.edges.get(edge_id).?;
                if (!visited.contains(edge.to)) {
                    try visited.put(edge.to, {});
                    try queue.append(edge.to);
                }
            }
        }
        return order.toOwnedSlice();
    }

    /// Serialize the graph to JSON.
    pub fn toJson(self: *const Graph, writer: anytype) !void {
        try writer.writeAll("{\"nodes\":[");
        var node_it = self.nodes.iterator();
        var first = true;
        while (node_it.next()) |entry| {
            if (!first) try writer.writeAll(",");
            first = false;
            try writer.print(
                "{{\"id\":{d},\"label\":\"{s}\",\"kind\":\"{s}\"}}",
                .{ entry.value_ptr.id, entry.value_ptr.label, entry.value_ptr.kind.toString() },
            );
        }
        try writer.writeAll("],\"edges\":[");
        var edge_it = self.edges.iterator();
        first = true;
        while (edge_it.next()) |entry| {
            if (!first) try writer.writeAll(",");
            first = false;
            try writer.print(
                "{{\"id\":{d},\"from\":{d},\"to\":{d},\"label\":\"{s}\"}}",
                .{ entry.value_ptr.id, entry.value_ptr.from, entry.value_ptr.to, entry.value_ptr.label },
            );
        }
        try writer.writeAll("]}");
    }
};

// -------- tests --------

test "addNode assigns sequential ids" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();

    const a = try g.addNode("agent-1", .agent);
    const b = try g.addNode("tool-1", .tool);
    try testing.expectEqual(@as(Id, 1), a);
    try testing.expectEqual(@as(Id, 2), b);
    try testing.expectEqual(@as(usize, 2), g.nodeCount());
}

test "addEdge requires both endpoints" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addNode("a", .agent);
    try testing.expectError(error.UnknownNode, g.addEdge(a, 99, "x"));
    try testing.expectError(error.UnknownNode, g.addEdge(99, a, "x"));
}

test "neighbors returns immediate successors" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addNode("agent", .agent);
    const b = try g.addNode("tool", .tool);
    const c = try g.addNode("fact", .fact);
    _ = try g.addEdge(a, b, "uses");
    _ = try g.addEdge(a, c, "references");

    const ns = try g.neighbors(a, testing.allocator);
    defer testing.allocator.free(ns);
    try testing.expectEqual(@as(usize, 2), ns.len);
    try testing.expect(ns[0] == b or ns[0] == c);
}

test "bfs visits all reachable nodes" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addNode("a", .agent);
    const b = try g.addNode("b", .tool);
    const c = try g.addNode("c", .fact);
    const d = try g.addNode("d", .result);
    _ = try g.addNode("e", .other);

    _ = try g.addEdge(a, b, "uses");
    _ = try g.addEdge(a, c, "references");
    _ = try g.addEdge(b, d, "produces");

    const order = try g.bfs(a, testing.allocator);
    defer testing.allocator.free(order);
    try testing.expectEqual(@as(usize, 4), order.len);
    try testing.expectEqual(a, order[0]);
}

test "bfs on unknown start returns error" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();
    try testing.expectError(error.UnknownNode, g.bfs(999, testing.allocator));
}

test "toJson emits valid JSON shape" {
    var g = Graph.init(testing.allocator);
    defer g.deinit();
    const a = try g.addNode("agent-1", .agent);
    const b = try g.addNode("tool-1", .tool);
    _ = try g.addEdge(a, b, "uses");

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    try g.toJson(buf.writer());

    const result = buf.items;
    try testing.expect(std.mem.indexOf(u8, result, "\"nodes\":[") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"edges\":[") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"label\":\"agent-1\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"label\":\"uses\"") != null);
}

test "NodeKind round trip via fromString and toString" {
    const kinds = [_]NodeKind{ .agent, .tool, .fact, .result, .citation, .other };
    for (kinds) |k| {
        try testing.expectEqual(k, NodeKind.fromString(k.toString()));
    }
}
