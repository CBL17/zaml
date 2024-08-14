const std = @import("std");

pub const Token = struct {
    str: []const u8,
    tag: Tag,
    start: u32,

    const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "TRUE", .boolean_true },
        .{ "True", .boolean_true },
        .{ "true", .boolean_true },
        .{ "FALSE", .boolean_false },
        .{ "False", .boolean_false },
        .{ "false", .boolean_false },
        .{ "NULL", .null },
        .{ "Null", .null },
        .{ "null", .null },
    });

    pub const Tag = enum {
        sequence_start_hyphen,
        sequence_start_bracket,
        sequence_end_bracket,
        sequence_identifier,
        mapping_start_brace,
        mapping_end_brace,
        mapping_separator,
        mapping_key,
        comment_begin,
        whitespace,
        int_literal,
        float_literal,
        string_literal,
        boolean_true,
        boolean_false,
        null,
        newline,
        invalid,
        eof,
    };
};

pub const Tokenizer = struct {
    index: u32,
    buffer: [:0]const u8,

    const State = enum {
        start,
        sequence,
        mapping,
        string_literal,
        number_literal,
        whitespace,
    };

    pub const SmallToken = struct {
        tag: Token.Tag,
        start: u32,
    };

    pub fn next(self: *Tokenizer) SmallToken {
        var state: State = .start;
        var result = SmallToken{
            .tag = .eof,
            .start = self.index,
        };

        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => return result,
                    '-' => {
                        state = .sequence;
                        result.tag = .sequence_start_hyphen;
                    },
                    'a'...'z', 'A'...'Z', '$', '^', '&', '(', ')', '/', ',', '.', ';', '?', '~', '_', '<' => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                    '0'...'9' => {
                        state = .number_literal;
                        result.tag = .int_literal;
                    },
                    ':' => {
                        state = .mapping;
                        result.tag = .mapping_separator;
                    },
                    ' ' => {
                        result.tag = .whitespace;
                        self.index += 1;
                        return result;
                    },
                    '#' => {
                        while (self.index < self.buffer.len and self.buffer[self.index] != '\n') : (self.index += 1) {}
                    },
                    '\n' => {
                        result.tag = .newline;
                        self.index += 1;
                        return result;
                    },
                    '\r', '\t' => continue,
                    else => std.debug.print("{d}\n", .{c}),
                },
                .string_literal => {
                    if (Token.keywords.get(self.buffer[result.start..self.index])) |tag| {
                        result.tag = tag;
                        return result;
                    }
                    switch (c) {
                        ':' => {
                            if ((self.index + 1 < self.buffer.len) and std.ascii.isWhitespace(self.buffer[self.index + 1])) {
                                if (self.buffer[self.index + 1] == '\n') self.index -= 1;
                                self.index += 2;
                                result.tag = .mapping_key;
                                return result;
                            }
                        },
                        '\n', '#', 0 => return result,
                        else => continue,
                    }
                },
                .number_literal => switch (c) {
                    '0'...'9' => continue,
                    '.' => {
                        result.tag = .float_literal;
                    },
                    else => return result,
                },
                .mapping => switch (c) {
                    ' ', '\r', '\t', '\n' => {
                        self.index += 1;
                        return result;
                    },
                    else => {
                        state = .string_literal;
                        result.tag = .string_literal;
                    },
                },
                .sequence => switch (c) {
                    ' ' => {
                        self.index += 1;
                        return result;
                    },
                    else => {
                        result.tag = .invalid;
                        return result;
                    },
                },
                else => return result,
            }
        }
    }
};

fn testTokenizer(comptime buf: [:0]const u8, comptime expected_tokens_tags: []const Token.Tag) !void {
    var tok = Tokenizer{
        .index = 0,
        .buffer = buf,
    };

    for (expected_tokens_tags) |expected_tag| {
        const actual_tag = tok.next().tag;
        try std.testing.expectEqual(expected_tag, actual_tag);
    }
    try std.testing.expectEqual(Token.Tag.eof, tok.next().tag);
}

test "scalar int" {
    try testTokenizer("12345", &[_]Token.Tag{.int_literal});
}

test "scalar float" {
    try testTokenizer("123.45", &[_]Token.Tag{.float_literal});
}

test "scalar bool: true" {
    try testTokenizer("true", &[_]Token.Tag{.boolean_true});
}

test "scalar null" {
    try testTokenizer("null", &[_]Token.Tag{.null});
}

test "multiple scalar ints" {
    try testTokenizer(
        \\1289764
        \\1289731
    , &[_]Token.Tag{ .int_literal, .newline, .int_literal });
}

test "multiple scalar floats" {
    try testTokenizer(
        \\12.89764
        \\1289.731
    , &[_]Token.Tag{ .float_literal, .newline, .float_literal });
}

test "multiple sequences" {
    try testTokenizer(
        \\- Mark McGwire
        \\- Sammy Sosa
        \\- Ken Griffey
    , &[_]Token.Tag{ .sequence_start_hyphen, .string_literal, .newline, .sequence_start_hyphen, .string_literal, .newline, .sequence_start_hyphen, .string_literal });
}

test "multiple mappings" {
    try testTokenizer(
        \\bruh: moment
        \\ninja: 13
        \\man: 0.01
    , &[_]Token.Tag{ .mapping_key, .string_literal, .newline, .mapping_key, .int_literal, .newline, .mapping_key, .float_literal });
}

test "sequence of mappings" {
    try testTokenizer(
        \\- test: 
        \\  again: 1
        \\- bruh
    , &[_]Token.Tag{ .sequence_start_hyphen, .mapping_key, .newline, .whitespace, .whitespace, .mapping_key, .int_literal, .newline, .sequence_start_hyphen, .string_literal });
}
