// Exact LRU replacement for a set-associative cache.
// Per-set MRU stack: entry 0 = most recently used, entry WAYS-1 = victim.
// `upd_*` marks a way as most recently used (move-to-front); `look_*`
// returns the current victim for a set (combinational).
module replacement_lru #(
	parameter int SETS = 16,
	parameter int WAYS = 2
) (
	input  logic clk,
	input  logic rstn,
	// mark upd_way of upd_set as most recently used
	input  logic                    upd_valid,
	input  logic [$clog2(SETS)-1:0] upd_set,
	input  logic [$clog2(WAYS)-1:0] upd_way,
	// victim way for look_set
	input  logic [$clog2(SETS)-1:0] look_set,
	output logic [$clog2(WAYS)-1:0] victim_way
);
	localparam int SW = $clog2(SETS);
	localparam int WW = $clog2(WAYS);

	logic [WW-1:0] stack_q [SETS][WAYS];
	logic [WW-1:0] old_stk [WAYS];
	logic [WW-1:0] nxt_stk [WAYS];
	int j;

	assign victim_way = stack_q[look_set][WAYS-1];

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			for (int s = 0; s < SETS; s++)
				for (int w = 0; w < WAYS; w++)
					stack_q[s][w] <= WW'(w); // identity: cold victim = WAYS-1
		end else if (upd_valid) begin
			// move-to-front: [upd_way] + old entries except upd_way
			for (int w = 0; w < WAYS; w++)
				old_stk[w] = stack_q[upd_set][w];
			nxt_stk[0] = upd_way;
			j = 1;
			for (int w = 0; w < WAYS; w++) begin
				if (old_stk[w] != upd_way) begin
					nxt_stk[j] = old_stk[w];
					j++;
				end
			end
			for (int w = 0; w < WAYS; w++)
				stack_q[upd_set][w] <= nxt_stk[w];
		end
	end
endmodule
