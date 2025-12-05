module main(    
    input CLOCK_50,
    input [2:0] INSTRUCTION,
    input [7:0] DATA_IN,
    input [16:0] MEM_ADDR,
    input SEL_MEM,
    input ENABLE,
    
    output reg [7:0] DATA_OUT,
    output reg FLAG_DONE,
    output reg FLAG_ERROR,
    output FLAG_ZOOM_MAX,
    output FLAG_ZOOM_MIN,
    output [7:0] VGA_R,
    output [7:0] VGA_B, 
    output [7:0] VGA_G,
    output VGA_BLANK_N,
    output VGA_H_SYNC_N, 
    output VGA_V_SYNC_N, 
    output VGA_CLK, 
    output VGA_SYNC
);
    
    wire clk_100, clk_25_vga;
    pll pll0(.refclk(CLOCK_50), .rst(1'b0), .outclk_0(clk_100), .outclk_1(clk_25_vga));

    // Opcodes
    localparam REFRESH_SCREEN = 3'b000;
    localparam LOAD           = 3'b001;
    localparam STORE          = 3'b010;
    localparam NHI_ALG        = 3'b011; // Zoom In (Vizinho)
    localparam PR_ALG         = 3'b100; // Zoom In (Replicação)
    localparam BA_ALG         = 3'b101; // Zoom Out
    localparam NH_ALG         = 3'b110; // Zoom Out
    localparam RESET_INST     = 3'b111;

    // Estados FSM
    localparam IDLE           = 3'b000;
    localparam READ_AND_WRITE = 3'b001;
    localparam ALGORITHM      = 3'b010;
    localparam RESET          = 3'b011;
    localparam COPY_READ      = 3'b100;
    localparam COPY_WRITE     = 3'b101;
    localparam WAIT_WR_OR_RD  = 3'b111;

    reg [2:0] uc_state;
    reg [2:0] last_instruction;

    // Controles de Janela e Mouse
    reg [9:0] cursor_x; reg [8:0] cursor_y;
    reg [9:0] win_start_x; reg [8:0] win_start_y;
    reg [9:0] win_end_x; reg [8:0] win_end_y;
    reg window_active;
    reg [16:0] zoom_x_offset; reg [7:0] zoom_y_offset;

    reg enable_ff;
    wire enable_pulse;
    always @(posedge clk_100) enable_ff <= !ENABLE;
    assign enable_pulse = !ENABLE && !enable_ff;

    //================================================================
    // 2. Memórias
    //================================================================
    reg [16:0] addr_mem2, addr_mem3;
    wire [16:0] addr_mem1;
    reg [7:0] data_in_mem1, data_in_mem2;
    reg wren_mem1, wren_mem2, wren_mem3;
    wire [7:0] data_out_mem1, data_out_mem2, data_out_mem3;
    
    mem1 memory1(.rdaddress(addr_mem1), .wraddress(addr_wr_mem1), .clock(clk_100), .data(data_in_mem1), .wren(wren_mem1), .q(data_out_mem1));
    mem1 memory2(.rdaddress(addr_mem2), .wraddress(addr_wr_mem2), .clock(clk_100), .data(data_in_mem2), .wren(wren_mem2), .q(data_out_mem2));
    mem1 memory3(.rdaddress(addr_mem3), .wraddress(addr_for_write), .clock(clk_100), .data(data_to_write), .wren(wren_mem3), .q(data_out_mem3));

    assign addr_mem1 = (uc_state != ALGORITHM && uc_state != WAIT_WR_OR_RD && uc_state != READ_AND_WRITE) ? addr_for_copy : addr_for_read;

    //================================================================
    // 3. VGA com Overlay
    //================================================================
    localparam X_START=159, Y_START=119, X_END=X_START+320, Y_END=Y_START+240;
    wire [9:0] next_x, next_y;
    reg [16:0] addr_from_vga;
    reg inside_box;
    
    wire is_cursor = ((next_x == cursor_x + X_START) && (next_y >= cursor_y + Y_START - 2 && next_y <= cursor_y + Y_START + 2)) ||
                     ((next_y == cursor_y + Y_START) && (next_x >= cursor_x + X_START - 2 && next_x <= cursor_x + X_START + 2));
    
    wire [9:0] rel_x = (next_x >= X_START) ? (next_x - X_START) : 10'd0;
    wire [9:0] rel_y = (next_y >= Y_START) ? (next_y - Y_START) : 10'd0;
    wire is_window_area = (window_active && rel_x >= win_start_x && rel_x <= win_end_x && rel_y >= win_start_y && rel_y <= win_end_y);

    always @(posedge clk_25_vga) begin
        if (next_x >= X_START && next_x < X_END && next_y >= Y_START && next_y < Y_END) begin
            inside_box <= 1'b1;
            addr_from_vga <= ((next_y - Y_START) * 32'd320) + (next_x - X_START);
        end else begin
            inside_box <= 1'b0;
            addr_from_vga <= 17'd0;
        end
    end
    
    reg [7:0] data_to_vga_pipe;
    always @(posedge clk_100) begin
        if (inside_box) begin
            if (is_cursor) data_to_vga_pipe <= 8'b11100000; // Vermelho
            else if (is_window_area) data_to_vga_pipe <= data_out_mem2;
            else data_to_vga_pipe <= data_out_mem1;
        end else data_to_vga_pipe <= 8'b0;
    end 

    //================================================================
    // 4. Controle e Algoritmo
    //================================================================
    reg [1:0] counter_rd_wr;
    reg [16:0] counter_address;
    reg [2:0] next_zoom, current_zoom;
    reg has_alg_on_exec;
    reg [16:0] addr_wr_mem2, addr_wr_mem1;
    reg [9:0] new_x, new_y, old_x, old_y;
    reg [16:0] addr_for_read, addr_for_write;
    reg [7:0] data_to_write;
    reg [3:0] op_step;
    reg [31:0] data_to_avg;

    // Contadores para Replicação de Pixel
    reg [2:0] pr_cnt_x;
    reg [2:0] pr_cnt_y;

    assign FLAG_ZOOM_MAX = (current_zoom == 3'b111);
    assign FLAG_ZOOM_MIN = (current_zoom == 3'b001);

    // Calculos Auxiliares
    wire [2:0] shift_val = (next_zoom > 3'b000) ? (next_zoom - 1'b1) : 3'd0;    
    wire [2:0] zoom_limit_cnt = (1'b1 << (next_zoom - 1'b1)) - 1'b1;

    //================================================================
    // 5. FSM
    //================================================================
    always @(posedge clk_100) begin
        case (uc_state) 
            IDLE: begin 
                has_alg_on_exec <= 0; FLAG_DONE <= 1;
                wren_mem1 <= 0; wren_mem2 <= 0; wren_mem3 <= 0;

                if (enable_pulse) begin
                    counter_address <= 0; counter_rd_wr <= 0;
                    
                    if (INSTRUCTION == REFRESH_SCREEN && SEL_MEM == 1) begin
                        // Configuração Janela/Mouse
                        case (MEM_ADDR[16:15])
                            2'b00: begin cursor_x <= MEM_ADDR[9:0]; cursor_y <= DATA_IN[7:0]; end
                            2'b01: begin win_start_x <= MEM_ADDR[9:0]; win_start_y <= DATA_IN[7:0]; end
                            2'b10: begin win_end_x <= MEM_ADDR[9:0]; win_end_y <= DATA_IN[7:0]; end
                            2'b11: begin window_active <= DATA_IN[0]; end
                        endcase
                        FLAG_DONE <= 1; uc_state <= IDLE;
                    end 
                    else if (INSTRUCTION == LOAD || INSTRUCTION == STORE) begin
                        uc_state <= READ_AND_WRITE; last_instruction <= INSTRUCTION;
                    end 
                    else if (INSTRUCTION >= NHI_ALG && INSTRUCTION <= NH_ALG) begin
                        zoom_x_offset <= MEM_ADDR; zoom_y_offset <= DATA_IN;
                        if (INSTRUCTION == REFRESH_SCREEN) begin
                             last_instruction <= RESET_INST; uc_state <= COPY_READ;
                        end else begin
                            case (INSTRUCTION)
                                NH_ALG: begin // Zoom Out
                                    if (FLAG_ZOOM_MIN) begin FLAG_DONE <= 1; uc_state <= IDLE; end
                                    else begin next_zoom <= current_zoom - 1; last_instruction <= NHI_ALG; uc_state <= ALGORITHM; end
                                end
                                BA_ALG: begin // Zoom Out
                                    if (FLAG_ZOOM_MIN) begin FLAG_DONE <= 1; uc_state <= IDLE; end
                                    else begin next_zoom <= current_zoom - 1; last_instruction <= PR_ALG; uc_state <= ALGORITHM; end
                                end
                                NHI_ALG, PR_ALG: begin 
                                    if (FLAG_ZOOM_MAX && !SEL_MEM) begin FLAG_DONE <= 1; uc_state <= IDLE; end
                                    else begin 
                                        if (SEL_MEM) next_zoom <= current_zoom; 
                                        else next_zoom <= current_zoom + 1;  
                                        last_instruction <= INSTRUCTION; uc_state <= ALGORITHM; 
                                    end
                                end
                            endcase
                        end
                    end 
                    else if (INSTRUCTION == RESET_INST) begin
                        last_instruction <= RESET_INST; uc_state <= RESET;
                        win_start_x <= 0; win_start_y <= 0; win_end_x <= 319; win_end_y <= 239;
                        window_active <= 0; cursor_x <= 0; cursor_y <= 0;
                    end
                end
            end
            
            READ_AND_WRITE: begin
                if (MEM_ADDR > 76799) FLAG_ERROR <= 1;
                FLAG_DONE <= 0;
                if (last_instruction == STORE) begin
                    addr_wr_mem1 <= MEM_ADDR; data_in_mem1 <= DATA_IN; wren_mem1 <= 1;
                    uc_state <= WAIT_WR_OR_RD; counter_rd_wr <= 0;
                end else begin
                    if (SEL_MEM) begin counter_address <= MEM_ADDR; wren_mem3 <= 0; end 
                    else begin addr_for_read <= MEM_ADDR; wren_mem1 <= 0; end
                    uc_state <= WAIT_WR_OR_RD; counter_rd_wr <= 0;
                end
            end

            ALGORITHM: begin
                wren_mem1 <= 0; FLAG_DONE <= 0;
                
                case (last_instruction)                    
                    //REPLICAÇÃO DE PIXEL                    
                    PR_ALG: begin
                        if (!has_alg_on_exec) begin
                            has_alg_on_exec <= 1; op_step <= 0;
                            new_x <= win_start_x; new_y <= win_start_y;
                            old_x <= zoom_x_offset; old_y <= zoom_y_offset;
                            pr_cnt_x <= 0; pr_cnt_y <= 0; // Inicializa contadores
                        end else begin
                            if (op_step == 0) begin 
                                // Leitura (Endereço 32 bits seguro)
                                addr_for_read <= {7'd0, old_x} + ({7'd0, old_y} * 32'd320);
                                counter_rd_wr <= 0; op_step <= 1; uc_state <= WAIT_WR_OR_RD;
                            end else if (op_step == 1) begin 
                                // Escrita
                                data_in_mem2 <= data_out_mem1;
                                addr_wr_mem2 <= {7'd0, new_x} + ({7'd0, new_y} * 32'd320); 
                                wren_mem2 <= 1; op_step <= 0; uc_state <= WAIT_WR_OR_RD;
                                
                                // --- Lógica de Replicação ---
                                if (new_x >= win_end_x) begin 
                                    // Fim da Linha da Janela
                                    new_x <= win_start_x; 
                                    new_y <= new_y + 1;
                                    pr_cnt_x <= 0; 
                                    old_x <= zoom_x_offset;

                                    if (new_y >= win_end_y) begin 
                                        // Fim da Janela
                                        current_zoom <= next_zoom; FLAG_DONE <= 1; uc_state <= IDLE;
                                    end else begin                                    
                                        if (pr_cnt_y < zoom_limit_cnt) begin
                                            pr_cnt_y <= pr_cnt_y + 1;                                            
                                        end else begin
                                            pr_cnt_y <= 0;
                                            old_y <= old_y + 1; // Próxima linha original
                                        end
                                    end
                                end else begin
                                    // Meio da Linha
                                    new_x <= new_x + 1;
                                    // Avanço Horizontal com Repetição
                                    if (pr_cnt_x < zoom_limit_cnt) begin
                                        pr_cnt_x <= pr_cnt_x + 1;
                                        // Não incrementa old_x (Repete o pixel)
                                    end else begin
                                        pr_cnt_x <= 0;
                                        old_x <= old_x + 1; // Próximo pixel original
                                    end
                                end
                            end
                        end
                    end
                    
                    // NHI_ALG: VIZINHO MAIS PRÓXIMO                    
                    NHI_ALG: begin
                        if (!has_alg_on_exec) begin
                            has_alg_on_exec <= 1; op_step <= 0;
                            new_x <= win_start_x; new_y <= win_start_y;
                            old_x <= zoom_x_offset; old_y <= zoom_y_offset;
                        end else begin
                            if (op_step == 0) begin 
                                addr_for_read <= {7'd0, old_x} + ({7'd0, old_y} * 32'd320);
                                counter_rd_wr <= 0; op_step <= 1; uc_state <= WAIT_WR_OR_RD;
                            end else begin 
                                data_in_mem2 <= data_out_mem1;
                                addr_wr_mem2 <= {7'd0, new_x} + ({7'd0, new_y} * 32'd320);
                                wren_mem2 <= 1; op_step <= 0; uc_state <= WAIT_WR_OR_RD;
                                
                                if (new_x >= win_end_x) begin
                                    new_x <= win_start_x; new_y <= new_y + 1;
                                    if (new_y >= win_end_y) begin current_zoom <= next_zoom; FLAG_DONE <= 1; uc_state <= IDLE; end
                                    else begin 
                                        // Cálculo Inverso (Divisão por 2^N)
                                        old_y <= zoom_y_offset + ((new_y + 1'b1 - win_start_y) >> shift_val);
                                        old_x <= zoom_x_offset; 
                                    end
                                end else begin
                                    new_x <= new_x + 1;
                                    // Cálculo Inverso (Divisão por 2^N)
                                    old_x <= zoom_x_offset + ((new_x + 1'b1 - win_start_x) >> shift_val);
                                end
                            end
                        end
                    end

                    default: uc_state <= IDLE;
                endcase
            end

            RESET: begin
                FLAG_DONE <= 0; next_zoom <= 1; current_zoom <= 1; last_instruction <= RESET_INST;
                counter_address <= 0; counter_rd_wr <= 0; uc_state <= COPY_READ;
                win_start_x <= 0; win_start_y <= 0; win_end_x <= 319; win_end_y <= 239; window_active <= 0;
                cursor_x <= 0; cursor_y <= 0;
            end

            COPY_READ: begin
                if(counter_rd_wr == 2) begin wren_mem2 <= 0; counter_rd_wr <= 0; uc_state <= COPY_WRITE; end else counter_rd_wr <= counter_rd_wr + 1;
            end
            COPY_WRITE: begin
                data_in_mem2 <= data_out_mem1; addr_wr_mem2 <= counter_address; wren_mem2 <= 1;
                if (counter_rd_wr == 2) begin
                    counter_rd_wr <= 0; if (counter_address >= 76799) begin FLAG_DONE <= 1; uc_state <= IDLE; end else begin counter_address <= counter_address + 1; uc_state <= COPY_READ; end
                end else counter_rd_wr <= counter_rd_wr + 1;
            end
            WAIT_WR_OR_RD: begin
                if (counter_rd_wr == 2) begin
                    counter_rd_wr <= 0;
                    if (last_instruction == LOAD) begin uc_state <= IDLE; DATA_OUT <= data_out_mem1; FLAG_DONE <= 1; end
                    else if (last_instruction == STORE) begin uc_state <= IDLE; wren_mem1 <= 0; counter_address <= 0; FLAG_DONE <= 1; end
                    else begin wren_mem2 <= 0; uc_state <= ALGORITHM; end
                end else counter_rd_wr <= counter_rd_wr + 1;
            end
            default: uc_state <= IDLE;
        endcase
    end

    reg [16:0] addr_for_copy;
    always @(*) begin
        if (uc_state == COPY_READ || uc_state == COPY_WRITE) addr_for_copy <= counter_address;
        else begin
            addr_mem2 <= addr_from_vga; 
             if (uc_state != ALGORITHM && uc_state != WAIT_WR_OR_RD && uc_state != READ_AND_WRITE) addr_for_copy <= addr_from_vga;
             else addr_for_copy <= counter_address;
        end
    end

    vga_module vga_out(.clock(clk_25_vga), .reset(1'b0), .color_in(data_to_vga_pipe), .next_x(next_x), .next_y(next_y), .hsync(VGA_H_SYNC_N), .vsync(VGA_V_SYNC_N), .red(VGA_R), .green(VGA_G), .blue(VGA_B), .sync(VGA_SYNC), .clk(VGA_CLK), .blank(VGA_BLANK_N));
endmodule