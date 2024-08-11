const std = @import("std");

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
    sequence: std.ArrayList(YAMLData),
    mapping: std.StringArrayHashMapUnmanaged(YAMLData),
};
