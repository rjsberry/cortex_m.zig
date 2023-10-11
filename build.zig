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
    sections: []const Section = &.{},
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

/// An output section of the program.
pub const Section = struct {
    /// The name of the section.
    name: []const u8,
    /// The VMA (virtual memory address) of the section.
    address: ?[]const u8 = null,
    /// Input data to place in the section, avoiding garbage collection.
    keep: []const []const u8 = &.{},
    /// Places the section in the defined region.
    region: []const u8,
};

/// Generates and sets the linker script for a firmware artifact.
pub fn link(
    executable: *Step.Compile,
    layout: Layout,
) !void {
    const b = executable.step.owner;

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

    try generateMemoryRegions(&script, &layout);

    for (layout.sections) |*section| {
        try generateSection(&script, section);
    }

    var tmp_path = b.makeTempPath();
    var tmp_dir = try fs.openDirAbsolute(tmp_path, .{});
    defer tmp_dir.close();

    var memory_layout_script = try tmp_dir.createFile("memory_layout.ld", .{});
    defer memory_layout_script.close();
    try memory_layout_script.writeAll(script.items);

    var linker_script = try tmp_dir.createFile("link.ld", .{});
    defer linker_script.close();
    try linker_script.writeAll(@embedFile("link.ld"));

    const linker_script_path = try fs.path.join(
        b.allocator,
        &.{ tmp_path, "link.ld" },
    );
    defer b.allocator.free(linker_script_path);

    executable.addLibraryPath(.{ .path = tmp_path });
    executable.setLinkerScript(.{ .path = linker_script_path });

    const cleanup = b.addRemoveDirTree(tmp_path);
    cleanup.step.dependOn(&executable.step);
}

/// Generates the `MEMORY { ... }` linker script section.
fn generateMemoryRegions(
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

/// Generate `SECTION { ... }` linker script sections.
fn generateSection(
    script: *ArrayList(u8),
    section: *const Section,
) !void {
    const name = if (section.address) |address|
        try fmt.allocPrint(
            script.allocator,
            "  .{s} {s} :\n",
            .{ section.name, address },
        )
    else
        try fmt.allocPrint(
            script.allocator,
            "  .{s} :\n",
            .{section.name},
        );
    defer script.allocator.free(name);

    try script.appendSlice("SECTIONS\n{\n");
    try script.appendSlice(name);
    try script.appendSlice("  {\n");

    for (section.keep) |keep| {
        const command = try fmt.allocPrint(
            script.allocator,
            "    KEEP(*({s}));\n",
            .{keep},
        );
        defer script.allocator.free(command);
        try script.appendSlice(command);
    }

    const closing = try fmt.allocPrint(
        script.allocator,
        "  }} > {s}\n",
        .{section.region},
    );
    defer script.allocator.free(closing);
    try script.appendSlice(closing);

    try script.appendSlice("}\n\n");
}
