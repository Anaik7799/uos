//! beam-zig JIT epoch / slice #2 (`jit-asm-x86-64`): a **pure x86-64 machine-code
//! encoder** and its inverse decoder for the hot subset the template JIT needs.
//! This is the low-risk, Stratum-A (pure, law-governed) foundation of the native
//! backend — no executable memory, no codegen-from-BEAM, no GC. Just a byte
//! emitter and the disassembler that proves it correct.
//!
//! ## Signature
//!
//!   Inst                          — an abstract, operand-typed instruction (the
//!                                    algebra's carrier: mnemonic × registers ×
//!                                    immediates), independent of the byte layout.
//!   encode : Inst → Code          — the canonical byte encoding (a *total*,
//!                                    injective function; one instruction ↦ one
//!                                    byte string). Code is a free monoid over u8.
//!   decode : Code → (Inst, len)   — the partial inverse: parse the leading
//!                                    instruction and report bytes consumed.
//!   emitProgram : []Inst → []u8   — emit* , the monoid homomorphism extension of
//!                                    `encode` (emit*(xs++ys) = emit*(xs)·emit*(ys)).
//!
//! ## Semantic domain
//!
//! `Inst` is the abstract syntax; `Code` (byte strings) is the concrete x86-64
//! machine encoding as defined by the Intel SDM Vol.2 (REX / ModRM / SIB / disp /
//! imm). `decode` is the reference disassembler. The `encode` byte strings are
//! independently anchored to reality by a table of **golden vectors** hand-checked
//! against a real assembler / `objdump -d` (test `golden vectors`), so the
//! round-trip below is grounded, not merely self-consistent.
//!
//! ## Encodings (canonical — one chosen encoding per mnemonic)
//!
//!   mov r64, imm64   REX.W B8+rd  io          (movabs)
//!   mov r64, r64     REX.W 89 /r  (reg=src, rm=dst; MOV r/m64, r64)
//!   add r64, r64     REX.W 01 /r  (reg=src, rm=dst)
//!   sub r64, r64     REX.W 29 /r
//!   cmp r64, r64     REX.W 39 /r
//!   push r64         [REX.B] 50+rd
//!   pop  r64         [REX.B] 58+rd
//!   ret              C3
//!   jmp  rel32       E9 cd
//!   jcc  rel32       0F (80+tttn) cd        (je=0F84, jne=0F85, ...)
//!   call rel32       E8 cd
//!   call r64         [REX.B] FF /2        — gap-jit-bif-safepoint: the INDIRECT
//!                    call. rel32 cannot reach an mmap'ed W^X buffer from the
//!                    executable's text in general, so calling a Zig helper out
//!                    of JIT'd code needs an absolute target in a register.
//!   lea  r64,[r64+disp32]  REX.W 8D /r  (mod=10, rm=100 → SIB index=none, base=r64; disp32)
//!                    — LEA always emits a SIB byte (index=none). This uniform
//!                    encoding sidesteps the rsp/r12 (rm=100) and rbp/r13 (rm=101)
//!                    ModRM special cases and stays a clean bijection.
//!   and r64, r64     REX.W 21 /r  (reg=src, rm=dst; dst &= src)   — jit-codegen-arith
//!   mov r64,[r64+disp32]   REX.W 8B /r  (load; same always-SIB form as LEA)
//!   mov [r64+disp32],r64   REX.W 89 /r  (store; mod=10 disambiguates from mov_rr's
//!                    mod=11 reg-reg form of the SAME 89 opcode)
//!   sar r64, imm8    REX.W C1 /7 ib     (arithmetic shift right)
//!   shl r64, imm8    REX.W C1 /4 ib
//!                    — these five forms are what the template JIT needs to address
//!                    the memory-resident X-register file (load/store by offset),
//!                    mask a small-int tag (and), and untag/re-tag a small (sar/shl).
//!
//! ## Laws (this slice discharges **L1** of docs/OTP30_JIT_FORMAL_ANALYSIS.md)
//!
//!   L1  ENCODER BIJECTION   decode(encode(i)) = (i, |encode(i)|)   ∀ i ∈ subset
//!                           (property + fuzz; adversarial imm/disp boundaries and
//!                            r8–r15 REX-extended registers).
//!   L1' MONOID / STREAM     decoding emit*(p) byte-sequentially recovers exactly p
//!                           (emit* is injective; encode is prefix-free on the subset).
//!   GOLDEN                  encode(i) byte-equals a known-good reference encoding
//!                           for a hand-verified table (grounds the algebra in real
//!                           x86-64, so a decoder bug cannot hide an encoder bug).
//!
//! ## Scope limits
//!
//! 64-bit operand-size register ops only (REX.W where applicable); the exact hot
//! subset BeamAsm-class codegen needs (arith, moves, stack, control transfer,
//! address computation). NO memory operands beyond `lea [base+disp32]`, NO
//! scaled-index addressing, NO 8/16/32-bit operand forms, NO x87/SSE. Those are
//! out of scope until later codegen slices demand them.

