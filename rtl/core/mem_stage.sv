// Memory stage: data-bus master for loads/stores, byte-lane extraction and
// store strobe generation. Owns the MEM/WB register; holds EX/MEM via `hold`
// (mem_busy) until the bus transaction completes.
//
// Phase 3: on a late-resolve `squash` the wrong-path store sitting in MEM
// (first cycle of its residency, so its transaction never started) is
// suppressed — wrong-path stores must not commit. Speculative loads are
// deliberately left unblocked: their memory access (cache fill) must
// survive the squash, which is the Spectre side channel. MEM/WB is cleared
// with priority over `hold` so the flush always completes.
module mem_stage (
	input  logic clk,
	input  logic rstn,
	input  core_pkg::exmem_t exmem,
	input  logic squash,           // late-resolve flush: kill MEM/WB now
	output logic hold,              // mem_busy: EX/MEM frozen
	// data bus
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

	assign is_mem_op = exmem.valid && (exmem.c.is_load || exmem.c.is_store);
	assign mem_done = !is_mem_op || d_ready;
	assign hold = exmem.valid && !mem_done;

	// wrong-path store squashed before its transaction starts; loads pass
	assign d_valid = is_mem_op && !(squash && exmem.c.is_store);
	assign d_addr  = exmem.ex_result;

	// store lane replication
	always_comb begin
		d_wdata = 32'd0;
		d_wstrb = 4'b0000;
		if (exmem.c.is_store) begin
			unique case (exmem.c.mem_size)
				SZ_B: begin
					d_wstrb = 4'b0001 << d_addr[1:0];
					d_wdata = {4{exmem.store_data[7:0]}};
				end
				SZ_H: begin
					d_wstrb = d_addr[1] ? 4'b1100 : 4'b0011;
					d_wdata = {2{exmem.store_data[15:0]}};
				end
				default: begin
					d_wstrb = 4'b1111;
					d_wdata = exmem.store_data;
				end
			endcase
		end
	end

	// load byte-lane extraction + extension
	always_comb begin
		logic [31:0] w;
		logic [7:0]  b;
		logic [15:0] h;
		w = d_rdata;
		unique case (exmem.c.mem_size)
			SZ_B: begin
				b = w >> (8 * d_addr[1:0]);
				load_data = exmem.c.mem_unsigned ? {24'b0, b}
				                                  : {{24{b[7]}}, b};
			end
			SZ_H: begin
				h = d_addr[1] ? w[31:16] : w[15:0];
				load_data = exmem.c.mem_unsigned ? {16'b0, h}
				                                  : {{16{h[15]}}, h};
			end
			default: load_data = w;
		endcase
	end

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
