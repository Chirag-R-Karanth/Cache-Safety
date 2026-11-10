// Fetch stage: PC + instruction bus master with a 1-entry skid buffer so an
// in-flight response is never lost across a stall. Owns the IF/ID register.
//
// Invariants: at most one outstanding request, and the skid is empty while a
// request is outstanding (issue is blocked whenever skid_valid), so a response
// and a skid drain can never compete for IF/ID in the same cycle.
module fetch (
	input  logic clk,
	input  logic rstn,
	input  logic stall,             // hold IF/ID (mem busy or load-use)
	input  logic consume,           // IF/ID taken by decode this cycle
	input  logic flush,             // kill IF/ID + skid (redirect)
	input  logic [31:0] redirect_pc,
	// instruction bus
	output logic        i_valid,
	output logic [31:0] i_addr,
	input  logic        i_ready,
	input  logic [31:0] i_rdata,
	// IF/ID toward decode
	output core_pkg::ifid_t ifid
);
	import core_pkg::*;

	ifid_t ifid_q, skid_q;
	logic [31:0] pc_q, out_pc;
	logic outstanding, skid_valid;

	logic can_put;   // response may enter IF/ID this cycle
	logic issue;     // launch a new request this cycle
	logic resp;      // request completes this cycle
	logic [31:0] resp_pc;

	assign can_put = !stall && (!ifid_q.valid || consume);
	assign issue = !flush && !outstanding && !skid_valid;
	assign i_valid = issue || outstanding;
	assign i_addr = outstanding ? out_pc : pc_q;
	assign resp = i_valid && i_ready;
	assign resp_pc = outstanding ? out_pc : pc_q;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			pc_q <= 32'd0;
			ifid_q <= '0;
			skid_q <= '0;
			skid_valid <= 1'b0;
			outstanding <= 1'b0;
			out_pc <= 32'd0;
		end else if (flush) begin
			pc_q <= redirect_pc;
			ifid_q <= '0;
			skid_valid <= 1'b0;
			outstanding <= 1'b0;
		end else begin
			// 1) response capture (skid is guaranteed empty here when
			//    outstanding, and drain/resp are mutually exclusive)
			if (resp) begin
				outstanding <= 1'b0;
				if (can_put) begin
					ifid_q.valid <= 1'b1;
					ifid_q.pc <= resp_pc;
					ifid_q.instr <= i_rdata;
				end else begin
					skid_q.valid <= 1'b1;
					skid_q.pc <= resp_pc;
					skid_q.instr <= i_rdata;
					skid_valid <= 1'b1;
				end
				if (!outstanding)
					pc_q <= pc_q + 32'd4; // same-cycle issue+resp (comb mem)
			end else if (issue) begin
				outstanding <= 1'b1;
				out_pc <= pc_q;
				pc_q <= pc_q + 32'd4;
			end

			// 2) skid drain into IF/ID
			if (skid_valid && can_put) begin
				ifid_q <= skid_q;
				skid_valid <= 1'b0;
			end

			// 3) consume clears IF/ID when nothing reloaded it above
			if (consume && !stall && !resp && !(skid_valid && can_put))
				ifid_q.valid <= 1'b0;
		end
	end

	assign ifid = ifid_q;
endmodule
