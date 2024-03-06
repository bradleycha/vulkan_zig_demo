# Vulkan Zig Demo
Vulkan graphics programming example in Zig with minimal dependencies and as much programmed from scratch as I could tolerate.

![alt text](https://github.com/bradleycha/vulkan_zig_demo/raw/master/demonstration.gif)

### Supported platforms
 - Linux with either X11 or Wayland desktops

### Build Requirements
 - [Zig compiler](https://ziglang.org/learn/getting-started/#installing-zig)
 - libxcb when targetting X11
 - libwayland when targetting Wayland

### Building
For targetting X11:
```
zig build -Doptimize=ReleaseFast -Dpresent-backend=xcb
```

For targetting Wayland:
```
zig build -Doptimize=ReleaseFast -Dpresent-backend=wayland
```

The program executable will be found at "zig-out/bin/learn\_graphics\_zig"

### Controlling
Name | Keybind 
-----|--------
Close window | Escape
Grab/release mouse | Tab
Move forward | W
Move backward | S
Move left | A
Move right | D
Move up | Space
Move down | Left shift
Look up | Up arrow
Look down | Down arrow
Look left | Left arrow
Look right | Right arrow
Accelerate | Left Control
Decelerate | Left Alt
Reset camera | R

### Dependencies and implemented features
This program was made to use only minimal system dependencies.  The following are the only system library dependencies:
 - Vulkan graphics API (libvulkan)
 - XCB for X11 desktops (libxcb)
 - Wayland Client for Wayland desktops (libwayland-client)
 - System dynamic linker

The following is a list of most features which were implemented from scratch and can referenced for those wanting to learn Zig or graphics programming:
 - Novice-level Vulkan graphics API usage
 - Windowing/input abstraction
 - Asynchronous graphics rendering without multithreading
 - Asynchronous and batched resource loading
 - Vulkan memory heap implementation to manually manage device memory
 - Perfect linear and non-linear delta-time calculation for camera movement
 - Custom Zig build runner steps to compile resources as part of the build process
 - GLSL to SPIR-V shader compilation using ```glslc```
 - Compile-time Targa (.tga) image parsing
 - Compile-time PLY mesh parsing
 - Embedding of resources statically to avoid dynamic memory allocations and File I/O
 - Debug safety checks and logging which get stripped from the binary in Release builds for maximum performance
 - Linear mathematics optimized with Zig Vector types

### About
This project originally started as me trying to learn Vulkan graphics programming.  I wanted to try Rust, but
unsatisfied with some of the abstractions provided by Rust, plus my new-found love for Zig, I decided to use
Zig instead with minimal dependencies.  I'm quite new to graphics programming, which is why the graphics are
very basic with crude lighting.  The main point of this project was to learn all the back-end programming and
API usage while also understanding and solving problems such as asynchronous resource loading and rendering.
This project has been sitting on my computer for a couple months, mostly abandoned.  Recently I thought it
would be valuable to post this project publically due to my disatisfaction with Zig's lack of online documentation
and discussion, so hopefully new Zig programmers could pick up what I've learned more quickly.  This project
can also be a general sample for how I approached many problems in graphics programming and used as an example
for new programmers of all languages.

