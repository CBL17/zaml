const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Mapping = std.StringArrayHashMapUnmanaged(YAMLData);
pub const Sequence = std.ArrayListUnmanaged(YAMLData);

pub const YAMLError = error{
    UnsupportedSyntax,
};

pub const YAMLScalarTag = enum {
    integer,
    float,
    string,
    boolean,
    null,
};

pub const YAMLDataTag = enum {
    scalar,
    sequence,
    mapping,
};

pub const YAMLData = union(YAMLDataTag) {
    scalar: union(YAMLScalarTag) {
        integer: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        null: u0,
    },
    sequence: Sequence,
    mapping: Mapping,
};

pub fn deinitYAML(allocator: Allocator, obj: *YAMLData) void {
    switch (obj.*) {
        .mapping => {
            var it = obj.mapping.iterator();
            var data = it.next();
            while (data != null) : (data = it.next()) {
                deinitYAML(allocator, data.?.value_ptr);
            }
            obj.mapping.deinit(allocator);
        },
        .sequence => {
            const length = obj.sequence.items.len;
            var i: u32 = 0;
            while (i < length) : (i += 1) {
                deinitYAML(allocator, &(obj.sequence.items[i]));
            }
            obj.sequence.deinit(allocator);
        },
        .scalar => {},
    }
}

pub fn expectEqualYAML(actual: YAMLData, expected: YAMLData) !void {
    switch (expected) {
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
    const actual_items = actual.items;
    const expected_items = expected.items;

    if (actual_items.len != expected_items.len) return error.TestExpectedEqual;

    for (actual_items, expected_items) |act, exp| {
        try expectEqualYAML(act, exp);
    }
}

test "nested mappings equal" {
    var data = YAMLData{
        .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
            .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
                .{ .scalar = .{ .string = "yee" } },
            }),
        }}),
    };
    defer deinitYAML(std.testing.allocator, &data);

    var data_2 = YAMLData{
        .mapping = try Mapping.init(std.testing.allocator, &.{"value"}, &.{.{
            .mapping = try Mapping.init(std.testing.allocator, &.{"bruh"}, &.{
                .{ .scalar = .{ .string = "yee" } },
            }),
        }}),
    };
    defer deinitYAML(std.testing.allocator, &data_2);

    _ = &data;
    _ = &data_2;

    try expectEqualYAML(data, data_2);
}