const std = @import("std");

/// The 16 general-purpose 64-bit registers, numbered by their x86-64 encoding
/// (low 3 bits = ModRM/opcode field, bit 3 = the REX extension bit).
pub const Reg = enum(u4) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,
};

/// Condition codes for `jcc rel32`. The value is the low byte of the two-byte
/// `0F 8x` opcode (tttn field folded in): je = 0x84, jne = 0x85, …
pub const Cc = enum(u8) {
    b = 0x82, // below (CF=1)
    ae = 0x83, // above-or-equal (CF=0)
    e = 0x84, // equal / zero
    ne = 0x85, // not-equal / not-zero
    be = 0x86, // below-or-equal
    a = 0x87, // above
    l = 0x8C, // less (signed)
    ge = 0x8D, // greater-or-equal (signed)
    le = 0x8E, // less-or-equal (signed)
    g = 0x8F, // greater (signed)
};

const RegImm = struct { dst: Reg, imm: i64 };
const RegReg = struct { dst: Reg, src: Reg };
const JccOp = struct { cc: Cc, rel: i32 };
const LeaOp = struct { dst: Reg, base: Reg, disp: i32 };
/// jit-codegen-arith: a base+disp32 memory operand. `reg` is the register
/// destination (`load`) or source (`store`); `base+disp` is the address. Like
/// `lea`, the encoding ALWAYS emits a SIB byte (index=none) so it sidesteps the
/// rsp/r12 (rm=100) and rbp/r13 (rm=101) ModRM special cases and stays a clean
/// bijection over every base register. NO scaled index (out of scope).
const MemOp = struct { reg: Reg, base: Reg, disp: i32 };
/// jit-codegen-arith: a shift-by-immediate operand (`sar`/`shl` r64, imm8).
const ShiftOp = struct { dst: Reg, imm: u8 };
/// gap-jit-mask-imm: a group-1 ALU-with-imm32 operand (`add`/`and`/`cmp`
/// r64, imm32). The immediate is SIGN-EXTENDED to 64 bits by the hardware, so
/// only constants representable in i32 may be encoded this way — which is why
/// `SMALL_SUFFIX` (0xF) qualifies and `SMALL_HI` (1<<59) does not.
const RegImm32 = struct { dst: Reg, imm: i32 };

/// The instruction algebra carrier: operand-typed, layout-independent.
pub const Inst = union(enum) {
    mov_ri: RegImm, // mov r64, imm64
    mov_rr: RegReg, // mov dst, src
    add_rr: RegReg, // add dst, src   (dst += src)
    sub_rr: RegReg, // sub dst, src   (dst -= src)
    cmp_rr: RegReg, // cmp dst, src
    and_rr: RegReg, // and dst, src   (dst &= src)   — jit-codegen-arith (tag mask)
    push: Reg,
    pop: Reg,
    ret,
    jmp: i32, // jmp rel32
    jcc: JccOp, // jcc rel32
    call: i32, // call rel32
    /// gap-jit-bif-safepoint: `call r64` (FF /2). A rel32 call reaches ±2GB from
    /// the call site, and the JIT's code lives in an `mmap`ed W^X buffer that the
    /// kernel may place arbitrarily far from the executable's own text — so the
    /// displacement to a Zig helper is NOT representable in general. The
    /// indirect form (`mov rax, imm64` then `call rax`) has no such range limit,
    /// which is what makes calling out of JIT'd code possible at all.
    call_r: Reg,
    lea: LeaOp, // lea dst, [base + disp32]
    // ---- jit-codegen-arith: memory-resident register file access + shifts ----
    load: MemOp, //   mov reg, [base + disp32]   (REX.W 8B /r, always-SIB)
    store: MemOp, //  mov [base + disp32], reg   (REX.W 89 /r, always-SIB)
    sar_ri: ShiftOp, // sar reg, imm8  (REX.W C1 /7 ib) — arithmetic (sign) shift
    shl_ri: ShiftOp, // shl reg, imm8  (REX.W C1 /4 ib)
    // ---- gap-jit-mask-imm: group-1 ALU with a sign-extended imm32 (81 /ext id).
    // These exist so the small-tag constant stops occupying a register: the tag
    // guard and re-tag can name 0xF directly instead of loading it per block.
    add_ri: RegImm32, // add reg, imm32 (REX.W 81 /0 id)
    and_ri: RegImm32, // and reg, imm32 (REX.W 81 /4 id)
    cmp_ri: RegImm32, // cmp reg, imm32 (REX.W 81 /7 id)
    sub_ri: RegImm32, // sub reg, imm32 (REX.W 81 /5 id)
};

