const opcode = @import("../types/opcode.zig");
const program = @import("../types/program.zig");
const virtual_machine = @import("../virtual_machine.zig");

pub const Error = program.Error;

/// Copy the value of one register to another.
pub const Instruction = struct {
    /// The ID of the register to copy into.
    destination: virtual_machine.RegisterID,

    /// The ID of the register to copy from.
    source: virtual_machine.RegisterID,

    /// Parse the next instruction from a bytecode program.
    /// Consumes 2 bytes from the bytecode on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: opcode.RawOpcode, prog: *program.Program) Error!Instruction {
        return Instruction {
            .destination = try prog.read(virtual_machine.RegisterID),
            .source = try prog.read(virtual_machine.RegisterID),
        };
    }

    pub fn execute(self: Instruction, vm: *virtual_machine.VirtualMachine) void {
        vm.registers[self.destination] = vm.registers[self.source];
    }
};

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(opcode.Opcode.CopyRegister);

    pub const valid = [_]u8 { raw_opcode, 16, 17 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid, 2);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(17, instruction.source);
}

test "parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..2], 1),
    );
}

test "execute updates specified register with value" {
    const instruction = Instruction {
        .destination = 16,
        .source = 17,
    };

    var vm = virtual_machine.VirtualMachine.init();
    vm.registers[17] = -900;

    instruction.execute(&vm);

    testing.expectEqual(-900, vm.registers[16]);
    testing.expectEqual(-900, vm.registers[17]);
}