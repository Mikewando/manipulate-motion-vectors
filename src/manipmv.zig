const std = @import("std");
const vapoursynth = @import("vapoursynth");

const vs = vapoursynth.vapoursynth4;

const semver = std.SemanticVersion.parse(@import("config").version) catch unreachable;

const createScaleVect = @import("plugin_functions/scale_vect.zig").createScaleVect;
const createShowVect = @import("plugin_functions/show_vect.zig").createShowVect;
const createExpandAnalysisData = @import("plugin_functions/expand_analysis_data.zig").createExpandAnalysisData;

export fn VapourSynthPluginInit2(plugin: *vs.Plugin, vsapi: *const vs.PLUGINAPI) void {
    _ = vsapi.configPlugin.?("tools.mike.manipmv", "manipmv", "Manipulate Motion Vectors", vs.makeVersion(semver.major, semver.minor), vs.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vsapi.registerFunction.?("ScaleVect", "clip:vnode;scaleX:int:opt;scaleY:int:opt;", "clip:vnode;", createScaleVect, null, plugin);
    _ = vsapi.registerFunction.?("ShowVect", "clip:vnode;vectors:vnode;", "clip:vnode;", createShowVect, null, plugin);
    _ = vsapi.registerFunction.?("ExpandAnalysisData", "clip:vnode;", "clip:vnode;", createExpandAnalysisData, null, plugin);
}
