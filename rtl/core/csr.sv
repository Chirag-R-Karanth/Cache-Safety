// CSR file: cycle/instret counters plus a minimal mstatus privilege register.
// mstatus (0x300) bit 0 = UPRIV: 1 = user mode, 0 = machine/supervisor.
// Writes to read-only counters are accepted on `fire` but ignored; mstatus
// is read/write. The port stays for future CSRs.
module csr (
	input  logic        clk,
	input  logic        rstn,
	input  logic        req,
	input  logic [11:0] addr,
	input  logic [1:0]  op,      // core_pkg::csr_op_e
	input  logic [31:0] wdata,
	input  logic        fire,
	output logic [31:0] rdata,
	input  logic        retire,
	output logic        priv_user // 1 = current privilege mode is user
);
	import core_pkg::*;

	logic [31:0] cycle_q, instret_q, mstatus_q;

	localparam logic [11:0] CSR_CYCLE    = 12'hC00;
	localparam logic [11:0] CSR_INSTRET  = 12'hC02;
	localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
	localparam logic [11:0] CSR_MINSTRET = 12'hB02;
	localparam logic [11:0] CSR_MSTATUS  = 12'h300;

	logic csr_write;
	assign csr_write = fire && (op == CSR_RW || op == CSR_RS || op == CSR_RC);

	always_comb begin
		unique case (addr)
			CSR_CYCLE, CSR_MCYCLE:       rdata = cycle_q;
			CSR_INSTRET, CSR_MINSTRET:   rdata = instret_q;
			CSR_MSTATUS:                 rdata = mstatus_q;
			default:                     rdata = 32'd0;
		endcase
	end

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			cycle_q    <= 32'd0;
			instret_q  <= 32'd0;
			mstatus_q  <= 32'd0; // reset to machine mode
		end else begin
			cycle_q <= cycle_q + 32'd1;
			if (retire)
				instret_q <= instret_q + 32'd1;
			if (csr_write && addr == CSR_MSTATUS) begin
				unique case (op)
					CSR_RW: mstatus_q <= wdata;
					CSR_RS: mstatus_q <= mstatus_q | wdata;
					CSR_RC: mstatus_q <= mstatus_q & ~wdata;
					default: ;
				endcase
			end
		end
	end

	assign priv_user = mstatus_q[0];
endmodule
