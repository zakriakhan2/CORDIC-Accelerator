module cordic_top (
    input  logic               clk,
    input  logic               rst,
    input  logic                start,
    input  logic signed [15:0] angle_in,
    output logic signed [15:0] x_reg,   //cos(angle_in)*gain-compensated
    output logic signed [15:0] y_reg,   //sin(angle_in)
    output logic signed [15:0] z_reg,   //residual angle(~0 when valid)
    output logic                valid
);

    logic load;
    logic shift_en;

    cordic_controller u_cordic_controller (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .load     (load),
        .shift_en (shift_en),
        .valid    (valid)
    );

    cordic_datapath u_cordic_datapath (
        .clk      (clk),
        .rst      (rst),
        .load     (load),
        .shift_en (shift_en),
        .angle_in (angle_in),
        .x_reg    (x_reg),
        .y_reg    (y_reg),
        .z_reg    (z_reg)
    );

endmodule