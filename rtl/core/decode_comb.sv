// Combinational RV32I decoder: instruction word -> control word + immediates.
// Opcode/funct classification follows the PicoRV32 fork's decode table.
module decode_comb (
	input  logic [31:0] instr,
	output core_pkg::ctrl_t c,
	output logic [31:0] imm,
	output logic [4:0]  rs1,
	output logic [4:0]  rs2,
	output logic [4:0]  rd
);
	import core_pkg::*;

	logic [6:0] opcode;
	logic [2:0] funct3;
	logic [6:0] funct7;

	always_comb begin
		opcode = instr[6:0];
		funct3 = instr[14:12];
		funct7 = instr[31:25];
		rs1 = instr[19:15];
		rs2 = instr[24:20];
		rd  = instr[11:7];
		c = '0;
		imm = 32'd0;
		c.funct3 = funct3;

		case (opcode)
			7'b0110111: begin // LUI
				c.valid = 1; c.is_lui = 1;
				c.alu_op = ALU_B; c.alu_src2_imm = 1;
				c.wb_sel = WB_ALU; c.wb_en = 1;
				imm = {instr[31:12], 12'b0};
			end
			7'b0010111: begin // AUIPC
				c.valid = 1; c.is_auipc = 1;
				c.alu_op = ALU_ADD; c.alu_src1_pc = 1; c.alu_src2_imm = 1;
				c.wb_sel = WB_ALU; c.wb_en = 1;
				imm = {instr[31:12], 12'b0};
			end
			7'b1101111: begin // JAL
				c.valid = 1; c.is_jal = 1;
				c.wb_sel = WB_PC4; c.wb_en = 1;
				imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
			end
			7'b1100111: begin // JALR
				if (funct3 == 3'b000) begin
					c.valid = 1; c.is_jalr = 1;
					c.uses_rs1 = 1;
					c.wb_sel = WB_PC4; c.wb_en = 1;
					imm = {{20{instr[31]}}, instr[31:20]};
				end else c.illegal = 1;
			end
			7'b1100011: begin // branches
				c.valid = 1; c.is_branch = 1;
				c.uses_rs1 = 1; c.uses_rs2 = 1;
				imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
				if (funct3 == 3'b010 || funct3 == 3'b011) c.illegal = 1;
			end
			7'b0000011: begin // loads
				c.valid = 1; c.is_load = 1;
				c.uses_rs1 = 1;
				c.alu_op = ALU_ADD; c.alu_src2_imm = 1;
				c.wb_sel = WB_MEM; c.wb_en = 1;
				imm = {{20{instr[31]}}, instr[31:20]};
				case (funct3)
					3'b000: c.mem_size = SZ_B;
					3'b001: c.mem_size = SZ_H;
					3'b010: c.mem_size = SZ_W;
					3'b100: begin c.mem_size = SZ_B; c.mem_unsigned = 1; end
					3'b101: begin c.mem_size = SZ_H; c.mem_unsigned = 1; end
					default: c.illegal = 1;
				endcase
			end
			7'b0100011: begin // stores
				c.valid = 1; c.is_store = 1;
				c.uses_rs1 = 1; c.uses_rs2 = 1;
				c.alu_op = ALU_ADD; c.alu_src2_imm = 1;
				imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
				case (funct3)
					3'b000: c.mem_size = SZ_B;
					3'b001: c.mem_size = SZ_H;
					3'b010: c.mem_size = SZ_W;
					default: c.illegal = 1;
				endcase
			end
			7'b0010011: begin // ALU immediate
				c.valid = 1; c.is_alui = 1;
				c.uses_rs1 = 1;
				c.alu_src2_imm = 1;
				c.wb_sel = WB_ALU; c.wb_en = 1;
				imm = {{20{instr[31]}}, instr[31:20]};
				case (funct3)
					3'b000: c.alu_op = ALU_ADD;
					3'b010: c.alu_op = ALU_SLT;
					3'b011: c.alu_op = ALU_SLTU;
					3'b100: c.alu_op = ALU_XOR;
					3'b110: c.alu_op = ALU_OR;
					3'b111: c.alu_op = ALU_AND;
					3'b001: begin
						c.alu_op = ALU_SLL;
						if (funct7 != 7'b0000000) c.illegal = 1;
						imm = {27'b0, instr[24:20]};
					end
					3'b101: begin
						c.alu_op = instr[30] ? ALU_SRA : ALU_SRL;
						if (funct7 != 7'b0000000 && funct7 != 7'b0100000) c.illegal = 1;
						imm = {27'b0, instr[24:20]};
					end
				endcase
			end
			7'b0110011: begin // ALU register
				c.valid = 1; c.is_alu = 1;
				c.uses_rs1 = 1; c.uses_rs2 = 1;
				c.wb_sel = WB_ALU; c.wb_en = 1;
				case (funct3)
					3'b000: c.alu_op = instr[30] ? ALU_SUB : ALU_ADD;
					3'b001: c.alu_op = ALU_SLL;
					3'b010: c.alu_op = ALU_SLT;
					3'b011: c.alu_op = ALU_SLTU;
					3'b100: c.alu_op = ALU_XOR;
					3'b101: c.alu_op = instr[30] ? ALU_SRA : ALU_SRL;
					3'b110: c.alu_op = ALU_OR;
					3'b111: c.alu_op = ALU_AND;
				endcase
				if (funct7 != 7'b0000000 &&
				    !(funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)))
					c.illegal = 1;
			end
			7'b1110011: begin // SYSTEM
				c.valid = 1; c.is_system = 1;
				if (funct3 == 3'b000) begin
					if (instr[31:20] == 12'h000) c.ecall = 1;
					else if (instr[31:20] == 12'h001) c.ebreak = 1;
					else c.illegal = 1;
				end else begin
					c.csr_addr = instr[31:20];
					c.wb_sel = WB_CSR; c.wb_en = 1;
					case (funct3)
						3'b001: begin c.csr_op = CSR_RW; c.uses_rs1 = 1; end
						3'b010: begin c.csr_op = CSR_RS; c.uses_rs1 = 1; end
						3'b011: begin c.csr_op = CSR_RC; c.uses_rs1 = 1; end
						3'b101: c.csr_op = CSR_RW; // csrrwi (zimm in rs1 field)
						3'b110: c.csr_op = CSR_RS;
						3'b111: c.csr_op = CSR_RC;
						default: c.illegal = 1;
					endcase
				end
			end
			default: c.illegal = 1;
		endcase

		if (c.illegal) begin
			c = '0;
			c.valid = 1;
			c.illegal = 1;
		end
	end
endmodule
