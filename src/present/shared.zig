pub const Compositor = struct {
   pub const ConnectError = error {
      OutOfMemory,
      Unavailable,
      PlatformError,
   };
};

