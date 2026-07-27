module cordic_datapath (
    input  logic               clk,
    input  logic               rst,

    input  logic                load,
    input  logic                shift_en,

    input  logic signed [15:0] angle_in,

    output logic signed [15:0] x_reg,
    output logic signed [15:0] y_reg,
    output logic signed [15:0] z_reg
);

    typedef logic signed [15:0] fixed_t;

    localparam int    ITER      = 16;
    localparam fixed_t INV_GAIN = 16'sd4975;

    fixed_t       x_q, y_q, z_q;
    fixed_t       atan_queue [0:ITER-1];
    logic [3:0]   shift_cnt;

    logic sigma;
    assign sigma = ~z_q[15];

    fixed_t x_shifted, y_shifted;
    assign y_shifted = y_q >>> shift_cnt;
    assign x_shifted = x_q >>> shift_cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            x_q       <= '0;
            y_q       <= '0;
            z_q       <= '0;
            shift_cnt <= '0;
            for (int i = 0; i < ITER; i++) atan_queue[i] <= '0;
        end
        else if (load) begin
            x_q       <= INV_GAIN;
            y_q       <= '0;
            z_q       <= angle_in;
            shift_cnt <= '0;

            atan_queue[0]  <= 16'sd6434;
            atan_queue[1]  <= 16'sd3798;
            atan_queue[2]  <= 16'sd2007;
            atan_queue[3]  <= 16'sd1019;
            atan_queue[4]  <= 16'sd511;
            atan_queue[5]  <= 16'sd256;
            atan_queue[6]  <= 16'sd128;
            atan_queue[7]  <= 16'sd64;
            atan_queue[8]  <= 16'sd32;
            atan_queue[9]  <= 16'sd16;
            atan_queue[10] <= 16'sd8;
            atan_queue[11] <= 16'sd4;
            atan_queue[12] <= 16'sd2;
            atan_queue[13] <= 16'sd1;
            atan_queue[14] <= 16'sd0;
            atan_queue[15] <= 16'sd0;
        end
        else if (shift_en) begin
            if (sigma) begin
                x_q <= x_q - y_shifted;
                y_q <= y_q + x_shifted;
                z_q <= z_q - atan_queue[0];
            end
            else begin
                x_q <= x_q + y_shifted;
                y_q <= y_q - x_shifted;
                z_q <= z_q + atan_queue[0];
            end

            shift_cnt <= shift_cnt + 1'b1;

            for (int i = 0; i < ITER-1; i++)
                atan_queue[i] <= atan_queue[i+1];
            atan_queue[ITER-1] <= atan_queue[ITER-1];
        end
    end

    assign x_reg = x_q;
    assign y_reg = y_q;
    assign z_reg = z_q;

endmodule 