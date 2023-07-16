const std = @import("std");

const CoordinatePair = struct {
    x: usize,
    y: usize,
};

const Op = enum {
    increase,
    decrease,
    zero,
};

const State = enum {
    closed,
    open,
    // TODO: add remaining states (flagged?)
};

const Cell = struct {
    state: State,
    is_mine: bool,
    // Number of edges determines max number of mines surrounding a cell
    // This can be determined at run time, but we can cache this value
    // during the board game is initialized
    neighoring_mines: u8,
};

const GameResult = enum { undetermined, win, lost };

const Game = struct {
    allocator: std.mem.Allocator,
    // TODO: use Cell and State
    board: std.ArrayList(Cell),
    x_size: u32, // horizontal screen
    y_size: u32, // vertical screen
    num_mines: u64, // total number of mines
    remaining_cells: u64,

    result: GameResult,

    pub fn init_easy(allocator: std.mem.Allocator, seed: u64, x_size: u32, y_size: u32, num_mines: u64) !Game {
        const grid_size = x_size * y_size;
        const num_cells = x_size * y_size;
        var board = try std.ArrayList(Cell).initCapacity(allocator, x_size * grid_size);
        for (0..grid_size) |_| {
            try board.append(Cell{
                .state = State.closed,
                .is_mine = false,
                .neighoring_mines = 0,
            });
        }

        // Spawn mines
        // TODO: this feels wildly inefficient lol
        //
        // Shuffle the locations and take the first n to determine mine locations
        var locations = try std.ArrayList(usize).initCapacity(allocator, grid_size);
        defer locations.deinit();
        var n: usize = 0;
        while (n < grid_size) : (n += 1) {
            try locations.append(n);
        }
        var rng = std.rand.DefaultPrng.init(seed);
        const random = rng.random();
        std.rand.Random.shuffle(random, usize, locations.items);

        // Take the mine locations and update the board
        for (locations.items[0..num_mines]) |index| {
            board.items[index].is_mine = true;

            const coordinate = try index_to_coordinate(x_size, y_size, index);

            // increment neighboring cells
            const surrounding_indexes = try get_surrounding_indexes(x_size, y_size, coordinate);
            for (0..surrounding_indexes.size) |i| {
                var neighbor_cell = &board.items[surrounding_indexes.neighbors[i]];
                neighbor_cell.neighoring_mines += 1;
            }
        }

        return Game{ .allocator = allocator, .board = board, .x_size = x_size, .y_size = y_size, .num_mines = num_mines, .remaining_cells = (num_cells - num_mines), .result = GameResult.undetermined };
    }

    pub fn deinit(self: Game) void {
        self.board.deinit();
    }

    pub fn debug_print(self: Game) void {
        std.debug.print("----- Board -----\n", .{});
        std.debug.print("Result: {} Remaining Cells:{}\n", .{ self.result, self.remaining_cells });
        for (0..self.y_size) |y| {
            const start = y * self.x_size;
            const end = start + self.x_size;
            for (start..end) |pos| {
                const cell = self.board.items[pos];
                // TODO: clean up this printing
                if (cell.is_mine and self.result == GameResult.lost) {
                    std.debug.print("{u:3}", .{'X'});
                } else if (cell.state == State.open and cell.neighoring_mines > 0) {
                    std.debug.print("{d:3}", .{
                        cell.neighoring_mines,
                    });
                } else if (cell.state == State.open) {
                    std.debug.print("{u:3}", .{
                        'O',
                    });
                } else {
                    std.debug.print("{u:3}", .{
                        '_',
                    });
                }
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("----------------\n", .{});
    }

    pub fn debug_print_neighboring_mine_counts(self: Game) void {
        std.debug.print("----- Mine Count -----\n", .{});
        for (0..self.y_size) |y| {
            const start = y * self.x_size;
            const end = start + self.x_size;
            for (start..end) |pos| {
                const cell = self.board.items[pos];
                std.debug.print("{:3}", .{
                    cell.neighoring_mines,
                });
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("----------------\n", .{});
    }
    pub fn debug_print_mines(self: Game) void {
        std.debug.print("----- Mine -----\n", .{});
        for (0..self.y_size) |y| {
            const start = y * self.x_size;
            const end = start + self.x_size;
            for (start..end) |pos| {
                const cell = self.board.items[pos];
                const symbol: u8 = if (cell.is_mine)
                    'x'
                else
                    'o';

                // TODO: print mine marker
                std.debug.print("{u:3}", .{
                    symbol,
                });
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("----------------\n", .{});
    }

    pub fn open(self: *Game, target: CoordinatePair) !void {
        if (self.result != GameResult.undetermined) {
            // reached end state already
            return;
        }

        const target_index = coordinate_to_index(self.x_size, self.y_size, target);
        var cell = &self.board.items[target_index];
        if (cell.state == State.open) {
            // Nothing to do, cell is already open
            return;
        }

        if (cell.is_mine) {
            // Game is a lost.
            self.openCell(cell);
            self.result = GameResult.lost;
            return;
        } else {
            try revealCells(self, target_index);
            if (self.remaining_cells == 0) {
                self.result = GameResult.win;
            }
        }
    }

    fn openCell(self: *Game, cell: *Cell) void {
        if (cell.state == State.closed and !cell.is_mine) {
            self.remaining_cells -= 1;
        }
        cell.state = State.open;
    }

    fn revealCells(self: *Game, start_index: usize) !void {
        // open start and visit it.
        var start_cell = &self.board.items[start_index];
        self.openCell(start_cell);
        var visited_cells = std.AutoHashMap(usize, bool).init(self.allocator);
        try visited_cells.put(start_index, true);

        var cell_queue = std.ArrayList(usize).init(self.allocator);
        defer cell_queue.deinit();
        const neighboring_indexes = try get_neighboring_indexes_by_index(self.x_size, self.y_size, start_index);
        for (0..neighboring_indexes.size) |i| {
            const neighbor_index = neighboring_indexes.neighbors[i];
            try cell_queue.append(neighbor_index);
        }

        while (cell_queue.items.len != 0) {
            const cell_index = cell_queue.pop();
            if (!(visited_cells.contains(cell_index))) {
                var cell = &self.board.items[cell_index];
                if (cell.is_mine != true and cell.neighoring_mines == 0) {
                    self.openCell(cell);
                    try visited_cells.put(cell_index, true);

                    const new_neighboring_indexes = try get_neighboring_indexes_by_index(self.x_size, self.y_size, cell_index);
                    for (0..new_neighboring_indexes.size) |neighbor_i| {
                        const neighbor_index = new_neighboring_indexes.neighbors[neighbor_i];
                        try cell_queue.append(neighbor_index);
                    }
                }
            }
        }
    }
};

fn coordinate_to_index(x_size: usize, y_size: usize, coordinate: CoordinatePair) usize {
    _ = y_size;
    const index = (coordinate.y * x_size) + coordinate.x;
    return index;
}

fn index_to_coordinate(x_size: usize, y_size: usize, index: usize) !CoordinatePair {
    _ = y_size;
    const y = try std.math.divFloor(usize, index, x_size);
    const x = try std.math.rem(usize, index, x_size);

    return CoordinatePair{
        .x = x,
        .y = y,
    };
}

const NeighborIndexes = struct {
    neighbors: [4]usize,
    size: usize,
};
fn get_neighboring_index(x_size: usize, y_size: usize, coordinate: CoordinatePair, x_op: Op, y_op: Op) ?usize {
    // TODO: create a checked math fn to clean this up
    // Then use that fn for each coordinate entry
    if ((coordinate.x == 0) and (x_op == Op.decrease)) {
        return null;
    }
    if ((coordinate.x >= x_size - 1) and (x_op == Op.increase)) {
        return null;
    }
    if ((coordinate.y == 0) and (y_op == Op.decrease)) {
        return null;
    }
    if ((coordinate.y >= y_size - 1) and (y_op == Op.increase)) {
        return null;
    }

    const x = switch (x_op) {
        Op.increase => coordinate.x + 1,
        Op.decrease => coordinate.x - 1,
        Op.zero => coordinate.x,
    };
    const y = switch (y_op) {
        Op.increase => coordinate.y + 1,
        Op.decrease => coordinate.y - 1,
        Op.zero => coordinate.y,
    };
    const index = coordinate_to_index(x_size, y_size, CoordinatePair{ .x = x, .y = y });
    return index;
}

fn get_neighboring_indexes(x_size: usize, y_size: usize, coordinate: CoordinatePair) !NeighborIndexes {
    const neighbors = [4][2]Op{
        [_]Op{ Op.zero, Op.decrease },

        [_]Op{ Op.decrease, Op.zero },
        [_]Op{ Op.increase, Op.zero },

        [_]Op{ Op.zero, Op.increase },
    };

    var results: [4]usize = undefined;
    var result_index: usize = 0;
    for (neighbors) |operation| {
        const x_op = operation[0];
        const y_op = operation[1];
        if (get_neighboring_index(x_size, y_size, coordinate, x_op, y_op)) |neighbor_index| {
            results[result_index] = neighbor_index;
            result_index += 1;
        }
    }

    return NeighborIndexes{
        .neighbors = results,
        .size = result_index,
    };
}

fn get_neighboring_indexes_by_index(x_size: usize, y_size: usize, index: usize) !NeighborIndexes {
    const coordinate = try index_to_coordinate(x_size, y_size, index);
    return get_neighboring_indexes(x_size, y_size, coordinate);
}

const SurroundingIndexes = struct {
    neighbors: [8]usize,
    size: usize,
};

fn get_surrounding_indexes(x_size: usize, y_size: usize, coordinate: CoordinatePair) !SurroundingIndexes {
    // Includes the diagonals
    const neighbors = [8][2]Op{
        [_]Op{ Op.decrease, Op.decrease },
        [_]Op{ Op.zero, Op.decrease },
        [_]Op{ Op.increase, Op.decrease },

        [_]Op{ Op.decrease, Op.zero },
        [_]Op{ Op.increase, Op.zero },

        [_]Op{ Op.decrease, Op.increase },
        [_]Op{ Op.zero, Op.increase },
        [_]Op{ Op.increase, Op.increase },
    };

    var results: [8]usize = undefined;
    var result_index: usize = 0;
    for (neighbors) |operation| {
        const x_op = operation[0];
        const y_op = operation[1];
        if (get_neighboring_index(x_size, y_size, coordinate, x_op, y_op)) |neighbor_index| {
            results[result_index] = neighbor_index;
            result_index += 1;
        }
    }

    return SurroundingIndexes{
        .neighbors = results,
        .size = result_index,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var game = try Game.init_easy(allocator, 1, 3, 3, 8);
    defer game.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush(); // don't forget to flush!

    game.debug_print();
    game.debug_print_mines();
    game.debug_print_neighboring_mine_counts();

    // open one box
    try game.open(CoordinatePair{ .x = 2, .y = 1 });
    game.debug_print();
    game.debug_print_mines();
    game.debug_print_neighboring_mine_counts();
}
