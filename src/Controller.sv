module cordic_controller (
    input  logic clk,
    input  logic rst,

    input  logic start,

    output logic load,
    output logic shift_en,
    output logic valid
);

    localparam int ITER  = 16;
    localparam int CNT_W = $clog2(ITER);

    typedef enum logic [1:0] {
        S_IDLE      = 2'b00,
        S_CALCULATE = 2'b01,
        S_DONE      = 2'b10
    } state_t;

    state_t           state_q, state_d;
    logic [CNT_W-1:0] cnt_q,   cnt_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= S_IDLE;
            cnt_q   <= '0;
        end
        else begin
            state_q <= state_d;
            cnt_q   <= cnt_d;
        end
    end

    always_comb begin
        state_d = state_q;
        cnt_d   = cnt_q;

        case (state_q)

            S_IDLE : begin
                cnt_d = '0;
                if (start)
                    state_d = S_CALCULATE;
            end

            S_CALCULATE : begin
                if (cnt_q == ITER-1) begin
                    state_d = S_DONE;
                end
                else begin
                    cnt_d = cnt_q + 1'b1;
                end
            end

            S_DONE : begin
                state_d = S_IDLE;
            end

            default : state_d = S_IDLE;
        endcase
    end

    assign load     = (state_q == S_IDLE) && start;
    assign shift_en = (state_q == S_CALCULATE);
    assign valid    = (state_q == S_DONE);

endmodule 