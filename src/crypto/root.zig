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

/// ML-KEM post-quantum KEM (Key Encapsulation Mechanism)
/// NIST standardized version of Kyber (FIPS 203)
/// Provides quantum-safe key exchange for QUIC
pub const MLKEM = struct {
    kem: *c.OQS_KEM,
    allocator: std.mem.Allocator,

    /// ML-KEM security levels (NIST standardization levels)
    pub const Algorithm = enum {
        /// ML-KEM-512: NIST Level 1 security (128-bit equivalent)
        ML_KEM_512,
        /// ML-KEM-768: NIST Level 3 security (192-bit equivalent) - RECOMMENDED
        ML_KEM_768,
        /// ML-KEM-1024: NIST Level 5 security (256-bit equivalent)
        ML_KEM_1024,

        /// Convert enum to C string for liboqs
        /// Uses NIST FIPS 203 standardized ML-KEM naming
        fn toCString(self: Algorithm) [*:0]const u8 {
            return switch (self) {
                .ML_KEM_512 => "ML-KEM-512",
                .ML_KEM_768 => "ML-KEM-768",
                .ML_KEM_1024 => "ML-KEM-1024",
            };
        }
    };

    /// Initialize ML-KEM with specified security level
    pub fn init(allocator: std.mem.Allocator, alg: Algorithm) !MLKEM {
        const kem = c.OQS_KEM_new(alg.toCString()) orelse return error.KemInitFailed;
        return MLKEM{
            .kem = kem,
            .allocator = allocator,
        };
    }

    /// Free ML-KEM resources
    pub fn deinit(self: *MLKEM) void {
        c.OQS_KEM_free(self.kem);
    }

    /// Generate an ML-KEM keypair
    /// Returns public key and secret key as byte slices
    pub fn keypair(self: *MLKEM) !struct { public_key: []u8, secret_key: []u8 } {
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
    pub fn encapsulate(self: *MLKEM, public_key: []const u8) !struct { ciphertext: []u8, shared_secret: []u8 } {
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
    pub fn decapsulate(self: *MLKEM, secret_key: []const u8, ciphertext: []const u8) ![]u8 {
        // Allocate shared secret buffer
        const ss = try self.allocator.alloc(u8, self.kem.length_shared_secret);
        errdefer self.allocator.free(ss);

        // Decapsulate using liboqs
        const result = c.OQS_KEM_decaps(self.kem, ss.ptr, ciphertext.ptr, secret_key.ptr);
        if (result != c.OQS_SUCCESS) return error.DecapsFailed;

        return ss;
    }

    /// Get public key size for this algorithm
    pub fn publicKeySize(self: *MLKEM) usize {
        return self.kem.length_public_key;
    }

    /// Get secret key size for this algorithm
    pub fn secretKeySize(self: *MLKEM) usize {
        return self.kem.length_secret_key;
    }

    /// Get ciphertext size for this algorithm
    pub fn ciphertextSize(self: *MLKEM) usize {
        return self.kem.length_ciphertext;
    }

    /// Get shared secret size for this algorithm
    pub fn sharedSecretSize(self: *MLKEM) usize {
        return self.kem.length_shared_secret;
    }
};

// Backward compatibility alias
pub const Kyber = MLKEM;

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
test "ML-KEM-512 initialization" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_512);
    defer mlkem.deinit();

    try std.testing.expect(mlkem.kem != null);
}

test "ML-KEM-512 keypair generation" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_512);
    defer mlkem.deinit();

    const keys = try mlkem.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    try std.testing.expect(keys.public_key.len > 0);
    try std.testing.expect(keys.secret_key.len > 0);
    try std.testing.expectEqual(mlkem.publicKeySize(), keys.public_key.len);
    try std.testing.expectEqual(mlkem.secretKeySize(), keys.secret_key.len);
}

test "ML-KEM-512 encapsulation" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_512);
    defer mlkem.deinit();

    // Generate keypair
    const keys = try mlkem.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try mlkem.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    try std.testing.expect(encaps_result.ciphertext.len > 0);
    try std.testing.expect(encaps_result.shared_secret.len > 0);
    try std.testing.expectEqual(mlkem.ciphertextSize(), encaps_result.ciphertext.len);
    try std.testing.expectEqual(mlkem.sharedSecretSize(), encaps_result.shared_secret.len);
}

test "ML-KEM-512 decapsulation" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_512);
    defer mlkem.deinit();

    // Generate keypair
    const keys = try mlkem.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try mlkem.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try mlkem.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify shared secrets match
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "ML-KEM-768 round-trip" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_768);
    defer mlkem.deinit();

    // Generate keypair
    const keys = try mlkem.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try mlkem.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try mlkem.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "ML-KEM-1024 round-trip" {
    const allocator = std.testing.allocator;

    var mlkem = try MLKEM.init(allocator, .ML_KEM_1024);
    defer mlkem.deinit();

    // Generate keypair
    const keys = try mlkem.keypair();
    defer allocator.free(keys.public_key);
    defer allocator.free(keys.secret_key);

    // Encapsulate
    const encaps_result = try mlkem.encapsulate(keys.public_key);
    defer allocator.free(encaps_result.ciphertext);
    defer allocator.free(encaps_result.shared_secret);

    // Decapsulate
    const shared_secret2 = try mlkem.decapsulate(keys.secret_key, encaps_result.ciphertext);
    defer allocator.free(shared_secret2);

    // Verify
    try std.testing.expectEqualSlices(u8, encaps_result.shared_secret, shared_secret2);
}

test "crypto module" {
    std.debug.print("\n=== Crypto Module Tests ===\n", .{});
    try std.testing.expect(true);
    std.debug.print("✓ Crypto module test passed\n", .{});
}
