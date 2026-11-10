// Phase 0 smoke test: forked PicoRV32 runs its reference "ez" program
// (increment loop over word at 0x3FC) under Icarus Verilog.
// Self-checking: PASS if the counter word advanced, FAIL otherwise.
`timescale 1 ns / 1 ps

module tb_picorv32;
	reg clk = 1;
	reg resetn = 0;
	wire trap;

	always #5 clk = ~clk;

	wire mem_valid;
	wire mem_instr;
	reg mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0] mem_wstrb;
	reg  [31:0] mem_rdata;

	picorv32 uut (
		.clk         (clk        ),
		.resetn      (resetn     ),
		.trap        (trap       ),
		.mem_valid   (mem_valid  ),
		.mem_instr   (mem_instr  ),
		.mem_ready   (mem_ready  ),
		.mem_addr    (mem_addr   ),
		.mem_wdata   (mem_wdata  ),
		.mem_wstrb   (mem_wstrb  ),
		.mem_rdata   (mem_rdata  )
	);

	reg [31:0] memory [0:255];

	// Same program as upstream testbench_ez.v
	initial begin
		memory[0] = 32'h 3fc00093; //       li      x1,1020
		memory[1] = 32'h 0000a023; //       sw      x0,0(x1)
		memory[2] = 32'h 0000a103; // loop: lw      x2,0(x1)
		memory[3] = 32'h 00110113; //       addi    x2,x2,1
		memory[4] = 32'h 0020a023; //       sw      x2,0(x1)
		memory[5] = 32'h ff5ff06f; //       j       <loop>
	end

	always @(posedge clk) begin
		mem_ready <= 0;
		if (mem_valid && !mem_ready) begin
			if (mem_addr < 1024) begin
				mem_ready <= 1;
				mem_rdata <= memory[mem_addr >> 2];
				if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
				if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
				if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
			end
		end
	end

	localparam WORD_IDX = 1020 >> 2; // 255: counter word

	integer cycles = 0;
	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("tb_picorv32.vcd");
			$dumpvars(0, tb_picorv32);
		end
		repeat (10) @(posedge clk);
		resetn <= 1;
		// Run long enough for many loop iterations (each ~5 mem transactions)
		repeat (2000) @(posedge clk);
		cycles = 2010;

		if (memory[WORD_IDX] > 32'd3) begin
			$display("PASS: counter=%0d after %0d cycles", memory[WORD_IDX], cycles);
			$finish;
		end else begin
			$display("FAIL: counter=%0d (expected > 3) after %0d cycles", memory[WORD_IDX], cycles);
			$fatal(1);
		end
	end

	// Trap before completion is a failure
	always @(posedge clk) begin
		if (resetn && trap) begin
			$display("FAIL: core trapped early at cycle %0d", cycles);
			$fatal(1);
		end
	end
endmodule
