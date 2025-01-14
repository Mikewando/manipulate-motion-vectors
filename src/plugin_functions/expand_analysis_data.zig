const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;
const zapi = vapoursynth.zigapi;

const util = @import("../util.zig");
const vsutil = @import("../vsutil.zig");

const allocator = std.heap.c_allocator;

const FunctionData = struct {
    node: ?*vs.Node,
    vi: *const vs.VideoInfo,
};

export fn getFrameExpandAnalysisData(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        var src = zapi.Frame.init(d.node, n, frame_ctx, core, vsapi);
        const props = src.getPropertiesRW();

        const analysis_data = vsutil.getDataProp(vsapi, props, "MVTools_MVAnalysisData") catch {
            vsapi.?.setFilterError.?("Could not read MVTools_MVAnalysisData property.", frame_ctx);
            src.deinit();
            return null;
        };
        std.debug.assert(analysis_data.len == 21 * comptime @sizeOf(u32));

        var position: u32 = 0;
        const magic_key, position = util.readInt(u32, analysis_data, position); // (uninitialized)
        _ = vsapi.?.mapSetInt.?(props, "Analysis_MagicKey", magic_key, .Replace);
        const version, position = util.readInt(u32, analysis_data, position); // (uninitialized)
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Version", version, .Replace);
        const block_size_x, position = util.readInt(u32, analysis_data, position);
        const block_size_y, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_BlockSize", block_size_x, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_BlockSize", block_size_y, .Append);
        const pel, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Pel", pel, .Replace);
        const level_count, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_LevelCount", level_count, .Replace);
        const delta_frame, position = util.readInt(i32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_DeltaFrame", delta_frame, .Replace);
        const backwards, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Backwards", backwards, .Replace);
        const cpu_flags, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_CpuFlags", cpu_flags, .Replace);
        const motion_flags, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_MotionFlags", motion_flags, .Replace);
        const width, position = util.readInt(u32, analysis_data, position);
        const height, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_FrameSize", width, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_FrameSize", height, .Append);
        const overlap_x, position = util.readInt(u32, analysis_data, position);
        const overlap_y, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Overlap", overlap_x, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Overlap", overlap_y, .Append);
        const block_count_x, position = util.readInt(u32, analysis_data, position);
        const block_count_y, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_BlockCount", block_count_x, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_BlockCount", block_count_y, .Append);
        const bits_per_sample, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_BitsPerSample", bits_per_sample, .Replace);
        const chroma_ratio_y, position = util.readInt(u32, analysis_data, position);
        const chroma_ratio_x, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_ChromaRatio", chroma_ratio_x, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_ChromaRatio", chroma_ratio_y, .Append);
        const padding_x, position = util.readInt(u32, analysis_data, position);
        const padding_y, position = util.readInt(u32, analysis_data, position);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Padding", padding_x, .Replace);
        _ = vsapi.?.mapSetInt.?(props, "Analysis_Padding", padding_y, .Append);

        return src.frame;
    }
    return null;
}

export fn freeExpandAnalysisData(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    allocator.destroy(d);
}

pub export fn createExpandAnalysisData(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: FunctionData = undefined;
    var map = zapi.Map.init(in, out, vsapi);

    d.node, d.vi = map.getNodeVi("clip");

    const data: *FunctionData = allocator.create(FunctionData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
            .requestPattern = .General,
        },
    };
    vsapi.?.createVideoFilter.?(out, "ExpandAnalysisData", d.vi, getFrameExpandAnalysisData, freeExpandAnalysisData, .Parallel, &deps, deps.len, data, core);
}
