// Unit testbench for l1_dcache (write-through, no-write-allocate).
// Behavioral 1-wait-state slave over a backing array, counts bus ops.
// Compile twice: default (LRU) and -DPLRU_TEST (tree-PLRU).
`timescale 1 ns / 1 ps

module tb_dcache;
	logic clk = 0;
	logic rstn = 0;
	always #5 clk = ~clk;

`ifdef PLRU_TEST
	localparam int POL = 1;
`else
	localparam int POL = 0;
`endif

	logic        req_valid = 0;
	logic [31:0] req_addr  = 0;
	logic [31:0] req_wdata = 0;
	logic [3:0]  req_wstrb = 0;
	logic        req_we    = 0;
	logic        rsp_ready;
	logic [31:0] rsp_rdata;
	logic        inval_valid = 0;
	logic [31:0] inval_addr  = 0;
	logic        m_valid;
	logic [31:0] m_addr, m_wdata;
	logic [3:0]  m_wstrb;
	logic        m_ready;
	logic [31:0] m_rdata;

	l1_dcache #(.SETS(16), .WAYS(2), .LINE_WORDS(4), .POLICY(POL)) dut (
		.clk(clk), .rstn(rstn),
		.req_valid(req_valid), .req_addr(req_addr),
		.req_wdata(req_wdata), .req_wstrb(req_wstrb), .req_we(req_we),
		.rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
		.inval_valid(inval_valid), .inval_addr(inval_addr),
		.m_valid(m_valid), .m_addr(m_addr),
		.m_wdata(m_wdata), .m_wstrb(m_wstrb),
		.m_ready(m_ready), .m_rdata(m_rdata)
	);

	// ---- backing memory + 1-wait-state slave + bus-op counter ----
	logic [31:0] mem [0:4095];
	int bus_ops = 0;
	logic m_ready_q = 0;
	logic [31:0] m_rdata_q = 0;
	assign m_ready = m_ready_q;
	assign m_rdata = m_rdata_q;

	always_ff @(posedge clk) begin
		m_ready_q <= 1'b0;
		if (m_valid && !m_ready_q) begin
			m_ready_q <= 1'b1;
			bus_ops <= bus_ops + 1;
			if (m_wstrb != 4'b0000) begin
				if (m_wstrb[0]) mem[m_addr[13:2]][ 7: 0] <= m_wdata[ 7: 0];
				if (m_wstrb[1]) mem[m_addr[13:2]][15: 8] <= m_wdata[15: 8];
				if (m_wstrb[2]) mem[m_addr[13:2]][23:16] <= m_wdata[23:16];
				if (m_wstrb[3]) mem[m_addr[13:2]][31:24] <= m_wdata[31:24];
			end else begin
				m_rdata_q <= mem[m_addr[13:2]];
			end
		end
	end

	// ---- helpers ----
	int errors = 0;
	int cyc = 0;
	always @(posedge clk) if (rstn) cyc <= cyc + 1;

	task automatic check(input string name, input logic cond);
		begin
			if (cond)
				$display("PASS: %s", name);
			else begin
				$display("FAIL: %s", name);
				errors = errors + 1;
			end
		end
	endtask

	// issue one request, hold until rsp_ready, return data + cycle delta
	task automatic do_req(
		input  logic        we,
		input  logic [31:0] addr,
		input  logic [31:0] wd,
		input  logic [3:0]  strb,
		output logic [31:0] rd,
		output int          delta
	);
		int t0;
		begin
			@(negedge clk);
			t0 = cyc;
			req_valid = 1; req_we = we; req_addr = addr;
			req_wdata = wd; req_wstrb = strb;
			@(negedge clk);
			while (!rsp_ready) @(negedge clk);
			rd = rsp_rdata;
			delta = cyc - t0;
			req_valid = 0; req_we = 0; req_wstrb = 4'd0;
			@(negedge clk);
		end
	endtask

	logic [31:0] rd;
	int d0, d1, ops0;

	initial begin
		for (int k = 0; k < 4096; k++) mem[k] = 32'd0;
		mem[0] = 32'hDEAD_BEEF; // line 0x000
		mem[1] = 32'h1111_1111;
		mem[2] = 32'h2222_2222;
		mem[3] = 32'h3333_3333;
		mem[128] = 32'hAAAA_0000; // line 0x100 (word 128 = 0x200/4? no: 0x100/4=64)
		mem[64]  = 32'hBBBB_0000;
		mem[65]  = 32'hBBBB_1111;
		mem[66]  = 32'hBBBB_2222;
		mem[67]  = 32'hBBBB_3333;
		mem[128] = 32'hCCCC_0000; // line 0x200 (0x200/4=128)
		mem[129] = 32'hCCCC_1111;
		mem[130] = 32'hCCCC_2222;
		mem[131] = 32'hCCCC_3333;

		repeat (4) @(posedge clk);
		rstn = 1;
		@(negedge clk);

		// T1: cold load miss -> full line fill -> correct data
		ops0 = bus_ops;
		do_req(1'b0, 32'h000, 32'd0, 4'd0, rd, d0);
		check("T1 cold miss returns line data", rd == 32'hDEAD_BEEF);
		check("T1 fill = 4 bus reads", (bus_ops - ops0) == 4);
		check("T1 miss latency >= 8 cycles", d0 >= 8);

		// T2: repeat load hits (no bus traffic, fast)
		ops0 = bus_ops;
		do_req(1'b0, 32'h004, 32'd0, 4'd0, rd, d1);
		check("T2 hit returns word1", rd == 32'h1111_1111);
		check("T2 hit = 0 bus ops", (bus_ops - ops0) == 0);
		check("T2 hit latency <= 2 cycles", d1 <= 2);

		// T3: store hit -> write-through to memory + line updated
		ops0 = bus_ops;
		do_req(1'b1, 32'h004, 32'h1111_2222, 4'b1111, rd, d1);
		check("T3 store-hit = 1 bus write", (bus_ops - ops0) == 1);
		check("T3 memory updated (write-through)", mem[1] == 32'h1111_2222);
		ops0 = bus_ops;
		do_req(1'b0, 32'h004, 32'd0, 4'd0, rd, d1);
		check("T3 reload returns new data", rd == 32'h1111_2222);
		check("T3 reload hits (0 bus ops)", (bus_ops - ops0) == 0);

		// T4: store miss -> no-write-allocate (memory written, line not cached).
		// 0x440 is in set 4 so it does not compete with set 0's A/B/C lines.
		ops0 = bus_ops;
		do_req(1'b1, 32'h440, 32'hFEED_C0DE, 4'b1111, rd, d1);
		check("T4 store-miss = 1 bus write", (bus_ops - ops0) == 1);
		check("T4 memory updated", mem[272] == 32'hFEED_C0DE);
		ops0 = bus_ops;
		do_req(1'b0, 32'h440, 32'd0, 4'd0, rd, d1);
		check("T4 load after store-miss misses again (NWA)",
			(bus_ops - ops0) == 4);
		check("T4 load returns stored data", rd == 32'hFEED_C0DE);

		// T5: replacement in set 0 (tags 0,1,2 -> 2 ways)
		// A=0x000 present, B=0x100 fills second way, A hit, C=0x200 evicts
		// the LRU (B), then A hits and B misses.
		ops0 = bus_ops;
		do_req(1'b0, 32'h100, 32'd0, 4'd0, rd, d1);
		check("T5a B miss fills line", rd == 32'hBBBB_0000 &&
			(bus_ops - ops0) == 4);
		ops0 = bus_ops;
		do_req(1'b0, 32'h000, 32'd0, 4'd0, rd, d1);
		check("T5b A still hits after B", rd == 32'hDEAD_BEEF &&
			(bus_ops - ops0) == 0);
		ops0 = bus_ops;
		do_req(1'b0, 32'h200, 32'd0, 4'd0, rd, d1);
		check("T5c C miss fills line", rd == 32'hCCCC_0000 &&
			(bus_ops - ops0) == 4);
		ops0 = bus_ops;
		do_req(1'b0, 32'h000, 32'd0, 4'd0, rd, d1);
		check("T5d A hits after C (A more recent than B)",
			(bus_ops - ops0) == 0 && rd == 32'hDEAD_BEEF);
		ops0 = bus_ops;
		do_req(1'b0, 32'h100, 32'd0, 4'd0, rd, d1);
		check("T5e B was evicted by C (miss)", (bus_ops - ops0) == 4);

		// T6: invalidate drops only the addressed line (set 0 holds A+B now)
		@(negedge clk);
		inval_valid = 1; inval_addr = 32'h000;
		@(negedge clk);
		inval_valid = 0;
		ops0 = bus_ops;
		do_req(1'b0, 32'h000, 32'd0, 4'd0, rd, d1);
		check("T6 invalidate -> A misses", (bus_ops - ops0) == 4);
		ops0 = bus_ops;
		do_req(1'b0, 32'h100, 32'd0, 4'd0, rd, d1);
		check("T6 B untouched by A's invalidate (hit)",
			(bus_ops - ops0) == 0 && rd == 32'hBBBB_0000);

		// T7: squashed miss still fills the line (latched-fill FSM).
		// Drop req mid-fill (what a squash does), wait for the bus to go
		// quiet, then re-request: it must HIT with no extra reads.
		@(negedge clk);
		req_valid = 1; req_we = 0; req_addr = 32'h300; // set 3, cold
		repeat (3) @(negedge clk);
		req_valid = 0; // requester squashed mid-fill
		// fill keeps running on its latched state
		while (m_valid) @(negedge clk);
		repeat (3) @(negedge clk);
		check("T7 bus quiet after squashed fill", m_valid == 0);
		ops0 = bus_ops;
		do_req(1'b0, 32'h300, 32'd0, 4'd0, rd, d1);
		check("T7 line filled despite squash (hit, 0 reads)",
			(bus_ops - ops0) == 0 && d1 <= 2);

		if (errors == 0) begin
			$display("DCACHE TEST PASS (policy=%0d)", POL);
			$finish;
		end else begin
			$display("DCACHE TEST FAIL (policy=%0d, errors=%0d)", POL, errors);
			$fatal(1);
		end
	end

	// global timeout guard
	initial begin
		#1_000_000;
		$display("DCACHE TEST FAIL (timeout)");
		$fatal(1);
	end
endmodule
