// Decode stage: combinational decoder + register-file reads; owns the ID/EX
// pipeline register with flush/hold/load-use-bubble control from core5.
module decode (
	input  logic clk,
	input  logic rstn,
	input  core_pkg::ifid_t ifid,
	input  logic hold,        // MEM busy: freeze ID/EX
	input  logic load_use,    // insert bubble (consumer stays in IF/ID)
	input  logic flush,       // kill ID/EX (redirect)
	input  logic take,        // IF/ID advances into ID/EX this cycle
	// register-file write port (driven by WB)
	input  logic        wb_wen,
	input  logic [4:0]  wb_waddr,
	input  logic [31:0] wb_wdata,
	// ID/EX toward execute
	output core_pkg::idex_t idex,
	// hazard unit's view of the IF/ID instruction
	output logic [4:0] haz_rs1,
	output logic [4:0] haz_rs2,
	output logic       haz_uses_rs1,
	output logic       haz_uses_rs2
);
	import core_pkg::*;

	ctrl_t c;
	logic [31:0] imm;
	logic [4:0] rs1_f, rs2_f, rd_f;
	logic [31:0] rv1, rv2;

	decode_comb u_dec (
		.instr(ifid.instr),
		.c(c),
		.imm(imm),
		.rs1(rs1_f),
		.rs2(rs2_f),
		.rd(rd_f)
	);

	regfile u_rf (
		.clk(clk),
		.wen(wb_wen),
		.waddr(wb_waddr),
		.wdata(wb_wdata),
		.raddr1(rs1_f),
		.raddr2(rs2_f),
		.rdata1(rv1),
		.rdata2(rv2)
	);

	assign haz_rs1 = rs1_f;
	assign haz_rs2 = rs2_f;
	assign haz_uses_rs1 = ifid.valid && c.uses_rs1;
	assign haz_uses_rs2 = ifid.valid && c.uses_rs2;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			idex <= '0;
		end else if (flush) begin
			idex <= '0; // killed by redirect
		end else if (hold) begin
			// MEM busy: freeze as-is
		end else if (load_use || !take) begin
			idex <= '0; // bubble
		end else begin
			idex.valid      <= 1'b1;
			idex.pc         <= ifid.pc;
			idex.rs1        <= rs1_f;
			idex.rs2        <= rs2_f;
			idex.rd         <= rd_f;
			idex.rs1_val    <= rv1;
			idex.rs2_val    <= rv2;
			idex.imm        <= imm;
			idex.c          <= c;
		end
	end
endmodule