/// A fixed-capacity encoded instruction (the longest supported form —
/// `mov r64, imm64` — is 10 bytes; 16 is comfortable headroom, so encoding
/// needs no allocator and cannot leak).
pub const Encoded = struct {
    buf: [16]u8 = undefined,
    len: u8 = 0,

    fn put(self: *Encoded, b: u8) void {
        self.buf[self.len] = b;
        self.len += 1;
    }
    fn put32(self: *Encoded, v: i32) void {
        std.mem.writeInt(i32, self.buf[self.len..][0..4], v, .little);
        self.len += 4;
    }
    fn put64(self: *Encoded, v: i64) void {
        std.mem.writeInt(i64, self.buf[self.len..][0..8], v, .little);
        self.len += 8;
    }

    /// The emitted bytes.
    pub fn slice(self: *const Encoded) []const u8 {
        return self.buf[0..self.len];
    }
};

// REX prefix nibble: 0100 WRXB. W=64-bit operand, R=ModRM.reg ext,
// X=SIB.index ext, B=ModRM.rm / SIB.base / opcode-reg ext.
const REX_W: u8 = 0x48; // 0100_1000

/// The reg-reg family (89/01/29/39): REX.W + opcode + ModRM(mod=11, reg=src, rm=dst).
fn encodeRR(op: u8, dst: Reg, src: Reg) Encoded {
    var e = Encoded{};
    const d: u8 = @intFromEnum(dst);
    const s: u8 = @intFromEnum(src);
    e.put(REX_W | ((s >> 3) << 2) | (d >> 3)); // REX.W + R(src) + B(dst)
    e.put(op);
    e.put(0xC0 | ((s & 7) << 3) | (d & 7)); // mod=11, reg=src, rm=dst
    return e;
}

/// encode : Inst → Code — the canonical, total, injective byte encoding.
pub fn encode(inst: Inst) Encoded {
    var e = Encoded{};
    switch (inst) {
        .ret => e.put(0xC3),
        .push => |r| {
            const v: u8 = @intFromEnum(r);
            if (v >= 8) e.put(0x41); // REX.B
            e.put(0x50 | (v & 7));
        },
        .pop => |r| {
            const v: u8 = @intFromEnum(r);
            if (v >= 8) e.put(0x41); // REX.B
            e.put(0x58 | (v & 7));
        },
        .mov_ri => |m| {
            const d: u8 = @intFromEnum(m.dst);
            e.put(REX_W | (d >> 3)); // REX.W + B(dst)
            e.put(0xB8 | (d & 7));
            e.put64(m.imm);
        },
        .mov_rr => |m| return encodeRR(0x89, m.dst, m.src),
        .add_rr => |m| return encodeRR(0x01, m.dst, m.src),
        .sub_rr => |m| return encodeRR(0x29, m.dst, m.src),
        .cmp_rr => |m| return encodeRR(0x39, m.dst, m.src),
        .and_rr => |m| return encodeRR(0x21, m.dst, m.src),
        .jmp => |rel| {
            e.put(0xE9);
            e.put32(rel);
        },
        .call => |rel| {
            e.put(0xE8);
            e.put32(rel);
        },
        // gap-jit-bif-safepoint: FF /2 — near call, absolute indirect via r64.
        // No REX.W (the operand is 64-bit by default in long mode); REX.B only
        // to reach r8–r15.
        .call_r => |r| {
            const v: u8 = @intFromEnum(r);
            if (v >= 8) e.put(0x41); // REX.B
            e.put(0xFF);
            e.put(0xD0 | (v & 7)); // mod=11, reg=/2, rm=r
        },
        .jcc => |j| {
            e.put(0x0F);
            e.put(@intFromEnum(j.cc));
            e.put32(j.rel);
        },
        .lea => |l| {
            const d: u8 = @intFromEnum(l.dst);
            const bs: u8 = @intFromEnum(l.base);
            e.put(REX_W | ((d >> 3) << 2) | (bs >> 3)); // REX.W + R(dst) + B(base)
            e.put(0x8D);
            e.put(0x80 | ((d & 7) << 3) | 4); // mod=10(disp32), reg=dst, rm=100(SIB)
            e.put((4 << 3) | (bs & 7)); // scale=0, index=100(none), base
            e.put32(l.disp);
        },
        .load => |m| return encodeMem(0x8B, m), // mov reg, [base+disp32]
        .store => |m| return encodeMem(0x89, m), // mov [base+disp32], reg
        .sar_ri => |s| return encodeShift(7, s), // sar reg, imm8   (/7)
        .shl_ri => |s| return encodeShift(4, s), // shl reg, imm8   (/4)
        .add_ri => |o| return encodeGrp1(0, o), // add reg, imm32  (/0)
        .and_ri => |o| return encodeGrp1(4, o), // and reg, imm32  (/4)
        .cmp_ri => |o| return encodeGrp1(7, o), // cmp reg, imm32  (/7)
        .sub_ri => |o| return encodeGrp1(5, o), // sub reg, imm32  (/5)
    }
    return e;
}

