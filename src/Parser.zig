const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const yaml = @import("yaml.zig");

const Sequence = yaml.Sequence;
const Mapping = yaml.Mapping;
const YAMLData = yaml.YAMLData;

const Tokenizer = tokenizer.Tokenizer;
const Tag = tokenizer.Token.Tag;

const Allocator = std.mem.Allocator;

const expectEqualYAML = yaml.expectEqualYAML;
const deinitYAML = yaml.deinitYAML;

const Self = @This();

tokens: std.MultiArrayList(Tokenizer.SmallToken),
allocator: Allocator,
buf: [:0]const u8,
tags: []const Tag = undefined,
starts: []const u32 = undefined,
index: u32 = 0,

pub fn init(allocator: Allocator, buf: [:0]const u8, tokens: std.MultiArrayList(Tokenizer.SmallToken)) Self {
    return Self{
        .tokens = tokens,
        .buf = buf,
        .allocator = allocator,
        .tags = tokens.slice().items(.tag),
        .starts = tokens.slice().items(.start),
    };
}

pub fn reset(self: *Self) void {
    self.index = 0;
}

pub fn parse(self: *Self) anyerror!YAMLData {
    const next_index = if (self.index + 1 < self.tokens.len) self.starts[self.index + 1] else self.buf.len;
    const tag_slice = self.buf[self.starts[self.index]..next_index];

    switch (self.tags[self.index]) {
        .mapping_key => return try self.parse_mapping(),
        .sequence_start_hyphen => return try self.parse_sequence(),
        .int_literal => return YAMLData{ .scalar = .{ .integer = try std.fmt.parseInt(i64, tag_slice, 10) } },
        .float_literal => return YAMLData{ .scalar = .{ .float = try std.fmt.parseFloat(f64, tag_slice) } },
        .string_literal => return YAMLData{ .scalar = .{ .string = tag_slice } },
        .boolean_true => return YAMLData{ .scalar = .{ .boolean = true } },
        .boolean_false => return YAMLData{ .scalar = .{ .boolean = false } },
        .null => return YAMLData{ .scalar = .{ .null = 0 } },
        .whitespace => {
            var indent: u8 = 0;
            while (self.tags[self.index + indent] == .whitespace) : (indent += 1) {}
            {
                var curr_indent: u8 = 0;
                while (self.index < self.tokens.len and self.tags[self.index] == .whitespace) {
                    self.index += 1;
                    curr_indent += 1;
                }
                std.debug.assert(curr_indent == indent);

                return try self.parse();
            }
        },
        else => |tag| {
            std.log.err("\n\n{s}\n\n\n", .{@tagName(tag)});
            return yaml.YAMLError.UnsupportedSyntax;
        },
    }
}

fn parse_mapping(self: *Self) !YAMLData {
    var result = YAMLData{ .mapping = Mapping{} };
    std.debug.assert(self.tags[self.index] == .mapping_key);

    self.index += 1;
    switch (self.tags[self.index]) {
        .whitespace, .newline => {},
        else => return yaml.YAMLError.UnsupportedSyntax,
    }
    self.index += 1;
    try result.mapping.put(self.allocator, self.buf[self.starts[self.index - 2] .. self.starts[self.index - 1] - 1], try self.parse());
    self.index += 1;
    return result;
}

fn parse_sequence(self: *Self) !YAMLData {
    var result = YAMLData{ .sequence = Sequence{} };

    while (true) {
        std.debug.assert(self.tags[self.index] == .sequence_start_hyphen);

        self.index += 1;
        try result.sequence.append(self.allocator, try self.parse());
        self.index += 1;

        if (self.index >= self.tokens.len or self.tags[self.index] != .newline) break;

        self.index += 1;
    }
    return result;
}

fn testParse(buf: [:0]const u8, expected: YAMLData) !void {
    var tok = Tokenizer{
        .index = 0,
        .buffer = buf,
    };
    var tokens = std.MultiArrayList(Tokenizer.SmallToken){};
    var token = tok.next();
    while (token.tag != .eof) : (token = tok.next()) {
        try tokens.append(std.testing.allocator, token);
    }
    defer tokens.deinit(std.testing.allocator);

    var parser = Self.init(std.testing.allocator, buf, tokens);
    var actual = try parser.parse();
    _ = (&actual);

    try expectEqualYAML(actual, expected);
    defer deinitYAML(std.testing.allocator, &actual);
}

