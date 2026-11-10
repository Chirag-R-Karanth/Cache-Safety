// CSR file: cycle and instret counters (read-only aliases at the standard
// user/machine addresses). Writes are accepted on `fire` but currently ignored
// (counters are read-only); the port stays for future CSRs (privilege, etc.).
module csr (
	input  logic        clk,
	input  logic        rstn,
	input  logic        req,
	input  logic [11:0] addr,
	input  logic [1:0]  op,      // core_pkg::csr_op_e (unused: read-only)
	input  logic [31:0] wdata,
	input  logic        fire,
	output logic [31:0] rdata,
	input  logic        retire
);
	import core_pkg::*;

	logic [31:0] cycle_q, instret_q;

	localparam logic [11:0] CSR_CYCLE    = 12'hC00;
	localparam logic [11:0] CSR_INSTRET  = 12'hC02;
	localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
	localparam logic [11:0] CSR_MINSTRET = 12'hB02;

	always_comb begin
		unique case (addr)
			CSR_CYCLE, CSR_MCYCLE:       rdata = cycle_q;
			CSR_INSTRET, CSR_MINSTRET:   rdata = instret_q;
			default:                     rdata = 32'd0;
		endcase
	end

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			cycle_q <= 32'd0;
			instret_q <= 32'd0;
		end else begin
			cycle_q <= cycle_q + 32'd1;
			if (retire)
				instret_q <= instret_q + 32'd1;
		end
	end
endmodule
