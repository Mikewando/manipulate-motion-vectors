const std = @import("std");

pub fn readInt(comptime T: type, input_buffer: []const u8, position: u32) struct { T, u32 } {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    return .{ value, position + size };
}

test {
    var position: u32 = 0;
    const input = [_]u8{ 2, 0, 0, 0 };
    const value, position = readInt(u32, input[0..], position);
    try std.testing.expectEqual(comptime @sizeOf(u32), position);
    try std.testing.expectEqual(2, value);
}

pub fn readAndCopyInt(comptime T: type, input_buffer: []const u8, output_buffer: []u8, position: u32) struct { T, u32 } {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value, .little);
    return .{ value, position + size };
}

test {
    var position: u32 = 0;
    const input = [_]u8{ 2, 0, 0, 0 };
    var output = [_]u8{ 0, 0, 0, 0 };
    const value, position = readAndCopyInt(u32, input[0..], output[0..], position);
    try std.testing.expectEqual(comptime @sizeOf(u32), position);
    try std.testing.expectEqual(2, value);
    try std.testing.expectEqual(2, output[0]);
}

pub fn copyInt(comptime T: type, input_buffer: []const u8, output_buffer: []u8, position: u32) u32 {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value, .little);
    return position + size;
}

test {
    var position: u32 = 0;
    const input = [_]u8{ 2, 0, 0, 0 };
    var output = [_]u8{ 0, 0, 0, 0 };
    position = copyInt(u32, input[0..], output[0..], position);
    try std.testing.expectEqual(comptime @sizeOf(u32), position);
    try std.testing.expectEqual(2, output[0]);
}

pub fn scaleInt(comptime T: type, input_buffer: []const u8, output_buffer: []u8, position: u32, scale: u8) u32 {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value * scale, .little);
    return position + size;
}

test {
    var position: u32 = 0;
    const input = [_]u8{ 2, 0, 0, 0 };
    var output = [_]u8{ 0, 0, 0, 0 };
    position = scaleInt(u32, input[0..], output[0..], position, 2);
    try std.testing.expectEqual(comptime @sizeOf(u32), position);
    try std.testing.expectEqual(4, output[0]);
}
