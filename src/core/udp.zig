const std = @import("std");
const posix = std.posix;
    
const socket = struct {
    pub fn new() !void {
        // TODO: add addr set 
        try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    }
    
    pub fn send()!void{}
    pub fn receive(){};
    pub fn kill(){};
};

defer posix.close(socket);
 
