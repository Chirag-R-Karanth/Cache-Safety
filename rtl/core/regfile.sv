// 32 x 32-bit register file: 2 combinational read ports, 1 synchronous write.
// x0 hardwired to zero. Write-first bypass so a decode-stage read in the same
// cycle as a write observes the new value (required for correctness when the
// consumer sits in ID while the producer retires in WB).
module regfile (
	input  logic        clk,
	input  logic        wen,
	input  logic [4:0]  waddr,
	input  logic [31:0] wdata,
	input  logic [4:0]  raddr1,
	input  logic [4:0]  raddr2,
	output logic [31:0] rdata1,
	output logic [31:0] rdata2
);
	logic [31:0] regs [31:1];

	always_ff @(posedge clk) begin
		if (wen && waddr != 5'd0)
			regs[waddr] <= wdata;
	end

	always_comb begin
		rdata1 = (raddr1 == 5'd0) ? 32'd0 :
		         (wen && waddr == raddr1 && waddr != 5'd0) ? wdata : regs[raddr1];
		rdata2 = (raddr2 == 5'd0) ? 32'd0 :
		         (wen && waddr == raddr2 && waddr != 5'd0) ? wdata : regs[raddr2];
	end
endmodule
