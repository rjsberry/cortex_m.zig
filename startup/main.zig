// The contents of this file is dual-licensed under the MIT or 0BSD license.

const cortex_m = @import("cortex_m");

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

    if (cortex_m.cpu.generation == .v6m) {
        vectors[3] = .{ .reserve = 0 };
        vectors[4] = .{ .reserve = 0 };
        vectors[5] = .{ .reserve = 0 };
    } else {
        vectors[3] = .{ .diverge = _memManageFault };
        vectors[4] = .{ .diverge = _busFault };
        vectors[5] = .{ .diverge = _usageFault };
    }

    if (cortex_m.cpu.generation == .v8m) {
        vectors[6] = .{ .diverege = _secureFault };
    } else {
        vectors[6] = .{ .reserve = 0 };
    }

    vectors[7] = .{ .reserve = 0 };
    vectors[8] = .{ .reserve = 0 };
    vectors[9] = .{ .reserve = 0 };

    vectors[10] = .{ .handler = _svCall };

    if (cortex_m.cpu.generation == .v6m) {
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
/// If the CPU has a floating point hardware accelerator we fully enable both
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
///
/// Also branches to two optional init functions: `_preInit` and `_init`.
///
/// `_preInit` is called immediately on reset before RAM is initialized. This
/// can be used as a hook to call very early initialization code, e.g. C/C++
/// runtime initialization.
///
/// `_init` is called right before main. It can be used as a facade by other
/// downstream startup implementations to hide device specific detail from the
/// user, e.g. initializing clocks/PLLs.
///
/// Both functions are plain C functions with no arg and no return:
///
/// ```
/// export fn _preInit() callconv(.C) void {
///     // ...
/// }
///
/// export fn _init() callconv(.C) void {
///     // ...
/// }
/// ```
export fn _reset() linksection(".text._reset") callconv(.Naked) noreturn {
    // Note: all variables in assembly below come from the linker script.
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

    if (cortex_m.cpu.has_fp) {
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
