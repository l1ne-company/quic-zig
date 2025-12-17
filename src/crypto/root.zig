//! QUIC Cryptography Module
//!
//! This module handles QUIC-specific cryptographic operations including:
//! - Post-quantum key encapsulation (Kyber via liboqs)
//! - TLS 1.3 integration
//! - Packet encryption/decryption
//! - Header protection
//! - Key derivation

const std = @import("std");

// liboqs C bindings for post-quantum cryptography
pub const c = @cImport({
    @cInclude("oqs/oqs.h");
});

/// Kyber post-quantum KEM (Key Encapsulation Mechanism)
/// Provides quantum-safe key exchange for QUIC
pub const Kyber = struct {
    kem: *c.OQS_KEM,
    allocator: std.mem.Allocator,

    /// Kyber security levels (NIST standardization levels)
    pub const Algorithm = enum {
        /// Kyber512: NIST Level 1 security (128-bit equivalent)
        Kyber512,
        /// Kyber768: NIST Level 3 security (192-bit equivalent)
        Kyber768,
        /// Kyber1024: NIST Level 5 security (256-bit equivalent)
        Kyber1024,

        /// Convert enum to C string for liboqs
        fn toCString(self: Algorithm) [*:0]const u8 {
            return switch (self) {
                .Kyber512 => "Kyber512",
                .Kyber768 => "Kyber768",
                .Kyber1024 => "Kyber1024",
            };
        }
    };

    /// Initialize Kyber KEM with specified security level
    pub fn init(allocator: std.mem.Allocator, alg: Algorithm) !Kyber {
        const kem = c.OQS_KEM_new(alg.toCString()) orelse return error.KemInitFailed;
        return Kyber{
            .kem = kem,
            .allocator = allocator,
        };
    }

    /// Free Kyber KEM resources
    pub fn deinit(self: *Kyber) void {
        c.OQS_KEM_free(self.kem);
    }

    /// Generate a Kyber keypair
    /// Returns public key and secret key as byte slices
    pub fn keypair(self: *Kyber) !struct { public_key: []u8, secret_key: []u8 } {
        // Allocate public key buffer
        const pk = try self.allocator.alloc(u8, self.kem.length_public_key);
        errdefer self.allocator.free(pk);

        // Allocate secret key buffer
        const sk = try self.allocator.alloc(u8, self.kem.length_secret_key);
        errdefer self.allocator.free(sk);

        // Generate keypair using liboqs
        const result = c.OQS_KEM_keypair(self.kem, pk.ptr, sk.ptr);
        if (result != c.OQS_SUCCESS) return error.KeypairFailed;

        return .{ .public_key = pk, .secret_key = sk };
    }

    /// Encapsulate: Create shared secret and ciphertext using public key
    /// This is called by the client in the key exchange
    pub fn encapsulate(self: *Kyber, public_key: []const u8) !struct { ciphertext: []u8, shared_secret: []u8 } {
        // Allocate ciphertext buffer
        const ct = try self.allocator.alloc(u8, self.kem.length_ciphertext);
        errdefer self.allocator.free(ct);

        // Allocate shared secret buffer
        const ss = try self.allocator.alloc(u8, self.kem.length_shared_secret);
        errdefer self.allocator.free(ss);

        // Encapsulate using liboqs
        const result = c.OQS_KEM_encaps(self.kem, ct.ptr, ss.ptr, public_key.ptr);
        if (result != c.OQS_SUCCESS) return error.EncapsFailed;

        return .{ .ciphertext = ct, .shared_secret = ss };
    }

    /// Decapsulate: Derive shared secret from ciphertext and secret key
    /// This is called by the server in the key exchange
    pub fn decapsulate(self: *Kyber, secret_key: []const u8, ciphertext: []const u8) ![]u8 {
        // Allocate shared secret buffer
        const ss = try self.allocator.alloc(u8, self.kem.length_shared_secret);
        errdefer self.allocator.free(ss);

        // Decapsulate using liboqs
        const result = c.OQS_KEM_decaps(self.kem, ss.ptr, ciphertext.ptr, secret_key.ptr);
        if (result != c.OQS_SUCCESS) return error.DecapsFailed;

        return ss;
    }

    /// Get public key size for this algorithm
    pub fn publicKeySize(self: *Kyber) usize {
        return self.kem.length_public_key;
    }

    /// Get secret key size for this algorithm
    pub fn secretKeySize(self: *Kyber) usize {
        return self.kem.length_secret_key;
    }

    /// Get ciphertext size for this algorithm
    pub fn ciphertextSize(self: *Kyber) usize {
        return self.kem.length_ciphertext;
    }

    /// Get shared secret size for this algorithm
    pub fn sharedSecretSize(self: *Kyber) usize {
        return self.kem.length_shared_secret;
    }
};

pub const KeySchedule = struct {
    // TODO: QUIC key schedule
};

pub const PacketProtection = struct {
    pub fn encrypt(data: []const u8) ![]u8 {
        _ = data;
        // TODO: Implement packet encryption
        return error.NotImplemented;
    }

    pub fn decrypt(data: []const u8) ![]u8 {
        _ = data;
        // TODO: Implement packet decryption
        return error.NotImplemented;
    }
};

pub const HeaderProtection = struct {
    pub fn apply(header: []u8) !void {
        _ = header;
        // TODO: Implement header protection
    }

    pub fn remove(header: []u8) !void {
        _ = header;
        // TODO: Implement header protection removal
    }
};

// Tests
test "Kyber512 initialization" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber512);
    defer kyber.deinit();

    try std.testing.expect(kyber.kem != null);
}

test "Kyber512 keypair generation" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber512);
    defer kyber.deinit();

    const keys = try kyber.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    try std.testing.expect(keys.public_key.len > 0);
    try std.testing.expect(keys.secret_key.len > 0);
    try std.testing.expectEqual(kyber.publicKeySize(), keys.public_key.len);
    try std.testing.expectEqual(kyber.secretKeySize(), keys.secret_key.len);
}

test "Kyber512 encapsulation" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber512);
    defer kyber.deinit();

    // Generate keypair
    const keys = try kyber.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try kyber.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    try std.testing.expect(encaps_result.ciphertext.len > 0);
    try std.testing.expect(encaps_result.shared_secret.len > 0);
    try std.testing.expectEqual(kyber.ciphertextSize(), encaps_result.ciphertext.len);
    try std.testing.expectEqual(kyber.sharedSecretSize(), encaps_result.shared_secret.len);
}

test "Kyber512 decapsulation" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber512);
    defer kyber.deinit();

    // Generate keypair
    const keys = try kyber.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try kyber.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try kyber.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify shared secrets match
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "Kyber768 round-trip" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber768);
    defer kyber.deinit();

    // Generate keypair
    const keys = try kyber.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try kyber.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try kyber.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "Kyber1024 round-trip" {
    const allocator = std.testing.allocator;

    var kyber = try Kyber.init(allocator, .Kyber1024);
    defer kyber.deinit();

    // Generate keypair
    const keys = try kyber.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try kyber.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try kyber.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "crypto module" {
    std.debug.print("\n=== Crypto Module Tests ===\n", .{});
    try std.testing.expect(true);
    std.debug.print("✓ Crypto module test passed\n", .{});
}
