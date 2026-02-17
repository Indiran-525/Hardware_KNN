module knn_d2s(
    input rst, clk,
    input [7:0] in,
    input x_pulse, y_pulse, mode_pulse,
    output reg[1:0] chosen_class,
    output reg[5:0] cycles
    );

    (* rom_style = "block" *)
    reg[19:0] data_points[0:63];
   
    initial begin
        $readmemh("rom.mem", data_points);
    end
    
    reg x_pulse_reg, y_pulse_reg, mode_pulse_reg;
    reg [7:0]odd_addr, even_addr;
    reg sw;

    reg[17:0] distance_register_odd, distance_register_even;
    wire[7:0] x_coord_odd, y_coord_odd, x_coord_even, y_coord_even;
    wire[1:0] class_odd, class_even;

    reg start_odd, start_even;

    reg[7:0] addr;
    wire[17:0] distance_odd, distance_even;

    wire done_even, done_odd;
    reg valid_in_even, valid_in_odd;

    //wire[7:0] x_in;
    //wire[7:0] y_in;

    //assign x_in = 8'd198;
    //assign y_in = 8'd127;
    
    reg[7:0] x_input, y_input;
    
    reg[19:0] even_data, odd_data;
    reg x_ack, y_ack, mode_ack;
    wire ready;
    assign ready = (x_ack && y_ack && mode_ack);
    always@(posedge clk) begin
        even_data <= data_points[even_addr];
        odd_data <= data_points[odd_addr];
    end
    
    always@(posedge clk) begin
        x_pulse_reg <= x_pulse;
        y_pulse_reg <= y_pulse;
        mode_pulse_reg <= mode_pulse;
    end
    
    always@(posedge clk) begin
    if(rst) begin
        x_ack <= 1'b0;
        y_ack <= 1'b0;
        mode_ack <= 1'b0;
    end
        if(x_pulse_reg) begin x_input <= in; x_ack <= 1'b1; end
        if(y_pulse_reg) begin y_input <= in; y_ack <= 1'b1; end
        if(mode_pulse_reg) begin sw <= in[0]; mode_ack <= 1'b1; end
    end
    
    assign x_coord_odd = odd_data[17:10];
    assign y_coord_odd = odd_data[9:2];
    assign class_odd = odd_data[1:0];
    assign x_coord_even = even_data[17:10];
    assign y_coord_even = even_data[9:2];
    assign class_even = even_data[1:0];
    
    distance_engine_2d DIST_ODD (.clk(clk), .rst(rst), .start(start_odd), .x_in(x_input), .y_in(y_input), 

                            .x_mem(x_coord_odd), .y_mem(y_coord_odd), .dist_out(distance_odd), .done(done_odd));
                            
    distance_engine_2d DIST_EVEN (.clk(clk), .rst(rst), .start(start_even), .x_in(x_input), .y_in(y_input), 

                            .x_mem(x_coord_even), .y_mem(y_coord_even), .dist_out(distance_even), .done(done_even));

    always@(posedge clk) begin
        if(rst || !ready) begin
            even_addr <= 8'b0;
            odd_addr <= 1;
            valid_in_even <= 1'b1;
            valid_in_odd <= 1'b1;
        end
        else begin
            if(done_odd && (odd_addr <= 63)) begin
                odd_addr <= odd_addr + 2;
                distance_register_odd <= distance_odd;
                valid_in_odd <= 1'b1;
            end
            if(odd_addr > 63) valid_in_odd <= 1'b0;
            if(done_even && (even_addr <= 62)) begin
                even_addr <= even_addr + 2;
                distance_register_even <= distance_even;
                valid_in_even <= 1'b1;
            end
            if(even_addr > 62) valid_in_even <= 1'b0;
        end
    end
    
    // --- Wire Declarations for Sorter Outputs ---
    wire finished_odd;
    wire finished_even;
    // --- Sorter Instantiation ---

    // Declare the packed wires to hold the 100-bit results
    wire [99:0] packed_odd;
    wire [99:0] packed_even;

    // --- ODD SORTER INSTANCE ---
    top_k_sorter SORTER_ODD (
        .clk(clk),
        .rst(rst || !ready),
        .valid_in(valid_in_odd),
        
        .new_dist(distance_odd),    
        .new_label(class_odd),     
        
        // NEW: Single Packed Output (100 bits)
        .sorted_list(packed_odd),
        
        .finished(finished_odd)
    );

    // --- EVEN SORTER INSTANCE ---
    top_k_sorter SORTER_EVEN (
        .clk(clk),
        .rst(rst || !ready),
        .valid_in(valid_in_even),
        
        .new_dist(distance_even),   
        .new_label(class_even),    
        
        // NEW: Single Packed Output (100 bits)
        .sorted_list(packed_even),
        
        .finished(finished_even)
    );

    // Wires to hold the final results
    wire [99:0] final_result_packed;
    wire        bubble_done, bubble_start;
    assign bubble_start = finished_even && finished_odd;

    final_merge_sort MERGE_UNIT (
        .clk(clk),
        .rst(rst || !ready),
        
        // Trigger: Start only when BOTH sorters are finished
        .start(bubble_start), 
        
        // Input Data
        .packed_odd(packed_odd),
        .packed_even(packed_even),
        
        // Outputs
        .final_top5(final_result_packed),
        .done(bubble_done)
    );
    
    wire [1:0]  final_winner;       
    wire done_class;
    
    majority_voter VOTER (
        .rst(rst || !ready), .clk(clk),
        // Start Signal: Use the valid flag from the Merge Sorter
        .start(bubble_done), 
        
        // Input: The packed 100-bit list from the Merge Sorter
        .sorted_list(final_result_packed), 
        
        // Mode Switch (K=3 or K=5)
        .mode(sw),
        
        // Outputs
        .predicted_class(final_winner),
        .done(done_class)
    );
    
    always@(posedge clk) begin
        if(rst) chosen_class <= 0;
        else if(done_class)chosen_class <= final_winner;
        else chosen_class <= 0;
    end

    reg[9:0] clock_counter;

    always@(posedge clk) begin
        if(rst || !ready) begin
            clock_counter <= 10'b0;
            cycles <= 0;
        end
        else begin
            if(!done_class) clock_counter <= clock_counter + 1'b1;
            else begin 
            $display("class = %d, clock = %d", final_winner,clock_counter);
            if(done_class) cycles <= clock_counter;
            end
        end
    end
endmodule
