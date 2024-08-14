const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const yaml = @import("yaml.zig");

const Sequence = std.ArrayList(yaml.YAMLData);
const Mapping = std.StringArrayHashMapUnmanaged(YAMLData);
const YAMLData = yaml.YAMLData;
const Tokenizer = tokenizer.Tokenizer;
const Tag = tokenizer.Token.Tag;

const Self = @This();

tokens: std.MultiArrayList(Tokenizer.SmallToken),
allocator: std.mem.Allocator,
buf: [:0]const u8,
tags: []const Tag = undefined,
starts: []const u32 = undefined,
index: u32 = 0,
curr_indent: u32 = 0,

pub fn init(allocator: std.mem.Allocator, buf: [:0]const u8, tokens: std.MultiArrayList(Tokenizer.SmallToken)) Self {
    return Self{
        .tokens = tokens,
        .buf = buf,
        .allocator = allocator,
        .tags = tokens.slice().items(.tag),
        .starts = tokens.slice().items(.start),
    };
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
        else => |tag| {
            std.debug.print("\n\n\n{s}\n\n", .{@tagName(tag)});
            return yaml.YAMLError.UnsupportedSyntax;
        },
    }
}

fn parse_mapping(self: *Self) !YAMLData {
    var result = YAMLData{ .mapping = Mapping{} };

    // if (tags[1] == Tag.newline) {
    //     while (tags[self.curr_indent + 2] == Tag.whitespace) : (self.curr_indent += 1) {}
    //     self.index += self.curr_indent;
    // }

    self.index += 1;
    try result.mapping.put(self.allocator, self.buf[self.starts[0] .. self.starts[1] - 2], try self.parse());
    return result;
}

fn parse_sequence(self: *Self) !YAMLData {
    _ = self;
    return YAMLData{ .scalar = .{ .null = 0 } };
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
    defer denit_yaml(std.testing.allocator, &actual);
}

pub fn denit_yaml(allocator: std.mem.Allocator, obj: *YAMLData) void {
    switch (obj.*) {
        .mapping => {
            var it = obj.mapping.iterator();
            var data = it.next();
            while (data != null) : (data = it.next()) {
                denit_yaml(allocator, data.?.value_ptr);
            }
            obj.mapping.deinit(allocator);
        },
        .sequence => {
            const length = obj.sequence.items.len;
            var i: u32 = 0;
            while (i < length) : (i += 1) {
                denit_yaml(allocator, &(obj.sequence.items[i]));
            }
            obj.sequence.deinit();
        },
        .scalar => {},
    }
}

fn expectEqualYAML(actual: YAMLData, expected: YAMLData) !void {
    switch (actual) {
        .mapping => try expectEqualMapping(actual.mapping, expected.mapping),
        .sequence => try expectEqualSequence(actual.sequence, actual.sequence),
        .scalar => switch (actual.scalar) {
            .integer => try std.testing.expectEqual(actual.scalar.integer, expected.scalar.integer),
            .float => try std.testing.expectEqual(actual.scalar.float, expected.scalar.float),
            .boolean => try std.testing.expectEqual(actual.scalar.boolean, expected.scalar.boolean),
            .null => try std.testing.expectEqual(actual.scalar.null, expected.scalar.null),
            .string => try std.testing.expectEqualSlices(u8, actual.scalar.string, expected.scalar.string),
        },
    }
}

fn expectEqualMapping(actual: Mapping, expected: Mapping) error{TestExpectedEqual}!void {
    var actual_it = actual.iterator();
    var expected_it = expected.iterator();

    var actual_data = actual_it.next();
    var expected_data = expected_it.next();

    while (actual_data != null and expected_data != null) : ({
        actual_data = actual_it.next();
        expected_data = expected_it.next();
    }) {
        try std.testing.expectEqualSlices(u8, expected_data.?.key_ptr.*, actual_data.?.key_ptr.*);
        try expectEqualYAML(actual_data.?.value_ptr.*, expected_data.?.value_ptr.*);
    }
    if (actual_data == null and expected_data == null) return else return error.TestExpectedEqual;
}

fn expectEqualSequence(actual: Sequence, expected: Sequence) error{TestExpectedEqual}!void {
    _ = actual;
    _ = expected;
    return error.TestExpectedEqual;
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

test "nested mappings equal" {
    var data = YAMLData{
        .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
            .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
                .{ .scalar = .{ .string = "yee" } },
            }),
        }}),
    };
    defer denit_yaml(std.testing.allocator, &data);

    var data_2 = YAMLData{
        .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
            .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
                .{ .scalar = .{ .string = "yee" } },
            }),
        }}),
    };
    defer denit_yaml(std.testing.allocator, &data_2);

    _ = &data;
    _ = &data_2;

    try expectEqualYAML(data, data_2);
}

// test "parse mapping: mappings of mappings" {
//     var data = YAMLData{
//         .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
//             .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
//                 .{ .scalar = .{ .string = "yee" } },
//             }),
//         }}),
//     };
//     defer denit_yaml(std.testing.allocator, &data);
//
//     try testParse(
//         \\value:\n
//         \\  bruh: yee
//     , .{ .mapping = data.mapping });
// }
