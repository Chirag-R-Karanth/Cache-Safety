// Scoreboard for late-resolving branches and Phase 6 memory faults.
//
// Branches resolve in EX but the squash/redirect is deferred until the
// branch reaches WB (2-stage scoreboard). During that window younger
// instructions keep executing on the predicted path; block_commit suppresses
// wrong-path CSR writes, traps and predictor training.
//
// Phase 6: memory permission faults are detected in MEM (mem_stage) and
// queued in a 4-stage fault scoreboard. This gives a ~4-cycle speculative
// window after the fault is detected, during which dependent transient
// instructions (e.g. a Meltdown probe load) can execute. Their cache side
// effects survive the eventual squash (Phase 4's speculative-fill property).
// When the fault entry reaches p0, `squash` fires and `trap` asserts so the
// testbench can observe the fault. block_commit is asserted for the whole
// window, gating wrong-path commits while letting speculative loads pass.
//
// Two independent pipelines are kept so the existing branch timing is
// unchanged: branch mispredicts squash after 2 cycles; faults squash after 4.
module scoreboard (
	input  logic        clk,
	input  logic        rstn,
	// branch resolve record from EX (at most one push per cycle)
	input  logic        resolve_mispredict,
	input  logic [31:0] resolve_target,
	// memory fault record from MEM (mem_stage)
	input  logic        fault_valid,
	input  logic [31:0] fault_addr,
	// recovery / control
	output logic        squash,         // 1-cycle pulse: flush younger now
	output logic [31:0] squash_target,  // redirect target (branch) or fault addr
	output logic        trap,           // fault retired: trap to testbench
	output logic        block_commit,   // squash pending: kill wrong-path commits
	output logic        speculating     // observability: record in flight
);
	typedef struct packed {
		logic        valid;
		logic [31:0] target;
	} rec_t;

	// ---- branch mispredict scoreboard (2-stage, existing timing) ----
	rec_t br_p0_q, br_p1_q;

	// ---- memory fault scoreboard (5-stage, Meltdown window) ----
	rec_t flt_p0_q, flt_p1_q, flt_p2_q, flt_p3_q, flt_p4_q;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			br_p0_q <= '0; br_p1_q <= '0;
			flt_p0_q <= '0; flt_p1_q <= '0;
			flt_p2_q <= '0; flt_p3_q <= '0; flt_p4_q <= '0;
		end else if (squash) begin
			// the flush kills every in-flight record too
			br_p0_q <= '0; br_p1_q <= '0;
			flt_p0_q <= '0; flt_p1_q <= '0;
			flt_p2_q <= '0; flt_p3_q <= '0; flt_p4_q <= '0;
		end else begin
			// branch pipeline: EX resolve -> p1 -> p0 -> squash
			br_p0_q <= br_p1_q;
			br_p1_q.valid  <= resolve_mispredict;
			br_p1_q.target <= resolve_target;

			// fault pipeline: MEM detect -> p4 -> p3 -> p2 -> p1 -> p0 -> squash+trap
			flt_p0_q <= flt_p1_q;
			flt_p1_q <= flt_p2_q;
			flt_p2_q <= flt_p3_q;
			flt_p3_q <= flt_p4_q;
			flt_p4_q.valid  <= fault_valid;
			flt_p4_q.target <= fault_addr;
		end
	end

	assign squash = br_p0_q.valid || flt_p0_q.valid;
	assign squash_target = br_p0_q.valid ? br_p0_q.target : flt_p0_q.target;
	assign trap = flt_p0_q.valid;                 // only memory faults trap
	assign block_commit =
		br_p0_q.valid || br_p1_q.valid ||
		flt_p0_q.valid || flt_p1_q.valid ||
		flt_p2_q.valid || flt_p3_q.valid;
	assign speculating = block_commit;
endmodule