test "parse scalar int" {
    try testParse("123456", .{ .scalar = .{ .integer = 123456 } });
    try testParse("0", .{ .scalar = .{ .integer = 0 } });
}

test "parse scalar float" {
    try testParse("142.51", .{ .scalar = .{ .float = 142.51 } });
    try testParse("142.0", .{ .scalar = .{ .float = 142 } });
}

test "parse scalar string" {
    try testParse("test", .{ .scalar = .{ .string = "test" } });
    try testParse("bruh:", .{ .scalar = .{ .string = "bruh:" } });
    try testParse("br:--", .{ .scalar = .{ .string = "br:--" } });
}

test "parse mapping: simple string" {
    var mapping = try Mapping.init(std.testing.allocator, &.{"simple"}, &.{.{ .scalar = .{ .string = "mapping" } }});
    defer mapping.deinit(std.testing.allocator);

    try testParse("simple: mapping", .{ .mapping = mapping });
}

test "parse mapping: simple int" {
    var mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{ .scalar = .{ .integer = 987124 } }});
    defer mapping.deinit(std.testing.allocator);

    try testParse("value: 987124", .{ .mapping = mapping });
}

test "parse mapping: simple float" {
    var mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{ .scalar = .{ .float = 123980.124 } }});
    defer mapping.deinit(std.testing.allocator);

    try testParse("value: 123980.124000", .{ .mapping = mapping });
}

test "parse mapping: simple bool" {
    var mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{ .scalar = .{ .boolean = true } }});
    defer mapping.deinit(std.testing.allocator);

    try testParse("value: True", .{ .mapping = mapping });
}

test "parse mapping: simple null" {
    var mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{ .scalar = .{ .null = 0 } }});
    defer mapping.deinit(std.testing.allocator);

    try testParse("value: null", .{ .mapping = mapping });
}

// test "parse mapping: multiple mappings" {
//     var mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{ .scalar = .{ .null = 0 } }});
//     defer mapping.deinit(std.testing.allocator);
//     try mapping.put(std.testing.allocator, "gooofy", YAMLData{ .scalar = .{ .string = "ahh" } });
//
//     try testParse(
//         \\value: null
//         \\gooofy: ahh
//     , .{ .mapping = mapping });
// }

test "parse mapping: mappings of mappings" {
    var data = YAMLData{
        .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
            .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
                .{ .scalar = .{ .string = "yee" } },
            }),
        }}),
    };
    defer deinitYAML(std.testing.allocator, &data);

    try testParse(
        \\value:
        \\  bruh: yee
    , .{ .mapping = data.mapping });
}

test "parse sequence: scalar" {
    var data = YAMLData{ .sequence = Sequence{} };
    defer deinitYAML(std.testing.allocator, &data);
    try data.sequence.append(std.testing.allocator, YAMLData{ .scalar = .{ .string = "baller" } });

    try testParse("- baller", .{ .sequence = data.sequence });
}

test "parse sequence: multiple sequences" {
    var data = YAMLData{ .sequence = Sequence{} };
    defer deinitYAML(std.testing.allocator, &data);
    try data.sequence.append(std.testing.allocator, YAMLData{ .scalar = .{ .string = "baller" } });
    try data.sequence.append(std.testing.allocator, YAMLData{ .scalar = .{ .integer = 9087253 } });
    try data.sequence.append(std.testing.allocator, YAMLData{ .scalar = .{ .boolean = false } });

    try testParse(
        \\- baller
        \\- 9087253
        \\- false
    , .{ .sequence = data.sequence });
}

test "parse sequence: mapping" {
    var data = YAMLData{ .sequence = Sequence{} };
    defer deinitYAML(std.testing.allocator, &data);
    const inner_data = YAMLData{ .mapping = try Mapping.init(
        std.testing.allocator,
        &.{"data"},
        &.{.{ .scalar = .{ .string = "value" } }},
    ) };
    try data.sequence.append(std.testing.allocator, inner_data);

    try testParse(
        \\- data: value
    , .{ .sequence = data.sequence });
}
