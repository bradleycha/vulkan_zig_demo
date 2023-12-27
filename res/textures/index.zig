const graphics = @import("graphics");

// TODO: Automate all of this with comptime image parsing.  We shouldn't have
// to manually hard-code this data with raw binary.

pub const TILE = graphics.ImageSource{
   .data    = @embedFile("tile.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

pub const GRASS = graphics.ImageSource{
   .data    = @embedFile("grass.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

pub const ROCK = graphics.ImageSource{
   .data    = @embedFile("rock.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

