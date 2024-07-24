const std = @import("std");

const Token = struct {
    str: []const u8,
    tag: Tag,
    start: u32,

    const Tag = enum {
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
        int_literal,
        float_literal,
        whitespace,
    };

    const SmallToken = struct {
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
                        state = .int_literal;
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
                        result.tag = .comment_begin;
                        self.index += 1;
                        return result;
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
                    switch (c) {
                        ':' => {
                            if ((self.index + 1 < self.buffer.len) and std.ascii.isWhitespace(self.buffer[self.index + 1])) {
                                return result;
                            }
                        },
                        '\n', '#', 0 => return result,
                        else => continue,
                    }
                },
                .int_literal => switch (c) {
                    '0'...'9' => continue,
                    '.' => {
                        state = .float_literal;
                        result.tag = .float_literal;
                    },
                    else => return result,
                },
                .float_literal => switch (c) {
                    '0'...'9' => continue,
                    else => state = .string_literal,
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

test "multiple sequences" {
    try testTokenizer(
        \\- Mark McGwire
        \\- Sammy Sosa
        \\- Ken Griffey
    , &[_]Token.Tag{ .sequence_start_hyphen, .string_literal, .newline, .sequence_start_hyphen, .string_literal, .newline, .sequence_start_hyphen, .string_literal });
}
