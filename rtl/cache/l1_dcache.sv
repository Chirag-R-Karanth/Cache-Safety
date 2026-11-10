// Set-associative L1 data cache sitting between the pipeline's mem stage
// and the external data bus.
//
// Policy:
// - Write-through, no-write-allocate. Stores always write memory (so the
//   ISS-visible memory image, the TB magic signature and DMA-style
//   observers stay coherent) and update the line only when it is already
//   present. Loads fill a whole line on miss.
// - Replacement: POLICY 0 = exact LRU, 1 = tree-PLRU (rtl/cache/).
// - Invalidate port drops the line containing inval_addr (Flush+Reload).
//
// Speculative fill (Phase 4's key property): once a miss starts, the fill
// FSM runs to completion using *latched* line state even if the requesting
// instruction is squashed mid-fill (req_valid drops). The line therefore
// becomes valid — a timing-visible side effect of a squashed load, which
// is exactly what the Spectre attack measures. The squashed instruction's
// data return is discarded by the pipeline (MEM/WB cleared on squash).
module l1_dcache #(
	parameter int SETS = 16,
	parameter int WAYS = 2,
	parameter int LINE_WORDS = 4,   // 16-byte lines by default
	parameter int POLICY = 0        // 0: LRU, 1: PLRU
) (
	input  logic clk,
	input  logic rstn,
	// request side (from mem_stage; held stable until rsp_ready)
	input  logic        req_valid,
	input  logic [31:0] req_addr,
	input  logic [31:0] req_wdata,
	input  logic [3:0]  req_wstrb,
	input  logic        req_we,      // 1 = store
	output logic        rsp_ready,   // 1-cycle completion pulse
	output logic [31:0] rsp_rdata,
	// invalidate: drop the line containing inval_addr
	input  logic        inval_valid,
	input  logic [31:0] inval_addr,
	// memory side (same valid/ready protocol as the TB slave)
	output logic        m_valid,
	output logic [31:0] m_addr,
	output logic [31:0] m_wdata,
	output logic [3:0]  m_wstrb,
	input  logic        m_ready,
	input  logic [31:0] m_rdata
);
	localparam int SW = $clog2(SETS);
	localparam int WW = $clog2(WAYS);
	localparam int OW = $clog2(LINE_WORDS);
	localparam int OFF_W = OW + 2;              // byte-offset bits in an address
	localparam int TAG_W = 32 - OFF_W - SW;

	// request address fields
	logic [TAG_W-1:0] req_tag;
	logic [SW-1:0]    req_set;
	logic [OW-1:0]    req_word;
	logic [31:0]      line_base;
	assign req_tag   = req_addr[31:OFF_W+SW];
	assign req_set   = req_addr[OFF_W+SW-1:OFF_W];
	assign req_word  = req_addr[OFF_W-1:2];
	assign line_base = {req_addr[31:OFF_W], {OFF_W{1'b0}}};

	// invalidate address fields
	logic [TAG_W-1:0] inval_tag;
	logic [SW-1:0]    inval_set;
	assign inval_tag = inval_addr[31:OFF_W+SW];
	assign inval_set = inval_addr[OFF_W+SW-1:OFF_W];

	// storage
	logic [31:0]      data_q [SETS][WAYS][LINE_WORDS];
	logic [TAG_W-1:0] tag_q  [SETS][WAYS];
	logic             valid_q [SETS][WAYS];

	// hit detection
	logic [WAYS-1:0] way_hit;
	logic            hit;
	logic [WW-1:0]   hit_way;
	always_comb begin
		way_hit = '0;
		hit_way = '0;
		for (int w = 0; w < WAYS; w++) begin
			way_hit[w] = valid_q[req_set][w] && (tag_q[req_set][w] == req_tag);
			if (way_hit[w]) hit_way = WW'(w);
		end
		hit = |way_hit;
	end

	// replacement
	logic              repl_upd;
	logic [WW-1:0]     repl_upd_way;
	logic [SW-1:0]     repl_upd_set;
	logic [WW-1:0]     victim_way;
	generate
		if (POLICY == 0) begin : g_lru
			replacement_lru #(.SETS(SETS), .WAYS(WAYS)) u_repl (
				.clk(clk), .rstn(rstn),
				.upd_valid(repl_upd), .upd_set(repl_upd_set), .upd_way(repl_upd_way),
				.look_set(req_set), .victim_way(victim_way)
			);
		end else begin : g_plru
			replacement_plru #(.SETS(SETS), .WAYS(WAYS)) u_repl (
				.clk(clk), .rstn(rstn),
				.upd_valid(repl_upd), .upd_set(repl_upd_set), .upd_way(repl_upd_way),
				.look_set(req_set), .victim_way(victim_way)
			);
		end
	endgenerate

	// FSM
	typedef enum logic [1:0] {S_IDLE, S_RESP, S_FILL, S_WT} state_e;
	state_e state_q;
	logic [OW-1:0]  fill_idx_q;
	logic [WW-1:0]  fill_way_q;
	logic [SW-1:0]  fill_set_q;
	logic [TAG_W-1:0] fill_tag_q;
	logic [31:0]    fill_base_q;
	logic [31:0]    rsp_rdata_q;

	logic fill_word_last;
	assign fill_word_last = (fill_idx_q == OW'(LINE_WORDS - 1));

	// store byte-merge (write hit updates the line)
	logic [31:0] store_merged;
	always_comb begin
		store_merged = data_q[req_set][hit_way][req_word];
		if (req_wstrb[0]) store_merged[ 7: 0] = req_wdata[ 7: 0];
		if (req_wstrb[1]) store_merged[15: 8] = req_wdata[15: 8];
		if (req_wstrb[2]) store_merged[23:16] = req_wdata[23:16];
		if (req_wstrb[3]) store_merged[31:24] = req_wdata[31:24];
	end

	// replacement update: on any served hit, or when a fill completes
	// (fill updates must use the latched set — req_* may change if the
	// requester was squashed mid-fill)
	assign repl_upd = (state_q == S_IDLE && req_valid && hit) ||
	                  (state_q == S_FILL && m_ready && fill_word_last);
	assign repl_upd_way = (state_q == S_FILL) ? fill_way_q : hit_way;
	assign repl_upd_set = (state_q == S_FILL) ? fill_set_q : req_set;

	// memory-side master
	always_comb begin
		m_valid = 1'b0;
		m_addr  = 32'd0;
		m_wdata = 32'd0;
		m_wstrb = 4'd0;
		case (state_q)
			S_FILL: begin
				m_valid = 1'b1;
				m_addr  = fill_base_q + (32'(fill_idx_q) << 2);
			end
			S_WT: begin
				m_valid = 1'b1;
				m_addr  = req_addr;
				m_wdata = req_wdata;
				m_wstrb = req_wstrb;
			end
			default: ;
		endcase
	end

	assign rsp_ready = (state_q == S_RESP);
	assign rsp_rdata = rsp_rdata_q;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			state_q     <= S_IDLE;
			fill_idx_q  <= '0;
			fill_way_q  <= '0;
			fill_set_q  <= '0;
			fill_tag_q  <= '0;
			fill_base_q <= 32'd0;
			rsp_rdata_q <= 32'd0;
			for (int s = 0; s < SETS; s++)
				for (int w = 0; w < WAYS; w++) begin
					valid_q[s][w] <= 1'b0;
					tag_q[s][w]   <= '0;
				end
		end else begin
			case (state_q)
				S_IDLE: begin
					if (req_valid) begin
						if (req_we) begin
							// write-through: update line only if present,
							// always write memory (S_WT)
							if (hit)
								data_q[req_set][hit_way][req_word] <= store_merged;
							state_q <= S_WT;
						end else if (hit) begin
							rsp_rdata_q <= data_q[req_set][hit_way][req_word];
							state_q <= S_RESP;
						end else begin
							// miss: latch line identity (the requester may be
							// squashed mid-fill; the fill must still complete)
							fill_way_q  <= victim_way;
							fill_set_q  <= req_set;
							fill_tag_q  <= req_tag;
							fill_base_q <= line_base;
							fill_idx_q  <= '0;
							valid_q[req_set][victim_way] <= 1'b0;
							state_q <= S_FILL;
						end
					end
				end
				S_RESP: state_q <= S_IDLE;
				S_WT: begin
					if (m_ready)
						state_q <= S_RESP;
				end
				S_FILL: begin
					if (m_ready) begin
						data_q[fill_set_q][fill_way_q][fill_idx_q] <= m_rdata;
						if (fill_word_last) begin
							valid_q[fill_set_q][fill_way_q] <= 1'b1;
							tag_q[fill_set_q][fill_way_q]   <= fill_tag_q;
							state_q <= S_IDLE; // re-serve the request (now hit)
						end else begin
							fill_idx_q <= fill_idx_q + OW'(1);
						end
					end
				end
				default: state_q <= S_IDLE;
			endcase

			// invalidate wins over same-cycle valid updates (applied last)
			if (inval_valid) begin
				for (int w = 0; w < WAYS; w++)
					if (valid_q[inval_set][w] && tag_q[inval_set][w] == inval_tag)
						valid_q[inval_set][w] <= 1'b0;
			end
		end
	end
endmodule
