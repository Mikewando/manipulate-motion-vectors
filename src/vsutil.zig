const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;

// TODO use whatever vapoursynth-zig wrapper comes up with instead of this
pub fn getDataProp(vsapi: ?*const vs.API, map: ?*vs.Map, prop: []const u8) ![]const u8 {
    var err: vs.MapPropertyError = undefined;
    const len: u32 = @bitCast(vsapi.?.mapGetDataSize.?(map, prop.ptr, 0, &err));
    if (err != .Success) {
        return error.VapoursynthMapError;
    }
    const data = vsapi.?.mapGetData.?(map, prop.ptr, 0, &err)[0..len];
    if (err != .Success) {
        return error.VapoursynthMapError;
    }
    return data;
}
