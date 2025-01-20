const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;
const zapi = vapoursynth.zigapi;

const util = @import("../util.zig");

const allocator = std.heap.c_allocator;

const FunctionData = struct {
    node: ?*vs.Node,
    node_vi: *const vs.VideoInfo,
    vector_node: ?*vs.Node,
    pel: u32,
    block_size_x: u32,
    block_size_y: u32,
    use_sc_props: bool,
    backwards: bool,
};

// The plugin function logic needs this type info, but it is only available at
// comptime, so we use this wrapper
fn formatHelper(comptime T: type, comptime bits_per_sample: u8) type {
    return struct {
        fn drawVector(
            block_index: u32,
            vector_x: i64,
            vector_y: i64,
            d: *FunctionData,
            stride: u32,
            dst_plane: []u8,
        ) void {
            const width: u32 = @intCast(d.node_vi.width);
            const height: u32 = @intCast(d.node_vi.height);
            const blocks_per_row: u32 = @divExact(width, d.block_size_x);
            const block_center_offset_x: u32 = d.block_size_x / 2;
            const block_center_offset_y: u32 = d.block_size_y / 2;
            const column: u32 = block_index % blocks_per_row;
            const row: u32 = block_index / blocks_per_row;
            const start_coord_x: i64 = (column * d.block_size_x) + block_center_offset_x;
            const start_coord_y: i64 = (row * d.block_size_y) + block_center_offset_y;

            var short_len: i64 = undefined;
            var long_len: i64 = undefined;
            if (vector_x >= vector_y) {
                short_len = @divTrunc(vector_y, d.pel);
                long_len = @divTrunc(vector_x, d.pel);
            } else {
                short_len = @divTrunc(vector_x, d.pel);
                long_len = @divTrunc(vector_y, d.pel);
            }

            const end_val = long_len;

            var increment: i64 = undefined;
            if (long_len < 0) {
                increment = -1;
                long_len = -long_len;
            } else {
                increment = 1;
            }

            var decrement: i64 = undefined;
            if (long_len == 0) {
                decrement = 0;
            } else {
                decrement = @divTrunc(short_len << 16, long_len);
            }

            const bit_diff: u8 = bits_per_sample - 8;
            const max_value: T = (255 << bit_diff) | (255 >> bit_diff);
            const step: T = (95 << bit_diff) | (95 >> bit_diff);

            var i: i64 = 0;
            var j: i64 = 0;
            if (vector_x < vector_y) {
                while (i < end_val) : ({
                    i += increment;
                    j += decrement;
                }) {
                    const coord_x = start_coord_x + (j >> 16);
                    const coord_y = start_coord_y + i;

                    const value: T = @intCast(max_value - @divTrunc(i * step, end_val));
                    const under = coord_x < 0 or coord_y < 0;
                    const over = coord_x >= width or coord_y >= height;
                    if (!under and !over) {
                        const plane_offset = @as(u32, @intCast(coord_y)) * stride + @as(u32, @intCast(coord_x)) * @sizeOf(T);
                        std.mem.writeInt(T, dst_plane[plane_offset..][0..@sizeOf(T)], value, .little);
                    }
                }
            } else {
                while (i < end_val) : ({
                    i += increment;
                    j += decrement;
                }) {
                    const coord_x = start_coord_x + i;
                    const coord_y = start_coord_y + (j >> 16);

                    const value: T = @intCast(max_value - @divTrunc(i * step, end_val));
                    const under = coord_x < 0 or coord_y < 0;
                    const over = coord_x >= width or coord_y >= height;
                    if (!under and !over) {
                        const plane_offset = @as(u32, @intCast(coord_y)) * stride + @as(u32, @intCast(coord_x)) * @sizeOf(T);
                        std.mem.writeInt(T, dst_plane[plane_offset..][0..@sizeOf(T)], value, .little);
                    }
                }
            }
        }

        pub fn getFrame(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
            _ = frame_data;
            const d: *FunctionData = @ptrCast(@alignCast(instance_data));

            if (activation_reason == .Initial) {
                vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
                vsapi.?.requestFrameFilter.?(n, d.vector_node, frame_ctx);
            } else if (activation_reason == .AllFramesReady) {
                var src = zapi.ZFrame.init(d.node, n, frame_ctx, core, vsapi);
                defer src.deinit();
                const dst = src.copyFrame();

                if (d.use_sc_props) {
                    const src_props = src.getProperties();
                    var scene_change = false;
                    if (d.backwards) {
                        scene_change = src_props.getBool("_SceneChangeNext") orelse false;
                    } else {
                        scene_change = src_props.getBool("_SceneChangePrev") orelse src_props.getBool("Scenechange") orelse false;
                    }

                    if (scene_change) {
                        return dst.frame;
                    }
                }

                var vector_src = zapi.ZFrame.init(d.vector_node, n, frame_ctx, core, vsapi);
                defer vector_src.deinit();
                const vector_data = vector_src.getProperties().getData("MVTools_vectors", 0) orelse {
                    return dst.frame;
                };

                var position: u32 = 0;
                const vector_data_size, position = util.readInt(u32, vector_data, position);
                std.debug.assert(vector_data.len == vector_data_size);

                const validity_int, position = util.readInt(u32, vector_data, position);
                if (validity_int != 1) {
                    return dst.frame;
                }

                while (position < vector_data_size) {
                    const level_size, const start_position = util.readInt(u32, vector_data, position);
                    const end_position = position + level_size;
                    position = start_position;
                    // Skip all intermediate levels (for now only support drawing the last level)
                    if (end_position != vector_data_size) {
                        position = end_position;
                        continue;
                    }

                    // Draw the level we care about
                    const stride = dst.getStride(0);
                    const dst_plane = dst.getWriteSlice(0);

                    var block_index: u32 = 0;
                    while (position < end_position) : (block_index += 1) {
                        const vector_x, position = util.readInt(i32, vector_data, position);
                        const vector_y, position = util.readInt(i32, vector_data, position);
                        _, position = util.readInt(u64, vector_data, position);

                        drawVector(
                            block_index,
                            @intCast(vector_x),
                            @intCast(vector_y),
                            d,
                            stride,
                            dst_plane,
                        );
                    }
                }
                return dst.frame;
            }
            return null;
        }
    };
}

