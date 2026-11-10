// Memory stage: issues load/store requests to the on-chip L1 data cache
// and owns the MEM/WB register. The cache (rtl/cache/l1_dcache.sv) masters
// the external data bus.
//
// Phase 3 semantics kept: on a late-resolve `squash` a wrong-path store's
// request is suppressed before it reaches the cache (never commits), while
// speculative loads are deliberately let through — their fill completes
// even though MEM/WB is cleared, leaving the cache line valid (the
// timing-visible side effect Spectre measures). MEM/WB clears with priority
// over `hold` so the flush always completes.
module mem_stage (
	input  logic clk,
	input  logic rstn,
	input  core_pkg::exmem_t exmem,
	input  logic squash,           // late-resolve flush: kill MEM/WB now
	output logic hold,              // mem_busy: EX/MEM frozen
	// invalidate (Flush+Reload): drop line containing inval_addr
	input  logic        inval_valid,
	input  logic [31:0] inval_addr,
	// external data bus (cache memory side)
	output logic        d_valid,
	output logic [31:0] d_addr,
	output logic [31:0] d_wdata,
	output logic [3:0]  d_wstrb,
	input  logic        d_ready,
	input  logic [31:0] d_rdata,
	// to WB
	output core_pkg::memwb_t memwb
);
	import core_pkg::*;

	memwb_t memwb_q;
	logic is_mem_op;
	logic mem_done;
	logic [31:0] load_data;

	// ---- request side toward the cache ----
	logic        req_valid;
	logic [31:0] req_addr, req_wdata;
	logic [3:0]  req_wstrb;
	logic        req_we;
	logic        rsp_ready;
	logic [31:0] rsp_rdata;

	assign is_mem_op = exmem.valid && (exmem.c.is_load || exmem.c.is_store);
	assign mem_done = !is_mem_op || rsp_ready;
	assign hold = exmem.valid && !mem_done;

	// wrong-path store suppressed before it reaches the cache; loads pass
	// (their fill is the Phase 4/5 speculative side effect)
	assign req_valid = is_mem_op && !(squash && exmem.c.is_store);
	assign req_addr  = exmem.ex_result;
	assign req_we    = exmem.c.is_store;

	// store lane replication (was the external bus encoding)
	always_comb begin
		req_wdata = 32'd0;
		req_wstrb = 4'b0000;
		if (exmem.c.is_store) begin
			case (exmem.c.mem_size)
				SZ_B: begin
					req_wstrb = 4'b0001 << req_addr[1:0];
					req_wdata = {4{exmem.store_data[7:0]}};
				end
				SZ_H: begin
					req_wstrb = req_addr[1] ? 4'b1100 : 4'b0011;
					req_wdata = {2{exmem.store_data[15:0]}};
				end
				default: begin
					req_wstrb = 4'b1111;
					req_wdata = exmem.store_data;
				end
			endcase
		end
	end

	// load byte-lane extraction + extension (from cache response)
	always_comb begin
		logic [31:0] w;
		logic [7:0]  b;
		logic [15:0] h;
		w = rsp_rdata;
		case (exmem.c.mem_size)
			SZ_B: begin
				b = w >> (8 * req_addr[1:0]);
				load_data = exmem.c.mem_unsigned ? {24'b0, b}
				                                  : {{24{b[7]}}, b};
			end
			SZ_H: begin
				h = req_addr[1] ? w[31:16] : w[15:0];
				load_data = exmem.c.mem_unsigned ? {16'b0, h}
				                                  : {{16{h[7]}}, h};
			end
			default: load_data = w;
		endcase
	end

	// ---- L1 cache ----
	l1_dcache u_cache (
		.clk(clk), .rstn(rstn),
		.req_valid(req_valid),
		.req_addr(req_addr),
		.req_wdata(req_wdata),
		.req_wstrb(req_wstrb),
		.req_we(req_we),
		.rsp_ready(rsp_ready),
		.rsp_rdata(rsp_rdata),
		.inval_valid(inval_valid),
		.inval_addr(inval_addr),
		.m_valid(d_valid), .m_addr(d_addr),
		.m_wdata(d_wdata), .m_wstrb(d_wstrb),
		.m_ready(d_ready), .m_rdata(d_rdata)
	);

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			memwb_q <= '0;
		end else if (squash) begin
			// the retiring branch (current WB slot) has already written
			// back this cycle; everything behind the squash dies here
			memwb_q <= '0;
		end else if (!hold) begin
			// instruction leaves MEM every cycle it is not held;
			// while held, the WB slot keeps its content so WB->EX
			// forwarding into the frozen EX stage still works
			// (side effects are idempotent or gated: see csr.retire)
			memwb_q.valid     <= exmem.valid;
			memwb_q.pc        <= exmem.pc;
			memwb_q.rd        <= exmem.rd;
			memwb_q.wb_en     <= exmem.c.wb_en && exmem.valid;
			memwb_q.wb_sel    <= exmem.c.wb_sel;
			memwb_q.ex_result <= exmem.ex_result;
			memwb_q.mem_data  <= load_data;
		end
	end

	assign memwb = memwb_q;
endmodule
