//! QUIC-Zig - Modular QUIC Protocol Implementation
//!
//! This is the main entry point that re-exports all modules.
//! Users can either import this for everything, or import specific modules.
const std = @import("std");

pub const core = @import("core/root.zig");
pub const client = @import("client/root.zig");
pub const server = @import("server/root.zig");
pub const crypto = @import("crypto/root.zig");
pub const utils = @import("utils/root.zig");

pub const Connection = core.Connection;
pub const Stream = core.Stream;
pub const Packet = core.Packet;
pub const Client = client.Client;
pub const Server = server.Server;
pub const VarInt = utils.VarInt;
pub const ConnectionId = utils.ConnectionId;