/// A base+disp32 memory operand (load 8B / store 89): REX.W + opcode +
/// ModRM(mod=10, reg, rm=100/SIB) + SIB(index=none, base) + disp32. The
/// always-SIB form mirrors `lea` — one uniform encoding over every base reg.
fn encodeMem(op: u8, m: MemOp) Encoded {
    var e = Encoded{};
    const r: u8 = @intFromEnum(m.reg);
    const bs: u8 = @intFromEnum(m.base);
    e.put(REX_W | ((r >> 3) << 2) | (bs >> 3)); // REX.W + R(reg) + B(base)
    e.put(op);
    e.put(0x80 | ((r & 7) << 3) | 4); // mod=10(disp32), reg, rm=100(SIB)
    e.put((4 << 3) | (bs & 7)); // scale=0, index=100(none), base
    e.put32(m.disp);
    return e;
}

/// A shift-by-imm8 (C1 /ext ib): REX.W + C1 + ModRM(mod=11, reg=ext, rm=dst) +
/// imm8. `ext` selects the operation (4 = SHL, 7 = SAR).
fn encodeShift(ext: u3, s: ShiftOp) Encoded {
    var e = Encoded{};
    const d: u8 = @intFromEnum(s.dst);
    e.put(REX_W | (d >> 3)); // REX.W + B(dst)
    e.put(0xC1);
    e.put(0xC0 | (@as(u8, ext) << 3) | (d & 7)); // mod=11, reg=ext, rm=dst
    e.put(s.imm);
    return e;
}

/// A group-1 ALU with a sign-extended immediate. `ext` selects the operation
/// (0 = ADD, 4 = AND, 7 = CMP).
///
/// CANONICAL SHORTEST FORM. x86-64 offers two encodings — `83 /ext ib` with a
/// sign-extended imm8 (4 bytes total) and `81 /ext id` with an imm32 (7 bytes).
/// The encoder always picks the shorter one that represents the value, which is
/// what makes this slice a win on BOTH metrics rather than trading instruction
/// count for code size: the first version emitted only the imm32 form and grew
/// the benchmark loop by 26 bytes while removing 3 instructions. The attribution
/// instrument is what surfaced that, since the two numbers move in opposite
/// directions and the instruction count alone looked like a clean gain.
///
/// The decoder accepts both, so `decode ∘ encode = id` holds on INSTRUCTIONS.
/// Byte-level canonicity is deliberate, not accidental: one instruction has one
/// encoding here, so emitted code is a function of the instruction stream.
fn encodeGrp1(ext: u3, o: RegImm32) Encoded {
    var e = Encoded{};
    const d: u8 = @intFromEnum(o.dst);
    e.put(REX_W | (d >> 3)); // REX.W + B(dst)
    const short = o.imm >= -128 and o.imm <= 127;
    e.put(if (short) 0x83 else 0x81);
    e.put(0xC0 | (@as(u8, ext) << 3) | (d & 7)); // mod=11, reg=ext, rm=dst
    if (short) e.put(@bitCast(@as(i8, @intCast(o.imm)))) else e.put32(o.imm);
    return e;
}

pub const DecodeError = error{
    Truncated,
    BadOpcode,
    BadLea,
    BadJcc,
    /// gap-jit-bif-safepoint: an FF-group opcode whose /ext is not /2 (call).
    /// The encoder emits only /2, so this is unreachable from `encode` — it
    /// exists so `decode` stays TOTAL on arbitrary bytes rather than
    /// mis-reporting some other FF-group instruction as a call.
    BadCallR,
};

pub const Decoded = struct { inst: Inst, len: usize };

fn regOf(v: u8) Reg {
    return @enumFromInt(@as(u4, @intCast(v & 0xF)));
}

/// Decode a base+disp32 always-SIB memory op (`load`/`store`). `i` points at the
/// ModRM byte (the opcode is already consumed). The inverse of `encodeMem`.
fn decodeMem(comptime kind: enum { load, store }, code: []const u8, start: usize, r_ext: u8, b_ext: u8) DecodeError!Decoded {
    var i = start;
    if (i >= code.len) return error.Truncated;
    const modrm = code[i];
    i += 1;
    if ((modrm >> 6) != 0b10 or (modrm & 7) != 4) return error.BadOpcode; // mod=10, rm=100(SIB)
    if (i >= code.len) return error.Truncated;
    const sib = code[i];
    i += 1;
    if (((sib >> 3) & 7) != 4) return error.BadOpcode; // index must be none (100)
    const disp = try readI32(code, i);
    const m = MemOp{
        .reg = regOf(((modrm >> 3) & 7) | (r_ext << 3)),
        .base = regOf((sib & 7) | (b_ext << 3)),
        .disp = disp,
    };
    return switch (kind) {
        .load => .{ .inst = .{ .load = m }, .len = i + 4 },
        .store => .{ .inst = .{ .store = m }, .len = i + 4 },
    };
}

fn readI32(code: []const u8, off: usize) DecodeError!i32 {
    if (off + 4 > code.len) return error.Truncated;
    return std.mem.readInt(i32, code[off..][0..4], .little);
}
fn readI64(code: []const u8, off: usize) DecodeError!i64 {
    if (off + 8 > code.len) return error.Truncated;
    return std.mem.readInt(i64, code[off..][0..8], .little);
}

