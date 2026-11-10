// Writeback stage: selects the value written to the register file when an
// instruction retires from MEM/WB.
module writeback (
	input  core_pkg::memwb_t memwb,
	output logic        wen,
	output logic [4:0]  waddr,
	output logic [31:0] wdata
);
	import core_pkg::*;

	assign wen   = memwb.valid && memwb.wb_en;
	assign waddr = memwb.rd;
	assign wdata = wb_value(memwb);
endmodule
