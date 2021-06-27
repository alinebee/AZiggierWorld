//! Extends Machine.Instance with methods for loading resources and game parts.

const ResourceID = @import("../values/resource_id.zig");
const GamePart = @import("../values/game_part.zig");
const Machine = @import("machine.zig");

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

/// Methods intended to be imported into Machine.Instance.
pub const Interface = struct {
    /// Load the resources for the specified game part and begin executing its program.
    /// Returns an error if one or more resources do not exist or could not be loaded.
    pub fn startGamePart(self: *Machine.Instance, game_part: GamePart.Enum) !void {
        log_unimplemented("Resources.startGamePart: load game part {s}", .{@tagName(game_part)});
    }

    /// Load the specified resource if it is not already loaded.
    /// Returns an error if the specified resource ID does not exist or could not be loaded.
    pub fn loadResource(self: *Machine.Instance, resource_id: ResourceID.Raw) !void {
        log_unimplemented("Resources.loadResource: load #{X}", .{resource_id});
    }

    /// Unload all resources and stop any currently-playing sound.
    pub fn unloadAllResources(self: *Machine.Instance) void {
        log_unimplemented("Resources.unloadAllResources: unload all resources", .{});
    }
};