/// decode : Code → (Inst, len) — parse the leading instruction. The partial
/// inverse of `encode` over the supported subset.
pub fn decode(code: []const u8) DecodeError!Decoded {
    if (code.len == 0) return error.Truncated;
    var i: usize = 0;
    var rex: u8 = 0;
    var b = code[0];
    if (b & 0xF0 == 0x40) {
        rex = b;
        i += 1;
        if (i >= code.len) return error.Truncated;
        b = code[i];
    }
    const r_ext: u8 = (rex >> 2) & 1; // REX.R
    const b_ext: u8 = rex & 1; // REX.B
    i += 1; // consume the opcode byte

    switch (b) {
        0xC3 => return .{ .inst = .ret, .len = i },
        // gap-jit-bif-safepoint: FF /2 — near call, absolute indirect via r64.
        0xFF => {
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            i += 1;
            if ((modrm >> 6) != 0b11 or ((modrm >> 3) & 7) != 2) return error.BadCallR;
            return .{ .inst = .{ .call_r = regOf((modrm & 7) | (b_ext << 3)) }, .len = i };
        },
        0x50...0x57 => return .{ .inst = .{ .push = regOf((b & 7) | (b_ext << 3)) }, .len = i },
        0x58...0x5F => return .{ .inst = .{ .pop = regOf((b & 7) | (b_ext << 3)) }, .len = i },
        0xB8...0xBF => {
            const imm = try readI64(code, i);
            return .{ .inst = .{ .mov_ri = .{ .dst = regOf((b & 7) | (b_ext << 3)), .imm = imm } }, .len = i + 8 };
        },
        0x89 => {
            // MOV r/m64, r64: mod=11 is the reg-reg form; mod=10 (always-SIB) is
            // the `store [base+disp32], reg` form. Disambiguate on the mod field.
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            if ((modrm >> 6) == 0b10) return decodeMem(.store, code, i, r_ext, b_ext);
            i += 1;
            return .{ .inst = .{ .mov_rr = .{
                .src = regOf(((modrm >> 3) & 7) | (r_ext << 3)),
                .dst = regOf((modrm & 7) | (b_ext << 3)),
            } }, .len = i };
        },
        0x8B => return decodeMem(.load, code, i, r_ext, b_ext), // mov reg, [base+disp32]
        0x01, 0x29, 0x39, 0x21 => {
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            i += 1;
            const rr = RegReg{
                .src = regOf(((modrm >> 3) & 7) | (r_ext << 3)),
                .dst = regOf((modrm & 7) | (b_ext << 3)),
            };
            const inst: Inst = switch (b) {
                0x01 => .{ .add_rr = rr },
                0x29 => .{ .sub_rr = rr },
                0x39 => .{ .cmp_rr = rr },
                0x21 => .{ .and_rr = rr },
                else => unreachable,
            };
            return .{ .inst = inst, .len = i };
        },
        0xC1 => {
            // Shift r/m64, imm8: mod=11 reg-form; ext (ModRM.reg) selects SHL(/4)
            // or SAR(/7); the imm8 is the shift count.
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            i += 1;
            if ((modrm >> 6) != 0b11) return error.BadOpcode; // reg form only
            const dst = regOf((modrm & 7) | (b_ext << 3));
            if (i >= code.len) return error.Truncated;
            const imm = code[i];
            i += 1;
            const ext = (modrm >> 3) & 7;
            const so = ShiftOp{ .dst = dst, .imm = imm };
            return switch (ext) {
                4 => .{ .inst = .{ .shl_ri = so }, .len = i },
                7 => .{ .inst = .{ .sar_ri = so }, .len = i },
                else => error.BadOpcode,
            };
        },
        0x81, 0x83 => {
            // Group-1 r/m64 with a sign-extended immediate: mod=11 reg-form;
            // ext (ModRM.reg) selects ADD(/0), AND(/4) or CMP(/7). 0x83 carries
            // an imm8, 0x81 an imm32 — both sign-extend to 64 bits, so they
            // decode to the same instruction.
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            i += 1;
            if ((modrm >> 6) != 0b11) return error.BadOpcode; // reg form only
            const dst = regOf((modrm & 7) | (b_ext << 3));
            var imm: i32 = undefined;
            if (b == 0x83) {
                if (i >= code.len) return error.Truncated;
                imm = @as(i8, @bitCast(code[i]));
                i += 1;
            } else {
                imm = try readI32(code, i);
                i += 4;
            }
            const o = RegImm32{ .dst = dst, .imm = imm };
            return switch ((modrm >> 3) & 7) {
                0 => .{ .inst = .{ .add_ri = o }, .len = i },
                4 => .{ .inst = .{ .and_ri = o }, .len = i },
                5 => .{ .inst = .{ .sub_ri = o }, .len = i },
                7 => .{ .inst = .{ .cmp_ri = o }, .len = i },
                else => error.BadOpcode,
            };
        },
        0xE9 => return .{ .inst = .{ .jmp = try readI32(code, i) }, .len = i + 4 },
        0xE8 => return .{ .inst = .{ .call = try readI32(code, i) }, .len = i + 4 },
        0x8D => {
            if (i >= code.len) return error.Truncated;
            const modrm = code[i];
            i += 1;
            // canonical LEA: mod=10 (disp32), rm=100 (SIB follows)
            if ((modrm >> 6) != 0b10 or (modrm & 7) != 4) return error.BadLea;
            if (i >= code.len) return error.Truncated;
            const sib = code[i];
            i += 1;
            if (((sib >> 3) & 7) != 4) return error.BadLea; // index must be none (100)
            const disp = try readI32(code, i);
            return .{ .inst = .{ .lea = .{
                .dst = regOf(((modrm >> 3) & 7) | (r_ext << 3)),
                .base = regOf((sib & 7) | (b_ext << 3)),
                .disp = disp,
            } }, .len = i + 4 };
        },
        0x0F => {
            if (i >= code.len) return error.Truncated;
            const cc = code[i];
            i += 1;
            if (cc < 0x80 or cc > 0x8F) return error.BadJcc;
            return .{ .inst = .{ .jcc = .{ .cc = @enumFromInt(cc), .rel = try readI32(code, i) } }, .len = i + 4 };
        },
        else => return error.BadOpcode,
    }
}

