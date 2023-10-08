const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    _ = b.addModule("cortex_m_startup", .{
        .source_file = .{ .path = "startup/main.zig" },
    });
}
