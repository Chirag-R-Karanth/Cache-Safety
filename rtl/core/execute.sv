// Execute stage: forwarding selects, ALU, branch/jump resolution, CSR request.
// Owns the EX/MEM pipeline register. Branch prediction baseline: not-taken;
// a taken branch or any jump redirects and kills younger stages (via core5).
module execute (
	input  logic clk,
	input  logic rstn,
	input  logic hold,          // MEM busy: freeze EX/MEM, no redirect
	input  core_pkg::idex_t idex,
	input  core_pkg::memwb_t memwb,   // for WB->EX forwarding
	output core_pkg::exmem_t exmem,   // registered EX/MEM state
	// CSR interface (combinational read; write on fire)
	output logic csr_req,
	output logic [11:0] csr_addr,
	output logic [1:0]  csr_op,       // core_pkg::csr_op_e
	output logic [31:0] csr_wdata,
	input  logic [31:0] csr_rdata,
	output logic csr_fire,
	// redirect / trap toward core5
	output logic redirect_valid,
	output logic [31:0] redirect_target,
	output logic trap_valid
);
	import core_pkg::*;

	exmem_t exmem_q;
	logic [31:0] fwd1, fwd2;
	logic [31:0] alu_a, alu_b, alu_y;
	logic br_taken;
	logic [31:0] br_target, jalr_target;
	logic ex_fire;

	// ---- forwarding (EX/MEM result first: it is younger) ----
	always_comb begin
		if (exmem_q.valid && exmem_q.c.wb_en && !exmem_q.c.is_load &&
		    exmem_q.rd != 5'd0 && exmem_q.rd == idex.rs1 && idex.c.uses_rs1)
			fwd1 = exmem_q.ex_result;
		else if (memwb.valid && memwb.wb_en && memwb.rd != 5'd0 &&
		         memwb.rd == idex.rs1 && idex.c.uses_rs1)
			fwd1 = wb_value(memwb);
		else
			fwd1 = idex.rs1_val;

		if (exmem_q.valid && exmem_q.c.wb_en && !exmem_q.c.is_load &&
		    exmem_q.rd != 5'd0 && exmem_q.rd == idex.rs2 && idex.c.uses_rs2)
			fwd2 = exmem_q.ex_result;
		else if (memwb.valid && memwb.wb_en && memwb.rd != 5'd0 &&
		         memwb.rd == idex.rs2 && idex.c.uses_rs2)
			fwd2 = wb_value(memwb);
		else
			fwd2 = idex.rs2_val;
	end

	// ---- ALU ----
	always_comb begin
		alu_a = idex.c.alu_src1_pc ? idex.pc : fwd1;
		alu_b = idex.c.alu_src2_imm ? idex.imm : fwd2;
		unique case (idex.c.alu_op)
			ALU_ADD:  alu_y = alu_a + alu_b;
			ALU_SUB:  alu_y = alu_a - alu_b;
			ALU_AND:  alu_y = alu_a & alu_b;
			ALU_OR:   alu_y = alu_a | alu_b;
			ALU_XOR:  alu_y = alu_a ^ alu_b;
			ALU_SLT:  alu_y = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
			ALU_SLTU: alu_y = (alu_a < alu_b) ? 32'd1 : 32'd0;
			ALU_SLL:  alu_y = alu_a << alu_b[4:0];
			ALU_SRL:  alu_y = alu_a >> alu_b[4:0];
			ALU_SRA:  alu_y = $signed(alu_a) >>> alu_b[4:0];
			ALU_B:    alu_y = alu_b;
			default:  alu_y = 32'd0;
		endcase
	end

	// ---- branch compare ----
	always_comb begin
		unique case (idex.c.funct3)
			3'b000: br_taken = (fwd1 == fwd2);                       // BEQ
			3'b001: br_taken = (fwd1 != fwd2);                       // BNE
			3'b100: br_taken = ($signed(fwd1) <  $signed(fwd2));     // BLT
			3'b101: br_taken = ($signed(fwd1) >= $signed(fwd2));     // BGE
			3'b110: br_taken = (fwd1 <  fwd2);                       // BLTU
			3'b111: br_taken = (fwd1 >= fwd2);                       // BGEU
			default: br_taken = 1'b0;
		endcase
		br_target = idex.pc + idex.imm;
		jalr_target = (fwd1 + idex.imm) & 32'hFFFF_FFFE;
	end

	// ---- redirect (fires only when EX not held) ----
	assign ex_fire = idex.valid && !hold;
	always_comb begin
		redirect_valid = 1'b0;
		redirect_target = 32'd0;
		if (ex_fire) begin
			if (idex.c.is_jal || idex.c.is_jalr) begin
				redirect_valid = 1'b1;
				redirect_target = idex.c.is_jalr ? jalr_target : br_target;
			end else if (idex.c.is_branch && br_taken) begin
				redirect_valid = 1'b1;
				redirect_target = br_target;
			end
		end
	end

	// ---- CSR ----
	assign csr_req   = idex.valid && idex.c.csr_op != CSR_NONE;
	assign csr_addr  = idex.c.csr_addr;
	assign csr_op    = idex.c.csr_op;
	// immediate forms (funct3[2]) use zimm in the rs1 field
	assign csr_wdata = idex.c.funct3[2] ? {27'b0, idex.rs1} : fwd1;
	assign csr_fire  = csr_req && !hold;

	// ---- trap: ecall / ebreak / illegal ----
	assign trap_valid = ex_fire &&
		(idex.c.ecall || idex.c.ebreak || idex.c.illegal);

	// ---- EX/MEM register ----
	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			exmem_q <= '0;
		end else if (!hold) begin
			exmem_q.valid      <= idex.valid;
			exmem_q.pc         <= idex.pc;
			exmem_q.rd         <= idex.rd;
			exmem_q.c          <= idex.c;
			exmem_q.store_data <= fwd2;
			// result that later stages/forwarding consume
			unique case (1'b1)
				idex.c.is_load, idex.c.is_store:
					exmem_q.ex_result <= alu_y;      // address
				idex.c.wb_sel == WB_PC4:
					exmem_q.ex_result <= idex.pc + 32'd4;
				idex.c.wb_sel == WB_CSR:
					exmem_q.ex_result <= csr_rdata;
				default:
					exmem_q.ex_result <= alu_y;
			endcase
		end
	end

	assign exmem = exmem_q;
endmodule