/// emit* — the monoid-homomorphism extension of `encode` to an instruction
/// stream. Allocates the concatenated code (caller owns it).
pub fn emitProgram(gpa: std.mem.Allocator, prog: []const Inst) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (prog) |inst| {
        const e = encode(inst);
        try out.appendSlice(gpa, e.slice());
    }
    return out.toOwnedSlice(gpa);
}

// ===========================================================================
// Law suite
// ===========================================================================

// A fixed seed so the fuzz law is deterministic and reproducible; it is echoed
// on any failure so a reddening case is instantly replayable.
const FUZZ_SEED: u64 = 0x6A_69_74_61_73_6D_78_36; // "jitasmx6"

fn genReg(rnd: std.Random) Reg {
    // Bias one-third toward r8–r15 so the REX.R/REX.B extension bits are
    // exercised far more than uniform sampling would.
    if (rnd.uintLessThan(u8, 3) == 0) return @enumFromInt(rnd.intRangeAtMost(u4, 8, 15));
    return @enumFromInt(rnd.intRangeAtMost(u4, 0, 15));
}

fn advI64(rnd: std.Random) i64 {
    const boundaries = [_]i64{
        0,                    1,                    -1,
        std.math.minInt(i64), std.math.maxInt(i64), std.math.minInt(i32),
        std.math.maxInt(i32), 0x7fff_ffff,          -0x8000_0000,
        0x1_0000_0000,        -0x1_0000_0000,       0x8000_0000,
    };
    if (rnd.boolean()) return boundaries[rnd.uintLessThan(usize, boundaries.len)];
    return @bitCast(rnd.int(u64));
}

fn advI32(rnd: std.Random) i32 {
    const boundaries = [_]i32{
        0, 1, -1, std.math.minInt(i32), std.math.maxInt(i32), -0x8000, 0x7fff, 0x40,
    };
    if (rnd.boolean()) return boundaries[rnd.uintLessThan(usize, boundaries.len)];
    return @bitCast(rnd.int(u32));
}

fn genCc(rnd: std.Random) Cc {
    const all = [_]Cc{ .b, .ae, .e, .ne, .be, .a, .l, .ge, .le, .g };
    return all[rnd.uintLessThan(usize, all.len)];
}

fn genInst(rnd: std.Random) Inst {
    return switch (rnd.uintLessThan(u8, 22)) {
        0 => .{ .mov_ri = .{ .dst = genReg(rnd), .imm = advI64(rnd) } },
        1 => .{ .mov_rr = .{ .dst = genReg(rnd), .src = genReg(rnd) } },
        2 => .{ .add_rr = .{ .dst = genReg(rnd), .src = genReg(rnd) } },
        3 => .{ .sub_rr = .{ .dst = genReg(rnd), .src = genReg(rnd) } },
        4 => .{ .cmp_rr = .{ .dst = genReg(rnd), .src = genReg(rnd) } },
        5 => .{ .push = genReg(rnd) },
        6 => .{ .pop = genReg(rnd) },
        7 => .ret,
        8 => .{ .jmp = advI32(rnd) },
        9 => .{ .jcc = .{ .cc = genCc(rnd), .rel = advI32(rnd) } },
        10 => .{ .call = advI32(rnd) },
        11 => .{ .lea = .{ .dst = genReg(rnd), .base = genReg(rnd), .disp = advI32(rnd) } },
        // jit-codegen-arith additions (exercise the REX-extended memory/shift forms)
        12 => .{ .and_rr = .{ .dst = genReg(rnd), .src = genReg(rnd) } },
        13 => .{ .load = .{ .reg = genReg(rnd), .base = genReg(rnd), .disp = advI32(rnd) } },
        14 => .{ .store = .{ .reg = genReg(rnd), .base = genReg(rnd), .disp = advI32(rnd) } },
        15 => .{ .sar_ri = .{ .dst = genReg(rnd), .imm = rnd.int(u8) } },
        16 => .{ .shl_ri = .{ .dst = genReg(rnd), .imm = rnd.int(u8) } },
        // gap-jit-mask-imm: the group-1 imm32 forms. Generated like every other
        // arm so the bijection law covers them from the moment they exist — a
        // new instruction the fuzzer never emits is an unverified encoding.
        17 => .{ .add_ri = .{ .dst = genReg(rnd), .imm = advI32(rnd) } },
        18 => .{ .and_ri = .{ .dst = genReg(rnd), .imm = advI32(rnd) } },
        19 => .{ .cmp_ri = .{ .dst = genReg(rnd), .imm = advI32(rnd) } },
        20 => .{ .sub_ri = .{ .dst = genReg(rnd), .imm = advI32(rnd) } },
        // gap-jit-bif-safepoint: the indirect call. Generated like every other
        // arm — a new instruction the fuzzer never emits is an unverified
        // encoding, and this one is the only way out of the exec buffer.
        21 => .{ .call_r = genReg(rnd) },
        else => unreachable,
    };
}

