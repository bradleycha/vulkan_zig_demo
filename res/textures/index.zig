const std      = @import("std");
const graphics = @import("graphics");
const textures = @import("textures");

pub const GRASS = graphics.ImageSource{
   .data    = textures.grass.data,
   .format  = .rgba8888,
   .width   = textures.grass.width,
   .height  = textures.grass.height,
};

pub const ROCK = graphics.ImageSource{
   .data    = textures.rock.data,
   .format  = .rgba8888,
   .width   = textures.rock.width,
   .height  = textures.rock.height,
};

pub const TILE = graphics.ImageSource{
   .data    = textures.tile.data,
   .format  = .rgba8888,
   .width   = textures.tile.width,
   .height  = textures.tile.height,
};

