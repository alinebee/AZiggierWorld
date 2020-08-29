const opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const VirtualMachine = @import("../virtual_machine.zig");

pub const Error = Program.Error;

/// Set a specific register to a constant value.
pub const Instruction = struct {
    /// The ID of the register to set.
    destination: VirtualMachine.RegisterID,
    
    /// The constant value to set the register to.
    value: VirtualMachine.Register,

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: opcode.RawOpcode, program: *Program.Instance) Error!Instruction {
        return Instruction {
            .destination = try program.read(VirtualMachine.RegisterID),
            .value = try program.read(VirtualMachine.Register),
        };
    }

    pub fn execute(self: Instruction, vm: *VirtualMachine.Instance) void {
        vm.registers[self.destination] = self.value;
    }
};

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(opcode.Opcode.SetRegister);

    pub const valid = [_]u8 { raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid, 3);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(-18901, instruction.value);
}

test "parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..3], 2),
    );
}

test "execute updates specified register with value" {
    const instruction = Instruction {
        .destination = 16,
        .value = -1234,
    };

    var vm = VirtualMachine.init();
    instruction.execute(&vm);

    testing.expectEqual(-1234, vm.registers[16]);
}