test "L1: decode ∘ encode = id over the supported x86-64 subset (fuzz)" {
    var prng = std.Random.DefaultPrng.init(FUZZ_SEED);
    const rnd = prng.random();
    var n: usize = 0;
    while (n < 20000) : (n += 1) { // bounded driver: a hang would be a failed law
        const inst = genInst(rnd);
        const enc = encode(inst);
        const dec = decode(enc.slice()) catch |err| {
            std.debug.print("L1 FAIL SEED={x} iter={d}: decode error {s} on inst={any} bytes={x}\n", .{ FUZZ_SEED, n, @errorName(err), inst, enc.slice() });
            return err;
        };
        if (dec.len != enc.len or !std.meta.eql(dec.inst, inst)) {
            std.debug.print("L1 FAIL SEED={x} iter={d}: inst={any} enc={x} -> dec={any} (declen={d} enclen={d})\n", .{ FUZZ_SEED, n, inst, enc.slice(), dec.inst, dec.len, enc.len });
            return error.RoundTripMismatch;
        }
    }
}

test "L1': emit* stream decodes byte-sequentially back to the exact program" {
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(FUZZ_SEED +% 1);
    const rnd = prng.random();

    var trial: usize = 0;
    while (trial < 500) : (trial += 1) {
        const k = rnd.intRangeAtMost(usize, 0, 24);
        const prog = try gpa.alloc(Inst, k);
        defer gpa.free(prog);
        for (prog) |*p| p.* = genInst(rnd);

        const code = try emitProgram(gpa, prog); // exercises the allocating path (leak-free via testing.allocator)
        defer gpa.free(code);

        var off: usize = 0;
        for (prog, 0..) |inst, idx| {
            const dec = decode(code[off..]) catch |err| {
                std.debug.print("L1' FAIL SEED={x} trial={d} idx={d}: {s}\n", .{ FUZZ_SEED +% 1, trial, idx, @errorName(err) });
                return err;
            };
            if (!std.meta.eql(dec.inst, inst)) {
                std.debug.print("L1' FAIL SEED={x} trial={d} idx={d}: got {any} want {any}\n", .{ FUZZ_SEED +% 1, trial, idx, dec.inst, inst });
                return error.StreamMismatch;
            }
            off += dec.len;
        }
        try std.testing.expectEqual(code.len, off); // consumed exactly, no trailing bytes
    }
}

