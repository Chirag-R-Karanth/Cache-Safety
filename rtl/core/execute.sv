// Execute stage: forwarding selects, ALU, branch/jump resolution, CSR request.
// Owns the EX/MEM pipeline register.
//
// Phase 3 (late-resolving branch): the condition is still computed here in
// EX, but there is no immediate redirect. Instead a resolve record
// (mispredict + correct target) is handed to the scoreboard, which defers
// the squash/redirect until the branch reaches WB — younger instructions
// keep executing on the predicted path during that window. `block_commit`
// (asserted while a squash is pending) suppresses wrong-path CSR writes,
// traps and predictor training. On a squash, EX/MEM is flushed with
// priority over the MEM hold so the wrong-path occupant dies immediately.
module execute (
	input  logic clk,
	input  logic rstn,
	input  logic hold,          // MEM busy: freeze EX/MEM
	input  logic squash,        // late-resolve flush: kill EX/MEM now
	input  logic block_commit,  // squash pending: suppress wrong-path commits
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
	// resolve record toward the scoreboard
	output logic        resolve_valid,       // control transfer left EX
	output logic        resolve_mispredict,
	output logic [31:0] resolve_target,      // correct next PC when mispredict
	// predictor training (gated by !block_commit)
	output logic        train_bht_valid,
	output logic        train_btb_valid,
	output logic [31:0] train_pc,
	output logic        train_taken,
	output logic [31:0] train_target,
	output logic        train_cond,
	// trap toward core5
	output logic trap_valid
);
	import core_pkg::*;

	exmem_t exmem_q;
	logic [31:0] fwd1, fwd2;
	logic [31:0] alu_a, alu_b, alu_y;
	logic br_taken;
	logic [31:0] br_target, jalr_target;
	logic ex_fire;
	logic act_taken;
	logic [31:0] act_target;

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

	// actual outcome of a control transfer
	always_comb begin
		if (idex.c.is_jalr) begin
			act_taken = 1'b1;
			act_target = jalr_target;
		end else if (idex.c.is_jal) begin
			act_taken = 1'b1;
			act_target = br_target;
		end else begin
			act_taken = idex.c.is_branch && br_taken;
			act_target = br_target;
		end
	end

	assign ex_fire = idex.valid && !hold;

	// ---- resolve record (no immediate redirect anymore) ----
	assign resolve_valid = ex_fire &&
		(idex.c.is_branch || idex.c.is_jal || idex.c.is_jalr);
	assign resolve_mispredict = resolve_valid &&
		(act_taken ? (!idex.pred_taken || idex.pred_target != act_target)
		           : idex.pred_taken);
	assign resolve_target = act_taken ? act_target : (idex.pc + 32'd4);

	// ---- predictor training (never from behind a pending squash) ----
	assign train_pc = idex.pc;
	assign train_taken = act_taken;
	assign train_target = act_target;
	assign train_cond = idex.c.is_branch;
	assign train_bht_valid = ex_fire && idex.c.is_branch && !block_commit;
	assign train_btb_valid = ex_fire && act_taken && !block_commit;

	// ---- CSR ----
	assign csr_req   = idex.valid && idex.c.csr_op != CSR_NONE;
	assign csr_addr  = idex.c.csr_addr;
	assign csr_op    = idex.c.csr_op;
	// immediate forms (funct3[2]) use zimm in the rs1 field
	assign csr_wdata = idex.c.funct3[2] ? {27'b0, idex.rs1} : fwd1;
	assign csr_fire  = csr_req && !hold && !block_commit;

	// ---- trap: ecall / ebreak / illegal ----
	assign trap_valid = ex_fire && !block_commit &&
		(idex.c.ecall || idex.c.ebreak || idex.c.illegal);

	// ---- EX/MEM register ----
	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			exmem_q <= '0;
		end else if (squash) begin
			exmem_q <= '0; // late-resolve flush overrides the MEM hold
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
