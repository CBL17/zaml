const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const yaml = @import("yaml.zig");

const Sequence = std.ArrayList(yaml.YAMLData);
const Mapping = std.StringArrayHashMapUnmanaged(YAMLData);
const YAMLData = yaml.YAMLData;
const Tokenizer = tokenizer.Tokenizer;
const Tag = tokenizer.Token.Tag;

const Self = @This();

tokens: std.MultiArrayList(tokenizer.Tokenizer.SmallToken),
allocator: std.mem.Allocator,
buf: [:0]const u8,
index: u32 = 0,

pub fn parse(self: *Self, tags: []const Tag, starts: []const u32) anyerror!YAMLData {
    const next_index = if (self.index + 1 < self.tokens.len) starts[self.index + 1] else self.buf.len;
    const tag_slice = self.buf[starts[self.index]..next_index];

    switch (tags[self.index]) {
        .mapping_key => return try self.parse_mapping(tags, starts),
        .sequence_start_hyphen => return try self.parse_sequence(tags, starts),
        .int_literal => return YAMLData{ .scalar = .{ .integer = try std.fmt.parseInt(i64, tag_slice, 10) } },
        .float_literal => return YAMLData{ .scalar = .{ .float = try std.fmt.parseFloat(f64, tag_slice) } },
        .string_literal => return YAMLData{ .scalar = .{ .string = tag_slice } },
        .boolean_true => return YAMLData{ .scalar = .{ .boolean = true } },
        .boolean_false => return YAMLData{ .scalar = .{ .boolean = false } },
        .null => return YAMLData{ .scalar = .{ .null = 0 } },
        else => return yaml.YAMLError.UnsupportedSyntax,
    }
}

fn parse_mapping(self: *Self, tags: []const Tag, starts: []const u32) !YAMLData {
    var result = YAMLData{ .mapping = Mapping{} };
    self.index += 1;

    try result.mapping.put(self.allocator, self.buf[0 .. starts[1] - 2], try self.parse(tags, starts));
    return result;
}

fn parse_sequence(self: *Self, tags: []const Tag, starts: []const u32) !YAMLData {
    _ = self;
    _ = tags;
    _ = starts;
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

    var parser = Self{
        .buf = buf,
        .allocator = std.testing.allocator,
        .tokens = tokens,
    };
    var actual = try parser.parse(tokens.items(.tag), tokens.items(.start));
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
