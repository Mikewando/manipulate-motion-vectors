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
    position = util.copyInt(u32, in, out, position); // magic_key (uninitialized)
    position = util.copyInt(u32, in, out, position); // version (uninitialized)
    position = util.scaleInt(u32, in, out, position, scale_x); // block_size_x
    position = util.scaleInt(u32, in, out, position, scale_y); // block_size_y
    position = util.copyInt(u32, in, out, position); // pel
    position = util.copyInt(u32, in, out, position); // level_count
    position = util.copyInt(i32, in, out, position); // delta_frame
    position = util.copyInt(u32, in, out, position); // backwards
    position = util.copyInt(u32, in, out, position); // cpu_flags
    position = util.copyInt(u32, in, out, position); // motion_flags
    position = util.scaleInt(u32, in, out, position, scale_x); // width
    position = util.scaleInt(u32, in, out, position, scale_y); // height
    position = util.scaleInt(u32, in, out, position, scale_x); // overlap_x
    position = util.scaleInt(u32, in, out, position, scale_y); // overlap_y
    position = util.copyInt(u32, in, out, position); // block_count_x
    position = util.copyInt(u32, in, out, position); // block_count_y
    position = util.copyInt(u32, in, out, position); // bits_per_sample
    position = util.copyInt(u32, in, out, position); // chroma_ratio_y
    position = util.copyInt(u32, in, out, position); // chroma_ratio_x
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

        const analysis_data_in = src_props.getData("MVTools_MVAnalysisData", 0) orelse {
            vsapi.?.setFilterError.?("Could not read MVTools_MVAnalysisData property when attempting to scale vectors.", frame_ctx);
            dst.deinit();
            return null;
        };
        std.debug.assert(analysis_data_in.len == 21 * comptime @sizeOf(u32));

        const analysis_data_out = allocator.allocSentinel(u8, analysis_data_in.len, 0) catch {
            vsapi.?.setFilterError.?("Out of memory", frame_ctx);
            dst.deinit();
            return null;
        };
        defer allocator.free(analysis_data_out);

        scaleAnalysisData(analysis_data_in, analysis_data_out[0..analysis_data_in.len], d.scale_x, d.scale_y);

        dst_props.setData("MVTools_MVAnalysisData", analysis_data_out, .Binary, .Replace);

        // *** Scale vectors ***

        const vector_data_in = src_props.getData("MVTools_vectors", 0) orelse {
            vsapi.?.setFilterError.?("Could not read MVTools_vectors property when attempting to scale vectors.", frame_ctx);
            dst.deinit();
            return null;
        };

        const vector_data_out = allocator.alloc(u8, vector_data_in.len + 1) catch unreachable;
        defer allocator.free(vector_data_out);

        scaleVectorData(vector_data_in, vector_data_out[0..vector_data_in.len], d.scale_x, d.scale_y);
        vector_data_out[vector_data_in.len] = 0;

        dst_props.setData("MVTools_vectors", vector_data_out[0..vector_data_in.len :0], .Binary, .Replace);

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
