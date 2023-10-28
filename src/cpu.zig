// The contents of this file is dual-licensed under the MIT or 0BSD license.

const std = @import("std");
const builtin = @import("builtin");

const fmt = std.fmt;
const mem = std.mem;
const Target = std.Target;

const cpu = builtin.target.cpu;

/// Cortex-M CPU generations.
pub const Generation = enum {
    v6m,
    v7m,
    v8m,
};

/// The Cortex-M generation of the current build target (resolves via CPU name).
pub const generation = blk: {
    const v6m = [_][]const u8{
        "cortex_m0",
        "cortex_m0plus",
        "cortex_m1",
    };

    const v7m = [_][]const u8{
        "cortex_m3",
        "cortex_m4",
        "cortex_m7",
    };

    const v8m = [_][]const u8{
        "cortex_m23",
        "cortex_m33",
        "cortex_m35p",
        "cortex_m55",
        "cortex_m85",
    };

    inline for (v6m) |cpu_name| {
        if (mem.eql(u8, cpu.model.name, cpu_name)) {
            break :blk .v6m;
        }
    }

    inline for (v7m) |cpu_name| {
        if (mem.eql(u8, cpu.model.name, cpu_name)) {
            break :blk .v7m;
        }
    }

    inline for (v8m) |cpu_name| {
        if (mem.eql(u8, cpu.model.name, cpu_name)) {
            break :blk .v8m;
        }
    }

    @compileError(fmt.comptimePrint(
        "can't compile 'cortex_m' for '{s}' cpus",
        .{cpu.model.name},
    ));
};

/// Does the CPU having a floating point hardware accelerator?
pub const has_fp = blk: {
    const all_fp_features = [_]Target.arm.Feature{
        .vfp2,
        .vfp2sp,
        .vfp3,
        .vfp3d16,
        .vfp3d16sp,
        .vfp3sp,
        .vfp4,
        .vfp4d16,
        .vfp4d16sp,
        .vfp4sp,
    };

    inline for (all_fp_features) |feature| {
        if (cpu.features.isEnabled(@intFromEnum(feature))) {
            break :blk true;
        }
    }

    break :blk false;
};
