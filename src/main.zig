const std = @import("std");
const Allocator = std.mem.Allocator;
const T = std.builtin.Type;

pub const std_options = std.Options{
    .log_level = .err,
};

const CmdReturnStatus = enum {
    success,
    fail,
    exit,
};

const builtin_names = [_][]const u8{
    "cd",
    "help",
    "exit",
};

const builtins = [_]*const fn ([]?[*:0]const u8) CmdReturnStatus{ &cd, &help, &exit };

fn cd(args: []?[*:0]const u8) CmdReturnStatus {
    if (args.len < 2) return CmdReturnStatus.fail;

    var return_status: CmdReturnStatus = .success;

    // TODO: how could the argument be null?
    if (std.fs.cwd().openDir(std.mem.span(args[1].?), .{})) |dir| {
        dir.setAsCwd() catch |err| {
            std.log.err("{!}\n", .{err});
            return_status = .fail;
        };
    } else |err| {
        std.log.err("{!}\n", .{err});
        return_status = .fail;
    }

    return return_status;
}

fn help(args: []?[*:0]const u8) CmdReturnStatus {
    _ = args;
    const out = std.io.getStdOut().writer();

    out.print("Zish\n", .{}) catch {};
    out.print("A basic shell.\n", .{}) catch {};
    out.print("Builtin commands:\n", .{}) catch {};

    for (builtin_names) |builtin| {
        out.print("\t{s}\n", .{builtin}) catch {};
    }

    return CmdReturnStatus.success;
}

fn exit(_: []?[*:0]const u8) CmdReturnStatus {
    return CmdReturnStatus.exit;
}

pub fn main() !void {
    zishLoop() catch |err| {
        std.log.err("Error while executing: {}\n", .{err});
    };
}

fn zishLoop() !void {
    std.log.info("Start\n", .{});
    const out = std.io.getStdOut().writer();
    var input: [4096]u8 = undefined;

    while (true) {
        var dir_buf: [128]u8 = undefined;
        const cwd = try std.process.getCwd(&dir_buf);
        const relative_dir_start_idx = if (std.mem.lastIndexOf(u8, cwd, "/")) |idx|
            idx + 1
        else
            0;

        try out.print("{s} > ", .{cwd[relative_dir_start_idx..]});

        if (try readLine(&input)) |command| {
            std.log.debug("command: {s}\n", .{command});
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();
            defer {
                std.log.debug("freeing\n", .{});
                arena.deinit();
            }
            const tokens = try splitLineHeap(command, allocator);
            switch (try executeCommand(tokens)) {
                .success => {}, //noop
                .fail => {}, // TODO: do some cool error handling
                .exit => break,
            }
        }
    }

    std.log.debug("end\n", .{});
}

fn executeCommand(args: []?[*:0]const u8) !CmdReturnStatus {
    // do builtin commands
    if (args.len == 0) return CmdReturnStatus.success;

    for (builtin_names, 0..) |builtin, idx| {
        // TODO: is there any way args[0] could be null?
        if (std.mem.eql(u8, builtin, std.mem.span(args[0].?))) {
            return builtins[idx](args);
        }
    }

    return launchCommand(args);
}

fn launchCommand(args: []?[*:0]const u8) !CmdReturnStatus {
    var return_status = CmdReturnStatus.success;
    const pid = try std.posix.fork();
    if (pid == 0) {
        if (args[0]) |program| {
            return std.posix.execvpeZ(program, @ptrCast(args), &.{null});
        }
    } else {
        const result: std.posix.WaitPidResult = std.posix.waitpid(pid, 0);

        // TODO: maybe some better handling of return states
        if (result.status != 0) return_status = CmdReturnStatus.fail;
    }

    return return_status;
}

fn readLine(input: []u8) !?[]u8 {
    const in = std.io.getStdIn().reader();
    return in.readUntilDelimiterOrEof(input, '\n');
}

fn splitLineHeap(line: []u8, allocator: Allocator) ![]?[*:0]const u8 {
    var tokenizer = std.mem.tokenizeAny(u8, line, " \t\r\n");
    var number_of_tokens: usize = 0;
    var capacity: usize = 8;
    var tokens = try allocator.alloc(?[*:0]const u8, capacity);

    while (tokenizer.next()) |token| {
        const c_string = try std.fmt.allocPrintZ(allocator, "{s}", .{token});

        tokens[number_of_tokens] = c_string;
        number_of_tokens += 1;

        if (number_of_tokens == capacity) {
            capacity *= 2;
            tokens = try allocator.realloc(tokens, capacity);
        }
    }

    tokens[number_of_tokens] = null;

    return tokens;
}

/// Trying out stuff with type reflection
fn errorFun(t: anytype) void {
    switch (@typeInfo(@TypeOf(t))) {
        .error_union => std.log.err("It's an erro union", .{}),
        .error_set => |errset_opt| {
            std.log.err("It's an error set", .{});
            if (errset_opt) |errset| {
                for (errset) |err| {
                    std.log.err("{s}", .{err.name});
                }
            }
        },
        else => std.log.err("It's something else", .{}),
    }
}
