const std = @import("std");

const tokenizer = @import("tokenizer.zig");
const Tokenizer = tokenizer.Tokenizer;
const Parser = @import("Parser.zig");

pub fn main() !void {
    const file: [:0]const u8 =
        \\simple: mapping
    ;
    var it = Tokenizer{
        .buffer = file,
        .index = 0,
    };

    var token = it.next();
    while (token.tag != .eof) {
        std.debug.print("{s}\n", .{@tagName(token.tag)});
        token = it.next();
    }
}

test {
    _ = tokenizer;
    _ = Parser;
    _ = @import("yaml.zig");
}
