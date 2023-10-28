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

    const cortex_m = b.addModule("cortex_m", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    _ = b.addModule("cortex_m_startup", .{
        .source_file = .{ .path = "startup/main.zig" },
        .dependencies = &.{
            .{ .name = "cortex_m", .module = cortex_m },
        },
    });
}

/// Generates and sets the linker script for a firmware artifact.
///
/// The `memory` argument should contain the content of a linker script which
/// describes the memory regions and any extra output sections in your firmware.
///
/// At a minimum this script must contain two regions: `FLASH` and `RAM`. The
/// start of the stack upon entry to the firmware will be at the end of the
/// `RAM` region.
pub fn link(
    executable: *Step.Compile,
    memory: []const u8,
) !void {
    const b = executable.step.owner;

    var tmp_path = b.makeTempPath();
    var tmp_dir = try fs.openDirAbsolute(tmp_path, .{});
    defer tmp_dir.close();

    var memory_layout_script = try tmp_dir.createFile("memory.ld", .{});
    defer memory_layout_script.close();
    try memory_layout_script.writeAll(memory);

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
