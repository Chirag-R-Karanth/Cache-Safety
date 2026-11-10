// Unit test for the 2-bit saturating BHT: reset state, saturating
// transitions in both directions, index aliasing, and independence of
// different indices. Self-checking; prints PASS or FAIL per check.
`timescale 1 ns / 1 ps

module tb_bht;
	logic clk = 1;
	logic rstn = 0;
	always #5 clk = ~clk;

	logic [31:0] predict_pc;
	logic        predict_taken;
	logic        train_valid;
	logic [31:0] train_pc;
	logic        train_taken;

	int errors = 0;
	int checks = 0;

	bht_2bit #(.ENTRIES(256)) dut (
		.clk(clk), .rstn(rstn),
		.predict_pc(predict_pc),
		.predict_taken(predict_taken),
		.train_valid(train_valid),
		.train_pc(train_pc),
		.train_taken(train_taken)
	);

	task automatic train(input [31:0] pc, input taken);
		begin
			@(negedge clk);
			train_valid = 1'b1;
			train_pc = pc;
			train_taken = taken;
			@(negedge clk);
			train_valid = 1'b0;
		end
	endtask

	task automatic expect_pred(input [31:0] pc, input exp, input string what);
		begin
			@(negedge clk);
			predict_pc = pc;
			#1;
			checks++;
			if (predict_taken !== exp) begin
				$display("FAIL %s: pc=%08x predict=%b expected=%b",
					what, pc, predict_taken, exp);
				errors++;
			end
		end
	endtask

	initial begin
		predict_pc = 32'd0;
		train_valid = 1'b0;
		train_pc = 32'd0;
		train_taken = 1'b0;
		repeat (3) @(posedge clk);
		rstn = 1;

		// reset: weakly not-taken
		expect_pred(32'h0000_0100, 1'b0, "reset weakly NT");

		// learn taken at 0x100: 01 -> 10 (weakly taken)
		train(32'h0000_0100, 1'b1);
		expect_pred(32'h0000_0100, 1'b1, "after 1x taken");
		// 10 -> 11 (strongly taken)
		train(32'h0000_0100, 1'b1);
		expect_pred(32'h0000_0100, 1'b1, "after 2x taken");
		// saturate high: stays 11
		train(32'h0000_0100, 1'b1);
		expect_pred(32'h0000_0100, 1'b1, "saturated taken");

		// decay: 11 -> 10 (still taken), 10 -> 01 (not taken), 01 -> 00
		train(32'h0000_0100, 1'b0);
		expect_pred(32'h0000_0100, 1'b1, "decay 11->10");
		train(32'h0000_0100, 1'b0);
		expect_pred(32'h0000_0100, 1'b0, "decay 10->01");
		train(32'h0000_0100, 1'b0);
		expect_pred(32'h0000_0100, 1'b0, "saturated NT");
		train(32'h0000_0100, 1'b0);
		expect_pred(32'h0000_0100, 1'b0, "stays saturated NT");

		// aliasing: 0x500 shares index [9:2] with 0x100 (untagged table)
		train(32'h0000_0500, 1'b1); // shared counter 00 -> 01
		train(32'h0000_0500, 1'b1); // 01 -> 10
		expect_pred(32'h0000_0500, 1'b1, "alias pc trained taken");
		expect_pred(32'h0000_0100, 1'b1, "aliased neighbour sees taken");

		// different index is independent
		expect_pred(32'h0000_0200, 1'b0, "other index untouched");

		if (errors == 0) begin
			$display("PASS: tb_bht %0d checks", checks);
			$finish;
		end else begin
			$display("FAIL: tb_bht %0d/%0d checks failed", errors, checks);
			$fatal(1);
		end
	end
endmodule
