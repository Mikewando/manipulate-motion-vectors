const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;
const ZAPI = vapoursynth.ZAPI;

const util = @import("../util.zig");

const allocator = std.heap.c_allocator;

const FunctionData = struct {
    node: ?*vs.Node,
    vi: *const vs.VideoInfo,
    scale_x: u8,
    scale_y: u8,
};

pub fn scaleAnalysisData(in: []const u8, out: []u8, scale_x: u8, scale_y: u8) void {
    var position: u32 = 0;
    position = util.scaleInt(u32, in, out, position, scale_x); // block_size_x
    position = util.scaleInt(u32, in, out, position, scale_y); // block_size_y
    position = util.scaleInt(u32, in, out, position, scale_x); // width
    position = util.scaleInt(u32, in, out, position, scale_y); // height
    position = util.scaleInt(u32, in, out, position, scale_x); // overlap_x
    position = util.scaleInt(u32, in, out, position, scale_y); // overlap_y
    position = util.scaleInt(u32, in, out, position, scale_x); // padding_x
    position = util.scaleInt(u32, in, out, position, scale_y); // padding_y
}

test {
    const input = [_]u8{ 1, 0, 0, 0 } ** 21;
    var output = [_]u8{ 0, 0, 0, 0 } ** 21;

    scaleAnalysisData(input[0..], output[0..], 2, 4);

    try std.testing.expectEqual(1, std.mem.readInt(u32, output[0..4], .little));
    try std.testing.expectEqual(2, std.mem.readInt(u32, output[2 * @sizeOf(u32) ..][0..4], .little));
    try std.testing.expectEqual(4, std.mem.readInt(u32, output[3 * @sizeOf(u32) ..][0..4], .little));
}

pub fn scaleVectorData(in: []const u8, out: []u8, scale_x: u8, scale_y: u8) void {
    var position: u32 = 0;
    const size, position = util.readAndCopyInt(u32, in, out, position);
    std.debug.assert(in.len == size);

    const validity_int, position = util.readAndCopyInt(u32, in, out, position);
    if (validity_int == 1) {
        while (position < size) {
            const level_size, const start_position = util.readAndCopyInt(u32, in, out, position);
            const end_position = position + level_size;
            position = start_position;
            while (position < end_position) {
                position = util.scaleInt(i32, in, out, position, scale_x); // x
                position = util.scaleInt(i32, in, out, position, scale_y); // y
                position = util.scaleInt(u64, in, out, position, scale_x * scale_y); // SAD
            }
        }
    }
}

test {
    const single_vector = [_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0 }; // (1, 2, 3)
    const vectors = single_vector ** 10;
    const level_size = [_]u8{ vectors.len + @sizeOf(u32), 0, 0, 0 };
    const valid = [_]u8{ 1, 0, 0, 0 };
    const total_size = [_]u8{ vectors.len + valid.len + level_size.len + @sizeOf(u32), 0, 0, 0 };
    const input = total_size ++ valid ++ level_size ++ vectors;
    var output = [_]u8{0} ** input.len;

    scaleVectorData(input[0..], output[0..], 2, 4);

    try std.testing.expectEqual(2, std.mem.readInt(i32, output[3 * @sizeOf(u32) ..][0..4], .little));
    try std.testing.expectEqual(8, std.mem.readInt(i32, output[4 * @sizeOf(u32) ..][0..4], .little));
    try std.testing.expectEqual(24, std.mem.readInt(u64, output[5 * @sizeOf(u32) ..][0..8], .little));
}

export fn getFrameScaleVect(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) ?*const vs.Frame {
    _ = frame_data;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));
    const zapi = ZAPI.init(vsapi, core, frame_ctx);

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        var src = zapi.initZFrame(d.node, n);
        var dst = src.copyFrame();
        defer src.deinit();

        const src_props = src.getPropertiesRO();
        const dst_props = dst.getPropertiesRW();

        // *** Scale analysis data ***

        const block_size_x: u32 = src_props.getInt(u32, "MVUtensilsAnalysisBlkSizeX") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisBlkSizeX property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisBlkSizeX", block_size_x * d.scale_x, .Replace);

        const block_size_y: u32 = src_props.getInt(u32, "MVUtensilsAnalysisBlkSizeY") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisBlkSizeY property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisBlkSizeY", block_size_y * d.scale_y, .Replace);

        const width: u32 = src_props.getInt(u32, "MVUtensilsAnalysisWidth") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisWidth property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisWidth", width * d.scale_x, .Replace);

        const height: u32 = src_props.getInt(u32, "MVUtensilsAnalysisHeight") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisHeight property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisHeight", height * d.scale_y, .Replace);

        const real_width: u32 = src_props.getInt(u32, "MVUtensilsAnalysisRealWidth") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisRealWidth property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisRealWidth", real_width * d.scale_x, .Replace);

        const real_height: u32 = src_props.getInt(u32, "MVUtensilsAnalysisRealHeight") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisRealHeight property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisRealHeight", real_height * d.scale_y, .Replace);

        const overlap_x: u32 = src_props.getInt(u32, "MVUtensilsAnalysisOverlapX") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisOverlapX property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisOverlapX", overlap_x * d.scale_x, .Replace);

        const overlap_y: u32 = src_props.getInt(u32, "MVUtensilsAnalysisOverlapY") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisOverlapY property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisOverlapY", overlap_y * d.scale_y, .Replace);

        const padding_x: u32 = src_props.getInt(u32, "MVUtensilsAnalysisHPad") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisHPad property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisHPad", padding_x * d.scale_x, .Replace);

        const padding_y: u32 = src_props.getInt(u32, "MVUtensilsAnalysisVPad") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisVPad property.", frame_ctx);
            dst.deinit();
            return null;
        };
        dst_props.setInt("MVUtensilsAnalysisVPad", padding_y * d.scale_y, .Replace);

        // *** Scale vectors ***

        const vector_data_in = src_props.getIntArray("MVUtensilsAnalysisVectors") orelse {
            vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisVectors property.", frame_ctx);
            dst.deinit();
            return null;
        };

        const vector_data_out = allocator.alloc(i64, vector_data_in.len) catch unreachable;
        defer allocator.free(vector_data_out);

        for (vector_data_in, 0..) |vectors, block_index| {
            const vector_x = @as(i32, @truncate(vectors));
            const vector_y = @as(i32, @truncate(vectors >> 32));

            vector_data_out[block_index] = (vector_x * d.scale_x) | (@as(i64, vector_y * d.scale_y) << 32);
        }

        dst_props.setIntArray("MVUtensilsAnalysisVectors", vector_data_out);

        return dst.frame;
    }
    return null;
}

export fn freeScaleVect(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) void {
    _ = core;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    allocator.destroy(d);
}

pub export fn createScaleVect(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) void {
    _ = user_data;
    var d: FunctionData = undefined;
    const zapi = ZAPI.init(vsapi, core, null);
    var map_in = zapi.initZMap(in);

    d.node, d.vi = map_in.getNodeVi("clip").?;

    d.scale_x = map_in.getInt(u8, "scaleX") orelse 1;
    d.scale_y = map_in.getInt(u8, "scaleY") orelse d.scale_x;

    const data: *FunctionData = allocator.create(FunctionData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
            .requestPattern = .General,
        },
    };
    vsapi.?.createVideoFilter.?(out, "ScaleVect", d.vi, getFrameScaleVect, freeScaleVect, .Parallel, &deps, deps.len, data, core);
}
