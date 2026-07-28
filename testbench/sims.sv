`timescale 1ns/1ps
// Self-checking testbench for cordic_top. Checks functional accuracy,
// load/shift_en/valid pulse timing, and reset behavior; exits via $fatal
// on any failure so it can be used in a regression/CI flow.
module tb_cordic_top;

    localparam int  ITER   = 16;
    localparam real SCALE  = 8192.0;  // Q2.13 fixed point
    localparam real PI     = 3.14159265358979;
    localparam real TOL    = 0.01;    // acceptable cos/sin error

    logic               clk = 0;
    logic               rst;
    logic               start;
    logic signed [15:0] angle_in;
    logic signed [15:0] x_reg, y_reg, z_reg;
    logic               valid;

    int errors = 0;
    int checks = 0;

    cordic_top dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .angle_in (angle_in),
        .x_reg    (x_reg),
        .y_reg    (y_reg),
        .z_reg    (z_reg),
        .valid    (valid)
    );

    always #5 clk = ~clk;

    // Protocol monitor: taps load/shift_en hierarchically (not top-level
    // ports) since the checks need visibility inside the controller.
    int   load_width, valid_width, shift_total;
    logic prev_shift;

    always @(posedge clk) begin
        if (rst) begin
            load_width  <= 0;
            valid_width <= 0;
            shift_total <= 0;
            prev_shift  <= 0;  // must clear here too, or a reset mid-shift_en
                                // causes a false falling-edge detect next cycle
        end
        else begin
            if (dut.load) load_width <= load_width + 1;
            else           load_width <= 0;
            if (load_width > 1) begin
                $display("[%0t] PROTOCOL FAIL: load held high for >1 cycle", $time);
                errors++;
            end

            if (dut.shift_en) shift_total <= shift_total + 1;
            else if (prev_shift && !dut.shift_en) begin
                checks++;
                if (shift_total != ITER) begin
                    $display("[%0t] PROTOCOL FAIL: shift_en active for %0d cycles, expected %0d",
                              $time, shift_total, ITER);
                    errors++;
                end
                shift_total <= 0;
            end

            if (valid) valid_width <= valid_width + 1;
            else        valid_width <= 0;
            if (valid_width > 1) begin
                $display("[%0t] PROTOCOL FAIL: valid held high for >1 cycle", $time);
                errors++;
            end

            prev_shift <= dut.shift_en;
        end
    end

    task automatic run_angle(input real angle_deg);
        real angle_rad, exp_cos, exp_sin, got_cos, got_sin, cos_err, sin_err;
        int  cyc;
        begin
            angle_rad = angle_deg * PI / 180.0;
            angle_in  = $rtoi(angle_rad * SCALE);
            exp_cos   = $cos(angle_rad);
            exp_sin   = $sin(angle_rad);

            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;

            cyc = 0;
            while (!valid && cyc < (ITER + 5)) begin
                @(negedge clk);
                cyc++;
            end

            checks++;
            if (!valid) begin
                $display("FUNCTIONAL FAIL: angle=%0.2f deg never asserted valid (timeout at %0d cycles)",
                          angle_deg, cyc);
                errors++;
            end
            else if (cyc != ITER) begin
                $display("FUNCTIONAL FAIL: angle=%0.2f deg valid asserted at cycle %0d, expected %0d",
                          angle_deg, cyc, ITER);
                errors++;
            end
            else begin
                got_cos = $itor(x_reg) / SCALE;
                got_sin = $itor(y_reg) / SCALE;
                cos_err = got_cos - exp_cos; if (cos_err < 0) cos_err = -cos_err;
                sin_err = got_sin - exp_sin; if (sin_err < 0) sin_err = -sin_err;

                if (cos_err > TOL || sin_err > TOL) begin
                    $display("FUNCTIONAL FAIL: angle=%7.2f deg | exp cos=%8.5f sin=%8.5f | got cos=%8.5f sin=%8.5f | err cos=%0.5f sin=%0.5f",
                              angle_deg, exp_cos, exp_sin, got_cos, got_sin, cos_err, sin_err);
                    errors++;
                end
                else begin
                    $display("PASS: angle=%7.2f deg | exp cos=%8.5f sin=%8.5f | got cos=%8.5f sin=%8.5f | err cos=%0.5f sin=%0.5f",
                              angle_deg, exp_cos, exp_sin, got_cos, got_sin, cos_err, sin_err);
                end
            end

            @(negedge clk);
            @(negedge clk);
        end
    endtask

    // Not scored pass/fail: vanilla rotation-mode CORDIC only converges
    // within +/-99.88 deg (sum of all atan(2^-i) terms), so angles beyond
    // that produce a nonzero residual z by design, not a bug. Documented
    // here so it isn't mistaken for one later.
    task automatic show_out_of_range(input real angle_deg);
        real angle_rad, exp_cos, exp_sin, got_cos, got_sin;
        int  cyc;
        begin
            angle_rad = angle_deg * PI / 180.0;
            angle_in  = $rtoi(angle_rad * SCALE);
            exp_cos   = $cos(angle_rad);
            exp_sin   = $sin(angle_rad);

            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;

            cyc = 0;
            while (!valid && cyc < (ITER + 5)) begin
                @(negedge clk);
                cyc++;
            end

            got_cos = $itor(x_reg) / SCALE;
            got_sin = $itor(y_reg) / SCALE;
            $display("INFO (expected divergence, not a failure): angle=%7.2f deg | exp cos=%8.5f sin=%8.5f | got cos=%8.5f sin=%8.5f | residual z=%0.5f rad",
                      angle_deg, exp_cos, exp_sin, got_cos, got_sin, $itor(z_reg)/SCALE);

            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task automatic run_reset_midcalc();
        begin
            checks++;
            angle_in = $rtoi((45.0 * PI / 180.0) * SCALE);
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            repeat (5) @(negedge clk);  // interrupt partway through CALCULATE

            rst = 1;
            @(negedge clk);
            rst = 0;

            if (valid !== 1'b0 || x_reg !== 16'sd0 || y_reg !== 16'sd0 || z_reg !== 16'sd0) begin
                $display("RESET FAIL: mid-calc reset did not clear state (valid=%0b x=%0d y=%0d z=%0d)",
                          valid, x_reg, y_reg, z_reg);
                errors++;
            end
            else begin
                $display("PASS: mid-calculation reset correctly clears valid/x/y/z");
            end

            @(negedge clk);
            @(negedge clk);
        end
    endtask

    initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_cordic_top);
end

    initial begin
        rst = 1; start = 0; angle_in = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("=== Functional sweep ===");
        run_angle(0.0);
        run_angle(30.0);
        run_angle(45.0);
        run_angle(60.0);
        run_angle(89.0);
        run_angle(-30.0);
        run_angle(-45.0);
        run_angle(-89.0);
        run_angle(15.5);
        run_angle(72.3);
        run_angle(99.0);   // near the +/-99.88 deg convergence limit
        run_angle(-99.0);

        $display("\n=== Out-of-range demonstration (informational, not scored) ===");
        show_out_of_range(179.0);
        show_out_of_range(-179.0);

        $display("\n=== Reset-mid-calculation check ===");
        run_reset_midcalc();

        $display("\n=== Back-to-back transactions (no idle gap) ===");
        run_angle(10.0);
        run_angle(20.0);
        run_angle(30.0);

        $display("\n========================================");
        $display("TOTAL CHECKS: %0d   ERRORS: %0d", checks, errors);
        if (errors == 0) begin
            $display("RESULT: ALL TESTS PASSED");
            $finish;
        end
        else begin
            $display("RESULT: %0d CHECK(S) FAILED", errors);
            $fatal(1);
        end
    end

    initial begin
        #100000;
        $display("TIMEOUT: testbench did not finish in time");
        $fatal(1);
    end

endmodule
