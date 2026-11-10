// Shared types for the 5-stage RV32I pipeline (core5).
// Decoder semantics derived from the PicoRV32 fork (rtl/core/picorv32).
package core_pkg;

	typedef enum logic [3:0] {
		ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
		ALU_SLT, ALU_SLTU, ALU_SLL, ALU_SRL, ALU_SRA, ALU_B
	} alu_op_e;

	typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4, WB_CSR } wb_sel_e;
	typedef enum logic [1:0] { CSR_NONE, CSR_RW, CSR_RS, CSR_RC } csr_op_e;
	typedef enum logic [1:0] { SZ_B, SZ_H, SZ_W } mem_size_e;

	// Decode-stage control word
	typedef struct packed {
	 logic valid;
	 logic is_load, is_store, is_branch, is_jal, is_jalr;
	 logic is_lui, is_auipc, is_alui, is_alu, is_system;
	 logic uses_rs1, uses_rs2;
	 alu_op_e alu_op;
	 logic alu_src1_pc;    // 1: PC, 0: rs1
	 logic alu_src2_imm;   // 1: immediate, 0: rs2
	 mem_size_e mem_size;
	 logic mem_unsigned;
	 wb_sel_e wb_sel;
	 logic wb_en;
	 csr_op_e csr_op;
	 logic [11:0] csr_addr;
	 logic ecall, ebreak, illegal;
	 logic [2:0] funct3;
	} ctrl_t;

	// Prediction info captured with the instruction at fetch: what the
	// BTB/BHT said, carried to EX so the branch can compare actual vs
	// predicted when it resolves.
	typedef struct packed {
	 logic valid;
	 logic [31:0] pc, instr;
	 logic pred_taken;
	 logic [31:0] pred_target;
	} ifid_t;

	typedef struct packed {
	 logic valid;
	 logic [31:0] pc, rs1_val, rs2_val, imm;
	 logic [4:0] rs1, rs2, rd;
	 logic pred_taken;
	 logic [31:0] pred_target;
	 ctrl_t c;
	} idex_t;

	typedef struct packed {
	 logic valid;
	 logic [31:0] ex_result;  // ALU / CSR / PC+4 result (forwarded)
	 logic [31:0] store_data; // forwarded rs2 for stores
	 logic [31:0] pc;
	 logic [4:0] rd;
	 ctrl_t c;
	} exmem_t;

	typedef struct packed {
	 logic valid;
	 logic [31:0] ex_result, mem_data, pc;
	 logic [4:0] rd;
	 logic wb_en;
	 wb_sel_e wb_sel;
	} memwb_t;

	function automatic ctrl_t bubble_ctrl();
		bubble_ctrl = '0;
	endfunction

	function automatic logic [31:0] wb_value(input memwb_t m);
		wb_value = (m.wb_sel == WB_MEM) ? m.mem_data : m.ex_result;
	endfunction

endpackage
