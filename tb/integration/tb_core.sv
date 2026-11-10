// Integration testbench for core5.
// Loads a program hex (+HEX=file) into instruction memory; watches for a word
// store to 0xFFFF0000 (the "magic" signature address): prints MAGIC <value>
// and finishes. Traps and timeouts print TRAP/TIMEOUT and fail.
`timescale 1 ns / 1 ps

module tb_core;
	logic clk = 1;
	logic rstn = 0;
	always #5 clk = ~clk;

	logic i_valid, d_valid;
	logic [31:0] i_addr, d_addr, d_wdata;
	logic [3:0] d_wstrb;
	logic i_ready, d_ready;
	logic [31:0] i_rdata, d_rdata;
	logic trap;

	core5 uut (
		.clk(clk), .rstn(rstn),
		.i_valid(i_valid), .i_addr(i_addr),
		.i_ready(i_ready), .i_rdata(i_rdata),
		.d_valid(d_valid), .d_addr(d_addr),
		.d_wdata(d_wdata), .d_wstrb(d_wstrb),
		.d_ready(d_ready), .d_rdata(d_rdata),
		.trap(trap)
	);

	// ---- instruction memory (combinational, word array) ----
	logic [31:0] imem [0:1023];
	logic [31:0] dmem [0:4095];

	string hex_file;
	int timeout_cycles;

	initial begin
		// memory model: zero-initialized like FPGA BRAM (and the ISS)
		for (int k = 0; k < 1024; k++) imem[k] = 32'd0;
		for (int k = 0; k < 4096; k++) dmem[k] = 32'd0;
		if (!$value$plusargs("HEX=%s", hex_file)) begin
			$display("ERROR: missing +HEX=<file>");
			$fatal(1);
		end
		if (!$value$plusargs("TIMEOUT=%d", timeout_cycles))
			timeout_cycles = 200000;
		$readmemh(hex_file, imem);
		if ($test$plusargs("vcd")) begin
			$dumpfile("tb_core.vcd");
			$dumpvars(0, tb_core);
		end
	end

	// instruction bus: always ready
	assign i_ready = 1'b1;
	always_comb begin
		i_rdata = 32'd0;
		if (i_addr < 32'd4096)
			i_rdata = imem[i_addr[11:2]];
	end

	// data bus: 1 wait-state registered ready (picorv32-style slave)
	logic d_ready_q;
	logic [31:0] d_rdata_q;
	assign d_ready = d_ready_q;
	assign d_rdata = d_rdata_q;

	always_ff @(posedge clk) begin
		d_ready_q <= 1'b0;
		if (d_valid && !d_ready_q) begin
			d_ready_q <= 1'b1;
			if ($test$plusargs("trace") && rstn)
				if (d_wstrb != 4'b0000)
					$display("ST %06x <- %08x strb=%04x (pc=%06x rd=%0d)",
						d_addr, d_wdata, d_wstrb, uut.exmem.pc, uut.exmem.rd);
				else
					$display("LD %06x (pc=%06x)", d_addr, uut.exmem.pc);
			if (d_addr < 32'd16384)
				d_rdata_q <= dmem[d_addr[13:2]];
			else
				d_rdata_q <= 32'd0;
			// byte-lane writes
			if (d_wstrb[0]) dmem[d_addr[13:2]][ 7: 0] <= d_wdata[ 7: 0];
			if (d_wstrb[1]) dmem[d_addr[13:2]][15: 8] <= d_wdata[15: 8];
			if (d_wstrb[2]) dmem[d_addr[13:2]][23:16] <= d_wdata[23:16];
			if (d_wstrb[3]) dmem[d_addr[13:2]][31:24] <= d_wdata[31:24];
			// magic signature region: word store to 0xFFFF0000
			if (d_wstrb == 4'b1111 && d_addr[31:16] == 16'hFFFF) begin
				$display("MAGIC 0x%08x", d_wdata);
				finish_stats;
			end
		end
	end

	// ---- branch statistics (Phase 3: misprediction rate) ----
	int unsigned stat_br = 0; // non-speculative control-transfer resolves
	int unsigned stat_mp = 0; // late-resolve squashes (mispredictions)

	always @(posedge clk) begin
		if (rstn && uut.u_execute.resolve_valid && !uut.block_commit)
			stat_br <= stat_br + 1;
		if (rstn && uut.squash)
			stat_mp <= stat_mp + 1;
	end

	task automatic finish_stats;
		real rate;
		begin
			rate = (stat_br == 0) ? 100.0 : (100.0 * stat_mp) / stat_br;
			$display("STAT branches=%0d mispredicts=%0d rate=%0.2f%%",
				stat_br, stat_mp, rate);
			$finish;
		end
	endtask

	// reset + timeout + trap
	initial begin
		repeat (5) @(posedge clk);
		rstn <= 1;
		repeat (timeout_cycles) @(posedge clk);
		$display("TIMEOUT after %0d cycles", timeout_cycles);
		finish_stats;
	end

	always @(posedge clk) begin
		if (rstn && trap) begin
			$display("TRAP");
			finish_stats;
		end
		if (rstn && $test$plusargs("trace")) begin
			if (uut.memwb.valid)
				$display("RET %06x", uut.memwb.pc);
			if (uut.wb_wen && uut.wb_waddr != 0)
				$display("W x%0d=0x%08x", uut.wb_waddr, uut.wb_wdata);
			$display("S if=%06x id=%06x ex=%06x wb=%06x hold=%b | fwd1=%08x fwd2=%08x | idrs1=%0d iduse1=%b | xm:v%brd%0dwb%b isld%b | mw:v%brd%0dwb%b wbsel=%0d exr=%08x mdat=%08x",
				uut.ifid.pc, uut.idex.pc, uut.exmem.pc,
				uut.memwb.valid ? uut.memwb.pc : 32'h00000000,
				uut.u_mem.hold,
				uut.u_execute.fwd1, uut.u_execute.fwd2,
				uut.idex.rs1, uut.idex.c.uses_rs1,
				uut.exmem.valid, uut.exmem.rd, uut.exmem.c.wb_en, uut.exmem.c.is_load,
				uut.memwb.valid, uut.memwb.rd, uut.memwb.wb_en, uut.memwb.wb_sel,
				uut.memwb.ex_result, uut.memwb.mem_data);
		end
	end
endmodule
