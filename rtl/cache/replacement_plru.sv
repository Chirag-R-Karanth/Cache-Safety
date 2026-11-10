// Tree-PLRU replacement for a set-associative power-of-2 cache.
// One (WAYS-1)-bit tree per set (heap layout: children of node n are
// 2n+1 / 2n+2). A bit selects the LRU child at that node; `victim_way`
// walks the tree, `upd_*` walks to the accessed way and flips each bit
// to point away from it.
module replacement_plru #(
	parameter int SETS = 16,
	parameter int WAYS = 2
) (
	input  logic clk,
	input  logic rstn,
	input  logic                    upd_valid,
	input  logic [$clog2(SETS)-1:0] upd_set,
	input  logic [$clog2(WAYS)-1:0] upd_way,
	input  logic [$clog2(SETS)-1:0] look_set,
	output logic [$clog2(WAYS)-1:0] victim_way
);
	localparam int SW = $clog2(SETS);
	localparam int WW = $clog2(WAYS);
	localparam int NODES = WAYS - 1;

	logic [NODES-1:0] tree_q [SETS];
	logic [WW-1:0] way_c;
	int node_v; // victim-walk cursor (comb)
	int node_u; // update-walk cursor (seq)

	// victim walk: way MSB first
	always_comb begin
		way_c = '0;
		node_v = 0;
		for (int l = WW - 1; l >= 0; l--) begin
			way_c = (way_c << 1) | WW'(tree_q[look_set][node_v]);
			node_v = 2 * node_v + 1 + int'(tree_q[look_set][node_v]);
		end
	end
	assign victim_way = way_c;

	always_ff @(posedge clk or negedge rstn) begin
		if (!rstn) begin
			for (int s = 0; s < SETS; s++)
				tree_q[s] <= '0; // all bits point at child 0
		end else if (upd_valid) begin
			node_u = 0;
			for (int l = WW - 1; l >= 0; l--) begin
				// point this node away from the accessed child
				tree_q[upd_set][node_u] <= ~upd_way[l];
				node_u = 2 * node_u + 1 + int'(upd_way[l]);
			end
		end
	end
endmodule