export fn freeShowVect(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    vsapi.?.freeNode.?(d.vector_node);
    allocator.destroy(d);
}

pub export fn createShowVect(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: FunctionData = undefined;
    var map_in = zapi.ZMap.init(in, vsapi);
    var map_out = zapi.ZMap.init(out, vsapi);

    d.node, d.node_vi = map_in.getNodeVi("clip");
    d.vector_node = map_in.getNode("vectors");
    const supported_depth = switch (d.node_vi.format.bitsPerSample) {
        8, 10, 12, 16 => true,
        else => false,
    };
    if (d.node_vi.format.sampleType != .Integer or !supported_depth) {
        map_out.setError("ShowVect only supports 8/10/12/16 bit integer input.");
        vsapi.?.freeNode.?(d.node);
        vsapi.?.freeNode.?(d.vector_node);
        return;
    }
    d.use_sc_props = map_in.getBool("useSceneChangeProps") orelse true;

    const peek = vsapi.?.getFrame.?(0, d.vector_node, null, 0);
    defer vsapi.?.freeFrame.?(peek);
    const props = zapi.ZMap.init(vsapi.?.getFramePropertiesRO.?(peek), vsapi);
    const analysis_data = props.getData("MVTools_MVAnalysisData", 0) orelse {
        map_out.setError("ShowVect could not infer analysis metadata.");
        vsapi.?.freeNode.?(d.node);
        vsapi.?.freeNode.?(d.vector_node);
        return;
    };
    std.debug.assert(analysis_data.len == 21 * comptime @sizeOf(u32));
    d.block_size_x, _ = util.readInt(u32, analysis_data, 2 * comptime @sizeOf(u32));
    d.block_size_y, _ = util.readInt(u32, analysis_data, 3 * comptime @sizeOf(u32));
    d.pel, _ = util.readInt(u32, analysis_data, 4 * comptime @sizeOf(u32));
    const backwards, _ = util.readInt(u32, analysis_data, 7 * comptime @sizeOf(u32));
    const width, _ = util.readInt(u32, analysis_data, 10 * comptime @sizeOf(u32));
    const height, _ = util.readInt(u32, analysis_data, 11 * comptime @sizeOf(u32));
    if (d.node_vi.width != width or d.node_vi.height != height) {
        map_out.setError("ShowVect requires that clip and vector dimensions match.");
        vsapi.?.freeNode.?(d.node);
        vsapi.?.freeNode.?(d.vector_node);
        return;
    }
    d.backwards = backwards != 0;

    const data: *FunctionData = allocator.create(FunctionData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
            .requestPattern = .General,
        },
        vs.FilterDependency{
            .source = d.vector_node,
            .requestPattern = .General,
        },
    };
    const getFrameShowVect = switch (d.node_vi.format.bitsPerSample) {
        8 => &formatHelper(u8, 8).getFrame,
        10 => &formatHelper(u16, 10).getFrame,
        12 => &formatHelper(u16, 12).getFrame,
        16 => &formatHelper(u16, 16).getFrame,
        else => unreachable,
    };
    vsapi.?.createVideoFilter.?(out, "ShowVect", d.node_vi, getFrameShowVect, freeShowVect, .Parallel, &deps, deps.len, data, core);
}
