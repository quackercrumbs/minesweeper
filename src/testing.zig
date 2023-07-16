const std = @import("std");
const testing = std.testing;

// Exists purely to learn more about Zig syntax and Zig Std

test "test random shuffle" {
    var list = try std.ArrayList(i32).initCapacity(std.testing.allocator, 10);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!

    var n: i32 = 0;
    while (n < 10) : (n += 1) {
        try list.append(n);
    }

    var rng = std.rand.DefaultPrng.init(2);
    const random = rng.random();
    std.rand.Random.shuffle(random, i32, list.items);

    std.debug.print("hello\n", .{});
    for (list.items, 0..) |item, i| {
        std.debug.print("{any} {any}\n", .{ i, item });
    }

    // try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "arrays" {
    // var indexes = try get_neighboring_indexes(3, 3, CoordinatePair{ .x = 1, .y = 1 });
    // std.debug.print("\narrays: {any}\n", .{indexes});
}

test "queue" {
    const L = std.DoublyLinkedList(usize);
    var list = L{};

    for (0..5) |i| {
        var node_ptr = try std.testing.allocator.create(L.Node);
        node_ptr.data = i;
        list.prepend(node_ptr);
    }

    {
        var it = list.first;
        var index: usize = 1;
        while (it) |node| : (it = node.next) {
            std.debug.print("{}\n", .{node.data});
            //try testing.expect(node.data == index);
            index += 1;
        }
    }

    {
        while (list.len != 0) {
            var node = list.popFirst().?;
            std.testing.allocator.destroy(node);
        }
    }
}
