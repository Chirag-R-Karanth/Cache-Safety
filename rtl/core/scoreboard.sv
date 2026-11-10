// Scoreboard for late-resolving branches.
//
// A branch still resolves its condition in EX, but the squash/redirect is
// deferred until the branch reaches WB (two cycles later, since a branch is
// never a memory op and therefore never stalls in MEM). During that window
// younger instructions keep executing on the predicted path — including a
// speculative load at distance 1, which reaches MEM (and, later, the L1
// cache) before recovery. On the mispredict's WB cycle `squash` pulses to
// flush every younger stage; `block_commit` is asserted from the EX resolve
// through the WB squash so wrong-path CSR writes, traps and predictor
// training are suppressed, while speculative loads are deliberately left
// unblocked (their cache side effect is the attack primitive).
//
// The queue holds only mispredicted branches: a record pushed after EX
// resolution sits one cycle in p1 (branch in MEM) and one in p0 (branch in
// WB, where it fires). Because only mispredicts are queued, p0 firing always
// clears p1 as well — younger in-flight branches die with the older squash.
module scoreboard (
	input  logic        clk,
	input  logic        rstn,
	// resolve record from EX (at most one push per cycle)
	input  logic        resolve_mispredict,
	input  logic [31:0] resolve_target,
	// recovery / control
	output logic        squash,         // 1-cycle pulse: flush younger now
	output logic [31:0] squash_target,
	output logic        block_commit,   // squash pending: kill wrong-path commits
	output logic        speculating     // observability: record in flight
);
	typedef struct packed {
		logic        valid;
		logic [31:0] target;
	} rec_t;

	rec_t p0_q, p1_q;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			p0_q <= '0;
			p1_q <= '0;
		end else if (squash) begin
			// the flush kills every younger in-flight branch too
			p0_q <= '0;
			p1_q <= '0;
		end else begin
			p0_q <= p1_q;
			p1_q.valid  <= resolve_mispredict;
			p1_q.target <= resolve_target;
		end
	end

	assign squash = p0_q.valid;
	assign squash_target = p0_q.target;
	assign block_commit = p0_q.valid || p1_q.valid;
	assign speculating = block_commit;
endmodule
