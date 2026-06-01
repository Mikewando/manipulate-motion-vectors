const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;
const ZAPI = vapoursynth.ZAPI;

const util = @import("../util.zig");

const allocator = std.heap.c_allocator;

const FunctionData = struct {
    node: ?*vs.Node,
    node_vi: *const vs.VideoInfo,
    use_sc_props: bool,
};

// The plugin function logic needs this type info, but it is only available at
// comptime, so we use this wrapper
fn formatHelper(comptime T: type, comptime bits_per_sample: u8) type {
    return struct {
        fn drawVector(
            block_index: u32,
            vector_x: i64,
            vector_y: i64,
            width: u32,
            height: u32,
            block_size_x: u32,
            block_size_y: u32,
            overlap_x: u32,
            overlap_y: u32,
            pel: u32,
            stride: u32,
            dst_plane: []u8,
        ) void {
            const stride_x = block_size_x - overlap_x;
            const stride_y = block_size_y - overlap_y;
            const blocks_per_row: u32 = (width - block_size_x) / stride_x + 1;
            const block_center_offset_x: u32 = block_size_x / 2;
            const block_center_offset_y: u32 = block_size_y / 2;
            const column: u32 = block_index % blocks_per_row;
            const row: u32 = block_index / blocks_per_row;
            const start_coord_x: i64 = column * stride_x + block_center_offset_x;
            const start_coord_y: i64 = row * stride_y + block_center_offset_y;

            var short_len: i64 = undefined;
            var long_len: i64 = undefined;
            if (vector_x >= vector_y) {
                short_len = @divTrunc(vector_y, pel);
                long_len = @divTrunc(vector_x, pel);
            } else {
                short_len = @divTrunc(vector_x, pel);
                long_len = @divTrunc(vector_y, pel);
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

        pub fn getFrame(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) ?*const vs.Frame {
            _ = frame_data;
            const d: *FunctionData = @ptrCast(@alignCast(instance_data));
            const zapi = ZAPI.init(vsapi, core, frame_ctx);

            if (activation_reason == .Initial) {
                vsapi.?.requestFrameFilter.?(n, d.node, frame_ctx);
            } else if (activation_reason == .AllFramesReady) {
                var src = zapi.initZFrame(d.node, n);
                defer src.deinit();
                const src_props = src.getPropertiesRO();
                const dst = src.copyFrame();

                if (d.use_sc_props) {
                    const delta: u32 = src_props.getInt(u32, "MVUtensilsAnalysisDeltaFrame") orelse {
                        return dst.frame;
                    };
                    const backwards = delta < 0;
                    var scene_change = false;
                    if (backwards) {
                        scene_change = src_props.getBool("_SceneChangeNext") orelse false;
                    } else {
                        scene_change = src_props.getBool("_SceneChangePrev") orelse false;
                    }

                    if (scene_change) {
                        return dst.frame;
                    }
                }

                const vector_data = src_props.getData("MVUtensilsAnalysisVectors", 0) orelse {
                    // No usable vectors
                    return dst.frame;
                };
                const width: u32 = @intCast(d.node_vi.width);
                const height: u32 = @intCast(d.node_vi.height);
                // TODO this should have less boilerplate
                const block_size_x: u32 = src_props.getInt(u32, "MVUtensilsAnalysisBlkSizeX") orelse {
                    vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisBlkSizeX property.", frame_ctx);
                    dst.deinit();
                    return null;
                };
                const block_size_y: u32 = src_props.getInt(u32, "MVUtensilsAnalysisBlkSizeY") orelse {
                    vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisBlkSizeY property.", frame_ctx);
                    dst.deinit();
                    return null;
                };
                const overlap_x: u32 = src_props.getInt(u32, "MVUtensilsAnalysisOverlapX") orelse {
                    vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisOverlapX property.", frame_ctx);
                    dst.deinit();
                    return null;
                };
                const overlap_y: u32 = src_props.getInt(u32, "MVUtensilsAnalysisOverlapY") orelse {
                    vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisOverlapY property.", frame_ctx);
                    dst.deinit();
                    return null;
                };
                const pel: u32 = src_props.getInt(u32, "MVUtensilsAnalysisPel") orelse {
                    vsapi.?.setFilterError.?("Could not read MVUtensilsAnalysisPel property.", frame_ctx);
                    dst.deinit();
                    return null;
                };

                var position: u32 = 0;
                while (position < vector_data.len) {
                    const stride = dst.getStride(0);
                    const dst_plane = dst.getWriteSlice(0);

                    var block_index: u32 = 0;
                    while (position < vector_data.len) : (block_index += 1) {
                        const vector_x, position = util.readInt(i32, vector_data, position);
                        const vector_y, position = util.readInt(i32, vector_data, position);
                        _, position = util.readInt(u64, vector_data, position);

                        drawVector(
                            block_index,
                            @intCast(vector_x),
                            @intCast(vector_y),
                            width,
                            height,
                            block_size_x,
                            block_size_y,
                            overlap_x,
                            overlap_y,
                            pel,
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

export fn freeShowVect(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) void {
    _ = core;
    const d: *FunctionData = @ptrCast(@alignCast(instance_data));
    vsapi.?.freeNode.?(d.node);
    //vsapi.?.freeNode.?(d.vector_node);
    allocator.destroy(d);
}

pub export fn createShowVect(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.c) void {
    _ = user_data;
    var d: FunctionData = undefined;
    const zapi = ZAPI.init(vsapi, core, null);
    var map_in = zapi.initZMap(in);
    var map_out = zapi.initZMap(out);

    d.node, d.node_vi = map_in.getNodeVi("clip").?;
    const supported_depth = switch (d.node_vi.format.bitsPerSample) {
        8, 10, 12, 16 => true,
        else => false,
    };
    if (d.node_vi.format.sampleType != .Integer or !supported_depth) {
        map_out.setError("ShowVect only supports 8/10/12/16 bit integer input.");
        vsapi.?.freeNode.?(d.node);
        return;
    }
    d.use_sc_props = map_in.getBool("useSceneChangeProps") orelse true;

    const data: *FunctionData = allocator.create(FunctionData) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node,
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
