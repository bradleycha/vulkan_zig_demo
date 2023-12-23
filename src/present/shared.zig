pub const Compositor = struct {
   pub const ConnectError = error {
      OutOfMemory,
      Unavailable,
      PlatformError,
   };
};

pub const Window = struct {
   pub const CreateInfo = struct {
      title          : [:0] const u8,
      display_mode   : DisplayMode,
   };

   pub const DisplayModeTag = enum {
      windowed,
      fullscreen,
   };

   pub const DisplayMode = union(DisplayModeTag) {
      windowed    : Resolution,
      fullscreen  : void,
   };

   pub const Resolution = struct {
      width    : u32,
      height   : u32,
   };

   pub const CreateError = error {
      OutOfMemory,
      DisplayModeUnavailable,
      GraphicsApiUnavailable,
      PlatformError,
   };

   pub const PollEventsError = error {
      OutOfMemory,
      PlatformError,
   };
};

pub fn BindSet(comptime bind_type : type) type {
   // TODO: Check bind type for inconsistencies, maybe generate the bind enum
   // from a comptime map?

   return struct {
      exit           : bind_type,
      toggle_focus   : bind_type,
      move_forward   : bind_type,
      move_backward  : bind_type,
      move_left      : bind_type,
      move_right     : bind_type,
      move_up        : bind_type,
      move_down      : bind_type,
      respawn        : bind_type,
   };
}

