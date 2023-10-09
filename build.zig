// The contents of this file is dual-licensed under the MIT or 0BSD license.

const std = @import("std");

const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const Step = std.Build.Step;

/// Adds the modules `cortex_m_startup` and `cortex_m` to the build.
pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    _ = b.addModule("cortex_m_startup", .{
        .source_file = .{ .path = "startup/main.zig" },
    });
}

/// The layout of the firmware.
///
/// This is used to generate the linker script.
pub const Layout = struct {
    regions: []const MemoryRegion,
};

/// Tag for `RegionLength` enum.
pub const RegionLengthTag = enum {
    m,
    k,
    bytes,
};

/// The length of a memory region.
pub const RegionLength = union(RegionLengthTag) {
    m: usize,
    k: usize,
    bytes: usize,
};

/// A memory region.
pub const MemoryRegion = struct {
    name: []const u8,
    origin: usize,
    len: RegionLength,
};

/// Basic linker script template.
const link_template = @embedFile("templates/link.ld.in");

/// Generates and sets the linker script for a firmware artifact.
pub fn link(
    b: *std.Build,
    executable: *Step.Compile,
    layout: Layout,
) !void {
    var got_flash = false;
    var got_ram = false;

    for (layout.regions) |r| {
        if (mem.eql(u8, r.name, "FLASH")) {
            got_flash = true;
        } else if (mem.eql(u8, r.name, "RAM")) {
            got_ram = true;
        }
    }

    if (!got_flash) {
        @panic("missing memory region 'FLASH' in layout");
    }

    if (!got_ram) {
        @panic("missing memory region 'RAM' in layout");
    }

    var script = ArrayList(u8).init(b.allocator);
    defer script.deinit();
    try generateMemoryBlock(&script, &layout);
    try script.appendSlice(link_template);

    var tmp_path = b.makeTempPath();
    const script_path = try fs.path.join(b.allocator, &[_][]const u8{
        tmp_path,
        "link.ld",
    });
    defer b.allocator.free(script_path);

    var script_file = try fs.createFileAbsolute(script_path, .{});
    defer script_file.close();
    try script_file.writeAll(script.items);

    executable.setLinkerScript(.{ .path = script_path });

    const cleanup = b.addRemoveDirTree(tmp_path);
    cleanup.step.dependOn(&executable.step);
}

/// Generates the `MEMORY { ... }` linker script section.
fn generateMemoryBlock(
    script: *ArrayList(u8),
    layout: *const Layout,
) !void {
    try script.appendSlice("MEMORY\n{\n");

    for (layout.regions) |r| {
        const r_str_start = try fmt.allocPrint(
            script.allocator,
            "  {s} : ORIGIN = 0x{X:0>8}, LENGTH = ",
            .{ r.name, r.origin },
        );
        defer script.allocator.free(r_str_start);

        const r_str_end = switch (r.len) {
            .m => |len| try fmt.allocPrint(
                script.allocator,
                "{}M\n",
                .{len},
            ),
            .k => |len| try fmt.allocPrint(
                script.allocator,
                "{}K\n",
                .{len},
            ),
            .bytes => |len| try fmt.allocPrint(
                script.allocator,
                "{}\n",
                .{len},
            ),
        };

        try script.appendSlice(r_str_start);
        try script.appendSlice(r_str_end);
    }

    try script.appendSlice("}\n\n");
}
