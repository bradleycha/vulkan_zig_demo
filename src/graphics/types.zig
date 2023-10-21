const std = @import("std");

pub fn ColorRGBA(comptime ty : type) type {
   return struct {
      r  : ty,
      g  : ty,
      b  : ty,
      a  : ty,
   };
}

