const std      = @import("std");
const graphics = @import("graphics");

pub const SHADER_SPV_VERTEX   = @embedFile("shaders/vertex.spv");
pub const SHADER_SPV_FRAGMENT = @embedFile("shaders/fragment.spv");

