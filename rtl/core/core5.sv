// core5: 5-stage in-order RV32I pipeline (fetch, decode, execute, mem, wb).
//
// Phase 3 control: BHT/BTB predict-and-continue fetch; branches resolve in
// EX but the scoreboard defers misprediction squash/redirect until the
// branch reaches WB ("late-resolving branch"), so younger instructions —
// including a speculative load at distance 1 — execute before recovery.
// 1-cycle load-use interlock; full EX/MEM/WB forwarding.
//
// Stage modules own their pipeline registers; this top level contains the
// hazard unit and wiring. Instruction decode derives from the PicoRV32 fork.
module core5 (
	input  logic clk,
	input  logic rstn,
	// instruction bus (valid/ready handshake)
	output logic        i_valid,
	output logic [31:0] i_addr,
	input  logic        i_ready,
	input  logic [31:0] i_rdata,
	// data bus
	output logic        d_valid,
	output logic [31:0] d_addr,
	output logic [31:0] d_wdata,
	output logic [3:0]  d_wstrb,
	input  logic        d_ready,
	input  logic [31:0] d_rdata,
	// L1 invalidate (Flush+Reload): drop the line containing inval_addr
	input  logic        inval_valid,
	input  logic [31:0] inval_addr,
	// observability
	output logic trap
);
	import core_pkg::*;

	ifid_t ifid;
	idex_t idex;
	exmem_t exmem;
	memwb_t memwb;

	logic mem_busy;
	logic load_use, take, redirect;
	logic [31:0] redirect_pc;
	logic [4:0] haz_rs1, haz_rs2;
	logic haz_uses_rs1, haz_uses_rs2;

	// ---- late-resolve squash (scoreboard) ----
	logic squash, block_commit, speculating;
	logic [31:0] squash_target;
	logic resolve_valid, resolve_mispredict;
	logic [31:0] resolve_target;
	logic train_bht_valid, train_btb_valid, train_taken, train_cond;
	logic [31:0] train_pc, train_target;

	scoreboard u_scoreboard (
		.clk(clk), .rstn(rstn),
		.resolve_mispredict(resolve_mispredict),
		.resolve_target(resolve_target),
		.squash(squash),
		.squash_target(squash_target),
		.block_commit(block_commit),
		.speculating(speculating)
	);

	// squash is the pipeline-wide redirect/flush
	assign redirect = squash;
	assign redirect_pc = squash_target;

	// ---- hazard unit ----
	assign load_use = idex.valid && idex.c.is_load && idex.c.wb_en &&
	                  idex.rd != 5'd0 && ifid.valid &&
	                  ((haz_uses_rs1 && haz_rs1 == idex.rd) ||
	                   (haz_uses_rs2 && haz_rs2 == idex.rd));

	// IF/ID advances only when not frozen and not being flushed
	assign take = ifid.valid && !mem_busy && !load_use && !redirect;

	// ---- stages ----
	fetch u_fetch (
		.clk(clk), .rstn(rstn),
		.stall(mem_busy || load_use),
		.consume(take),
		.flush(redirect),
		.redirect_pc(redirect_pc),
		.train_bht_valid(train_bht_valid),
		.train_btb_valid(train_btb_valid),
		.train_pc(train_pc),
		.train_taken(train_taken),
		.train_target(train_target),
		.train_cond(train_cond),
		.i_valid(i_valid), .i_addr(i_addr),
		.i_ready(i_ready), .i_rdata(i_rdata),
		.ifid(ifid)
	);

	logic wb_wen;
	logic [4:0] wb_waddr;
	logic [31:0] wb_wdata;

	writeback u_writeback (
		.memwb(memwb),
		.wen(wb_wen), .waddr(wb_waddr), .wdata(wb_wdata)
	);

	decode u_decode (
		.clk(clk), .rstn(rstn),
		.ifid(ifid),
		.hold(mem_busy),
		.load_use(load_use),
		.flush(redirect),
		.take(take),
		.wb_wen(wb_wen), .wb_waddr(wb_waddr), .wb_wdata(wb_wdata),
		.idex(idex),
		.haz_rs1(haz_rs1), .haz_rs2(haz_rs2),
		.haz_uses_rs1(haz_uses_rs1), .haz_uses_rs2(haz_uses_rs2)
	);

	logic csr_req, csr_fire;
	logic [11:0] csr_addr;
	logic [1:0] csr_op;
	logic [31:0] csr_wdata, csr_rdata;

	// instret must tick exactly once per instruction: memwb may hold its
	// content for several cycles while MEM is stalled (hold), so gate retire
	// to the first cycle of each WB-slot residency.
	logic wb_first;
	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn)              wb_first <= 1'b0;
		else if (!mem_busy)     wb_first <= 1'b1;
		else                    wb_first <= 1'b0;
	end

	csr u_csr (
		.clk(clk), .rstn(rstn),
		.req(csr_req), .addr(csr_addr), .op(csr_op),
		.wdata(csr_wdata), .fire(csr_fire),
		.rdata(csr_rdata),
		.retire(memwb.valid && wb_first)
	);

	execute u_execute (
		.clk(clk), .rstn(rstn),
		.hold(mem_busy),
		.squash(squash),
		.block_commit(block_commit),
		.idex(idex),
		.memwb(memwb),
		.exmem(exmem),
		.csr_req(csr_req), .csr_addr(csr_addr), .csr_op(csr_op),
		.csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_fire(csr_fire),
		.resolve_valid(resolve_valid),
		.resolve_mispredict(resolve_mispredict),
		.resolve_target(resolve_target),
		.train_bht_valid(train_bht_valid),
		.train_btb_valid(train_btb_valid),
		.train_pc(train_pc),
		.train_taken(train_taken),
		.train_target(train_target),
		.train_cond(train_cond),
		.trap_valid(trap)
	);

	mem_stage u_mem (
		.clk(clk), .rstn(rstn),
		.exmem(exmem),
		.squash(squash),
		.hold(mem_busy),
		.inval_valid(inval_valid),
		.inval_addr(inval_addr),
		.d_valid(d_valid), .d_addr(d_addr),
		.d_wdata(d_wdata), .d_wstrb(d_wstrb),
		.d_ready(d_ready), .d_rdata(d_rdata),
		.memwb(memwb)
	);
endmodule
