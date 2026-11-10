// Branch target buffer: direct-mapped, 64 entries, tagged (PC[31:8]) with a
// valid bit and a `cond` flag (1 = conditional branch, 0 = jal/jalr).
// Read combinationally at fetch; written when a control transfer resolves
// taken in EX. Fetch redirects only when the entry is a hit; for
// conditional entries the BHT still decides direction (BTB hit + BHT
// not-taken => fall through).
module btb #(
	parameter int ENTRIES = 64
) (
	input  logic        clk,
	input  logic        rstn,
	// prediction port (combinational read)
	input  logic [31:0] predict_pc,
	output logic        predict_hit,
	output logic [31:0] predict_target,
	output logic        predict_cond,
	// training port (written on taken control transfers)
	input  logic        train_valid,
	input  logic [31:0] train_pc,
	input  logic [31:0] train_target,
	input  logic        train_cond
);
	localparam int IDX_W = $clog2(ENTRIES);
	localparam int TAG_W = 32 - IDX_W - 2;

	logic             valid_q [ENTRIES];
	logic [TAG_W-1:0] tag_q   [ENTRIES];
	logic [31:0]      tgt_q   [ENTRIES];
	logic             cond_q  [ENTRIES];

	logic [IDX_W-1:0] pidx, tidx;
	logic [TAG_W-1:0] ptag, ttag;

	assign pidx = predict_pc[IDX_W+1:2];
	assign tidx = train_pc[IDX_W+1:2];
	assign ptag = predict_pc[31:IDX_W+2];
	assign ttag = train_pc[31:IDX_W+2];

	assign predict_hit = valid_q[pidx] && (tag_q[pidx] == ptag);
	assign predict_target = tgt_q[pidx];
	assign predict_cond = cond_q[pidx];

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			for (int i = 0; i < ENTRIES; i++) begin
				valid_q[i] <= 1'b0;
				tag_q[i]   <= '0;
				tgt_q[i]   <= '0;
				cond_q[i]  <= 1'b0;
			end
		end else if (train_valid) begin
			valid_q[tidx] <= 1'b1;
			tag_q[tidx]   <= ttag;
			tgt_q[tidx]   <= train_target;
			cond_q[tidx]  <= train_cond;
		end
	end
endmodule