test "golden vectors: encoder byte-equals hand-verified x86-64 (objdump-checked)" {
    const cases = [_]struct { inst: Inst, bytes: []const u8 }{
        // ret
        .{ .inst = .ret, .bytes = &.{0xC3} },
        // movabs rax, 1
        .{ .inst = .{ .mov_ri = .{ .dst = .rax, .imm = 1 } }, .bytes = &.{ 0x48, 0xB8, 0x01, 0, 0, 0, 0, 0, 0, 0 } },
        // movabs r15, -1
        .{ .inst = .{ .mov_ri = .{ .dst = .r15, .imm = -1 } }, .bytes = &.{ 0x49, 0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF } },
        // mov rcx, rax
        .{ .inst = .{ .mov_rr = .{ .dst = .rcx, .src = .rax } }, .bytes = &.{ 0x48, 0x89, 0xC1 } },
        // mov r8, r15
        .{ .inst = .{ .mov_rr = .{ .dst = .r8, .src = .r15 } }, .bytes = &.{ 0x4D, 0x89, 0xF8 } },
        // add rbx, rdx
        .{ .inst = .{ .add_rr = .{ .dst = .rbx, .src = .rdx } }, .bytes = &.{ 0x48, 0x01, 0xD3 } },
        // sub rsi, rdi
        .{ .inst = .{ .sub_rr = .{ .dst = .rsi, .src = .rdi } }, .bytes = &.{ 0x48, 0x29, 0xFE } },
        // cmp rax, rax
        .{ .inst = .{ .cmp_rr = .{ .dst = .rax, .src = .rax } }, .bytes = &.{ 0x48, 0x39, 0xC0 } },
        // push rax / push rbp / push r12
        .{ .inst = .{ .push = .rax }, .bytes = &.{0x50} },
        .{ .inst = .{ .push = .rbp }, .bytes = &.{0x55} },
        .{ .inst = .{ .push = .r12 }, .bytes = &.{ 0x41, 0x54 } },
        // pop rbx / pop r13
        .{ .inst = .{ .pop = .rbx }, .bytes = &.{0x5B} },
        .{ .inst = .{ .pop = .r13 }, .bytes = &.{ 0x41, 0x5D } },
        // jmp .+0 ; call .+0
        .{ .inst = .{ .jmp = 0 }, .bytes = &.{ 0xE9, 0, 0, 0, 0 } },
        .{ .inst = .{ .call = 0 }, .bytes = &.{ 0xE8, 0, 0, 0, 0 } },
        // je .+16 ; jne .-1
        .{ .inst = .{ .jcc = .{ .cc = .e, .rel = 16 } }, .bytes = &.{ 0x0F, 0x84, 0x10, 0, 0, 0 } },
        .{ .inst = .{ .jcc = .{ .cc = .ne, .rel = -1 } }, .bytes = &.{ 0x0F, 0x85, 0xFF, 0xFF, 0xFF, 0xFF } },
        // lea rax, [rbx+0x10]   (always-SIB form: 48 8d 84 23 10 00 00 00; SIB=00 100 011, base=rbx)
        .{ .inst = .{ .lea = .{ .dst = .rax, .base = .rbx, .disp = 0x10 } }, .bytes = &.{ 0x48, 0x8D, 0x84, 0x23, 0x10, 0, 0, 0 } },
        // lea rax, [rsp+0x8]
        .{ .inst = .{ .lea = .{ .dst = .rax, .base = .rsp, .disp = 0x8 } }, .bytes = &.{ 0x48, 0x8D, 0x84, 0x24, 0x08, 0, 0, 0 } },
        // lea r8, [r13-4]
        .{ .inst = .{ .lea = .{ .dst = .r8, .base = .r13, .disp = -4 } }, .bytes = &.{ 0x4D, 0x8D, 0x84, 0x25, 0xFC, 0xFF, 0xFF, 0xFF } },
        // ---- jit-codegen-arith new forms (objdump-checked) ----
        // and rbx, rdx
        .{ .inst = .{ .and_rr = .{ .dst = .rbx, .src = .rdx } }, .bytes = &.{ 0x48, 0x21, 0xD3 } },
        // mov rax, [rbx+0x10]   (load; always-SIB, base=rbx)
        .{ .inst = .{ .load = .{ .reg = .rax, .base = .rbx, .disp = 0x10 } }, .bytes = &.{ 0x48, 0x8B, 0x84, 0x23, 0x10, 0, 0, 0 } },
        // mov [rsp+0x8], rax    (store; SIB base=rsp)
        .{ .inst = .{ .store = .{ .reg = .rax, .base = .rsp, .disp = 0x8 } }, .bytes = &.{ 0x48, 0x89, 0x84, 0x24, 0x08, 0, 0, 0 } },
        // mov [r13-4], r8       (store; REX.R+REX.B, base=r13)
        .{ .inst = .{ .store = .{ .reg = .r8, .base = .r13, .disp = -4 } }, .bytes = &.{ 0x4D, 0x89, 0x84, 0x25, 0xFC, 0xFF, 0xFF, 0xFF } },
        // sar rax, 4 ; shl rcx, 4 ; sar r15, 63
        .{ .inst = .{ .sar_ri = .{ .dst = .rax, .imm = 4 } }, .bytes = &.{ 0x48, 0xC1, 0xF8, 0x04 } },
        .{ .inst = .{ .shl_ri = .{ .dst = .rcx, .imm = 4 } }, .bytes = &.{ 0x48, 0xC1, 0xE1, 0x04 } },
        .{ .inst = .{ .sar_ri = .{ .dst = .r15, .imm = 63 } }, .bytes = &.{ 0x49, 0xC1, 0xFF, 0x3F } },
    };
    for (cases, 0..) |c, idx| {
        const enc = encode(c.inst);
        std.testing.expectEqualSlices(u8, c.bytes, enc.slice()) catch |err| {
            std.debug.print("GOLDEN FAIL case {d}: inst={any}\n", .{ idx, c.inst });
            return err;
        };
        // and the golden bytes decode back to the same instruction
        const dec = try decode(c.bytes);
        try std.testing.expect(std.meta.eql(dec.inst, c.inst));
        try std.testing.expectEqual(c.bytes.len, dec.len);
    }
}
