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

