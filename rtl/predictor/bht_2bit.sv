// 2-bit saturating counter branch history table (bimodal).
// Indexed by PC[9:2] (256 entries); read combinationally at fetch for the
// prediction, written at branch resolve in EX. Counters start weakly
// not-taken (2'b01), matching the baseline predict-not-taken behaviour
// until a branch trains the table. Entries are untagged, so two PCs that
// alias on the index share a counter (measured, documented behaviour).
module bht_2bit #(
	parameter int ENTRIES = 256
) (
	input  logic        clk,
	input  logic        rstn,
	// prediction port (combinational read)
	input  logic [31:0] predict_pc,
	output logic        predict_taken,
	// training port (2-bit saturating update)
	input  logic        train_valid,
	input  logic [31:0] train_pc,
	input  logic        train_taken
);
	localparam int IDX_W = $clog2(ENTRIES);

	logic [1:0] cnt_q [ENTRIES];
	logic [IDX_W-1:0] pidx, tidx;

	assign pidx = predict_pc[IDX_W+1:2];
	assign tidx = train_pc[IDX_W+1:2];
	assign predict_taken = (cnt_q[pidx] >= 2'b10);

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			for (int i = 0; i < ENTRIES; i++)
				cnt_q[i] <= 2'b01; // weakly not-taken
		end else if (train_valid) begin
			unique case (cnt_q[tidx])
				2'b00: cnt_q[tidx] <= train_taken ? 2'b01 : 2'b00;
				2'b01: cnt_q[tidx] <= train_taken ? 2'b10 : 2'b00;
				2'b10: cnt_q[tidx] <= train_taken ? 2'b11 : 2'b01;
				2'b11: cnt_q[tidx] <= train_taken ? 2'b11 : 2'b10;
			endcase
		end
	end
endmodule
