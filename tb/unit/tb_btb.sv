// Unit test for the direct-mapped BTB: miss after reset, hit with the
// trained target/cond, tag-mismatch miss (aliasing on the index), entry
// overwrite, and independence of a different index. Self-checking.
`timescale 1 ns / 1 ps

module tb_btb;
	logic clk = 1;
	logic rstn = 0;
	always #5 clk = ~clk;

	logic [31:0] predict_pc;
	logic        predict_hit;
	logic [31:0] predict_target;
	logic        predict_cond;
	logic        train_valid;
	logic [31:0] train_pc;
	logic [31:0] train_target;
	logic        train_cond;

	int errors = 0;
	int checks = 0;

	btb #(.ENTRIES(64)) dut (
		.clk(clk), .rstn(rstn),
		.predict_pc(predict_pc),
		.predict_hit(predict_hit),
		.predict_target(predict_target),
		.predict_cond(predict_cond),
		.train_valid(train_valid),
		.train_pc(train_pc),
		.train_target(train_target),
		.train_cond(train_cond)
	);

	task automatic train(input [31:0] pc, input [31:0] tgt, input cond);
		begin
			@(negedge clk);
			train_valid = 1'b1;
			train_pc = pc;
			train_target = tgt;
			train_cond = cond;
			@(negedge clk);
			train_valid = 1'b0;
		end
	endtask

	task automatic expect_btb(input [31:0] pc, input exp_hit,
	                          input [31:0] exp_tgt, input exp_cond,
	                          input string what);
		begin
			@(negedge clk);
			predict_pc = pc;
			#1;
			checks++;
			if (predict_hit !== exp_hit ||
			    (exp_hit && (predict_target !== exp_tgt ||
			                 predict_cond !== exp_cond))) begin
				$display("FAIL %s: pc=%08x hit=%b tgt=%08x cond=%b (exp hit=%b tgt=%08x cond=%b)",
					what, pc, predict_hit, predict_target, predict_cond,
					exp_hit, exp_tgt, exp_cond);
				errors++;
			end
		end
	endtask

	initial begin
		predict_pc = 32'd0;
		train_valid = 1'b0;
		train_pc = 32'd0;
		train_target = 32'd0;
		train_cond = 1'b0;
		repeat (3) @(posedge clk);
		rstn = 1;

		// cold: everything misses
		expect_btb(32'h0000_0100, 1'b0, 32'd0, 1'b0, "cold miss");

		// train a conditional branch at 0x100 (index [7:2]=0, tag=1)
		train(32'h0000_0100, 32'h0000_1234, 1'b1);
		expect_btb(32'h0000_0100, 1'b1, 32'h0000_1234, 1'b1, "hit after train");

		// same index, different tag (0x500: index 0, tag 5): miss
		expect_btb(32'h0000_0500, 1'b0, 32'd0, 1'b0, "tag mismatch miss");

		// overwrite same entry: unconditional jump now (cond=0)
		train(32'h0000_0100, 32'h0000_2000, 1'b0);
		expect_btb(32'h0000_0100, 1'b1, 32'h0000_2000, 1'b0, "entry overwritten");

		// different index (0x010: index 4) is independent
		train(32'h0000_0010, 32'h0000_0800, 1'b1);
		expect_btb(32'h0000_0010, 1'b1, 32'h0000_0800, 1'b1, "second entry hit");
		expect_btb(32'h0000_0100, 1'b1, 32'h0000_2000, 1'b0, "first entry kept");

		if (errors == 0) begin
			$display("PASS: tb_btb %0d checks", checks);
			$finish;
		end else begin
			$display("FAIL: tb_btb %0d/%0d checks failed", errors, checks);
			$fatal(1);
		end
	end
endmodule
