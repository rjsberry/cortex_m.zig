// The contents of this file is dual-licensed under the MIT or 0BSD license.

const std = @import("std");
const builtin = @import("builtin");

const fmt = std.fmt;
const mem = std.mem;
const Target = std.Target;

const cpu = builtin.target.cpu;

/// Cortex-M CPU generations.
const Generation = enum {
    v6m,
    v7m,
    v8m,
};

/// The Cortex-M generation of the current build target (resolves via CPU name).
const generation = blk: {
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
///
/// If so we must enable it in `_reset`.
const has_fp = blk: {
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

/// The default pre-init handler.
export fn _defaultPreInit() callconv(.C) void {}

/// The default init handler.
export fn _defaultInit() callconv(.C) void {}

/// The default exception/interrupt handler.
export fn _defaultHandler() callconv(.C) noreturn {
    @panic("");
}

extern fn _hardFault() callconv(.C) noreturn;
extern fn _nmi() callconv(.C) noreturn;
extern fn _memManageFault() callconv(.C) noreturn;
extern fn _busFault() callconv(.C) noreturn;
extern fn _usageFault() callconv(.C) noreturn;
extern fn _secureFault() callconv(.C) noreturn;
extern fn _svCall() callconv(.C) void;
extern fn _debugMonitor() callconv(.C) void;
extern fn _pendSv() callconv(.C) void;
extern fn _sysTick() callconv(.C) void;

/// An entry in the interrupt vector table.
///
/// In Cortex-M hardware this is just a function pointer.
const Vector = extern union {
    diverge: *const fn () callconv(.C) noreturn,
    handler: *const fn () callconv(.C) void,
    reserve: usize,
};

/// Built in exceptions.
///
/// This symbol is placed right after the stack pointer in the linker script.
export const _EXCEPTIONS linksection(".vector_table.exceptions") = blk: {
    var vectors: [15]Vector = undefined;

    vectors[0] = .{ .diverge = @ptrCast(&_reset) };
    vectors[1] = .{ .diverge = _nmi };
    vectors[2] = .{ .diverge = _hardFault };

    if (generation == .v6m) {
        vectors[3] = .{ .reserve = 0 };
        vectors[4] = .{ .reserve = 0 };
        vectors[5] = .{ .reserve = 0 };
    } else {
        vectors[3] = .{ .diverge = _memManageFault };
        vectors[4] = .{ .diverge = _busFault };
        vectors[5] = .{ .diverge = _usageFault };
    }

    if (generation == .v8m) {
        vectors[6] = .{ .diverege = _secureFault };
    } else {
        vectors[6] = .{ .reserve = 0 };
    }

    vectors[7] = .{ .reserve = 0 };
    vectors[8] = .{ .reserve = 0 };
    vectors[9] = .{ .reserve = 0 };

    vectors[10] = .{ .handler = _svCall };

    if (generation == .v6m) {
        vectors[11] = .{ .reserve = 0 };
    } else {
        vectors[11] = .{ .handler = _debugMonitor };
    }

    vectors[12] = .{ .reserve = 0 };

    vectors[13] = .{ .handler = _pendSv };
    vectors[14] = .{ .handler = _sysTick };

    break :blk vectors;
};

/// The reset handler.
///
/// If the core has a floating point hardware accelerator we fully enable both
/// CP10 and CP11 coprocessors (this check is made at comptime and has no
/// runtime cost).
///
/// Branches to `main` which must have the following signature:
///
/// ```
/// export fn main() callconv(.C) noreturn {
///     // ...
/// }
/// ```
export fn _reset() linksection(".text._reset") callconv(.Naked) noreturn {
    // Note: all variables below come from the linker script.
    asm volatile (
        \\bl _preInit
        \\ldr r0, =_sbss
        \\ldr r1, =_ebss
        \\movs r2, #0
        \\0:
        \\cmp r1, r0
        \\beq 1f
        \\stm r0!, {r2}
        \\b 0b
        \\1:
        \\ldr r0, =_sdata
        \\ldr r1, =_edata
        \\ldr r2, =_sidata
        \\2:
        \\cmp r1, r0
        \\beq 3f
        \\ldm r2!, {r3}
        \\stm r0!, {r3}
        \\b 2b
        \\3:
    );

    if (has_fp) {
        asm volatile (
            \\ldr r0, =0xE000ED88
            \\ldr r1, [r0]
            \\orr r1, r1, #0xF << 20
            \\str r1, [r0]
            \\dsb
            \\isb
        );
    }

    asm volatile (
        \\bl _init
        \\b main
    );
}
