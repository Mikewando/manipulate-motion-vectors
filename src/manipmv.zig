const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;
const zapi = vapoursynth.zigapi;

const semver = std.SemanticVersion.parse(@import("config").version) catch unreachable;
const allocator = std.heap.c_allocator;

const ScaleVectData = struct {
    node: ?*vs.Node,
    vi: *const vs.VideoInfo,
    scale_x: u8,
    scale_y: u8,
};

fn readAndCopyInt(comptime T: type, input_buffer: [*]const u8, output_buffer: []u8, position: u32) struct { T, u32 } {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value, .little);
    return .{ value, position + size };
}

fn copyInt(comptime T: type, input_buffer: [*]const u8, output_buffer: []u8, position: u32) u32 {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value, .little);
    return position + size;
}

fn scaleInt(comptime T: type, input_buffer: [*]const u8, output_buffer: []u8, position: u32, scale: u8) u32 {
    const size = comptime @sizeOf(T);
    const value = std.mem.readInt(T, input_buffer[position..][0..size], .little);
    std.mem.writeInt(T, output_buffer[position..][0..size], value * scale, .little);
    return position + size;
}

export fn getFrameScaleVect(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *ScaleVectData = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        const src = zapi.Frame.init(d.node, n, frame_ctx, core, vsapi);
        const props = src.getPropertiesRW();
        var err: vs.MapPropertyError = undefined;

        // *** Scale analysis data ***

        const analysis_data_in = vsapi.?.mapGetData.?(props, "MVTools_MVAnalysisData", 0, &err);
        if (err != .Success) {
            vsapi.?.setFilterError.?("Could not read MVTools_MVAnalysisData property when attempting to scale vectors.", frame_ctx);
            return null;
        }
        const analysis_data_len: u32 = @intCast(vsapi.?.mapGetDataSize.?(props, "MVTools_MVAnalysisData", 0, &err));
        if (err != .Success) {
            vsapi.?.setFilterError.?("Could not read MVTools_MVAnalysisData property when attempting to scale vectors.", frame_ctx);
            return null;
        }
        std.debug.assert(analysis_data_len == 21 * comptime @sizeOf(u32));

        const analysis_data_out = allocator.alloc(u8, analysis_data_len) catch unreachable;
        defer allocator.free(analysis_data_out);

        var position: u32 = 0;
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // magic_key (uninitialized)
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // version (uninitialized)
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_x); // block_size_x
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_y); // block_size_y
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // pel
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // level_count
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // delta_frame
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // backwards
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // cpu_flags
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // motion_flags
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_x); // width
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_y); // height
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_x); // overlap_x
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_y); // overlap_y
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // block_count_x
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // block_count_y
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // bits_per_sample
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // chroma_ratio_y
        position = copyInt(u32, analysis_data_in, analysis_data_out, position); // chroma_ratio_x
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_x); // padding_x
        position = scaleInt(u32, analysis_data_in, analysis_data_out, position, d.scale_y); // padding_y

        _ = vsapi.?.mapSetData.?(props, "MVTools_MVAnalysisData", analysis_data_out.ptr, @intCast(analysis_data_len), .Binary, .Replace);

        // *** Scale vectors ***

        const vector_data_in = vsapi.?.mapGetData.?(props, "MVTools_vectors", 0, &err);
        if (err != .Success) {
            vsapi.?.setFilterError.?("Could not read MVTools_vectors property when attempting to scale vectors.", frame_ctx);
            return null;
        }
        const vector_data_len: u32 = @intCast(vsapi.?.mapGetDataSize.?(props, "MVTools_vectors", 0, &err));
        if (err != .Success) {
            vsapi.?.setFilterError.?("Could not read MVTools_vectors property when attempting to scale vectors.", frame_ctx);
            return null;
        }

        const vector_data_out = allocator.alloc(u8, vector_data_len) catch unreachable;
        defer allocator.free(vector_data_out);

        position = 0;
        const size, position = readAndCopyInt(u32, vector_data_in, vector_data_out, position);
        std.debug.assert(vector_data_len == size);

        const validity_int, position = readAndCopyInt(u32, vector_data_in, vector_data_out, position);
        if (validity_int == 1) {
            while (position < size) {
                const level_size, const start_position = readAndCopyInt(u32, vector_data_in, vector_data_out, position);
                const end_position = position + level_size;
                position = start_position;
                while (position < end_position) {
                    position = scaleInt(i32, vector_data_in, vector_data_out, position, d.scale_x); // x
                    position = scaleInt(i32, vector_data_in, vector_data_out, position, d.scale_y); // y
                    position = scaleInt(u64, vector_data_in, vector_data_out, position, d.scale_x * d.scale_y); // SAD
                }
            }
        }

        _ = vsapi.?.mapSetData.?(props, "MVTools_vectors", vector_data_out.ptr, @intCast(vector_data_len), .Binary, .Replace);

        return src.frame;
    }
    return null;
}

export fn freeScaleVect(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *ScaleVectData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    allocator.destroy(d);
}

export fn createScaleVect(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: ScaleVectData = undefined;
    var map = zapi.Map.init(in, out, vsapi);

    d.node, d.vi = map.getNodeVi("clip");

    d.scale_x = map.getInt(u8, "scaleX") orelse 1;
    d.scale_y = map.getInt(u8, "scaleY") orelse d.scale_x;

    const data: *ScaleVectData = allocator.create(ScaleVectData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
            .requestPattern = .General,
        },
    };
    vsapi.?.createVideoFilter.?(out, "ScaleVect", d.vi, getFrameScaleVect, freeScaleVect, .Parallel, &deps, deps.len, data, core);
}

export fn VapourSynthPluginInit2(plugin: *vs.Plugin, vsapi: *const vs.PLUGINAPI) void {
    _ = vsapi.configPlugin.?("tools.mike.manipmv", "manipmv", "Manipulate Motion Vectors", vs.makeVersion(semver.major, semver.minor), vs.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vsapi.registerFunction.?("ScaleVect", "clip:vnode;scaleX:int:opt;scaleY:int:opt;", "clip:vnode;", createScaleVect, null, plugin);
}
