module REG_FILE (
    input                   [ 0 : 0]        clk,

    input                   [ 4 : 0]        rf_ra0,
    input                   [ 4 : 0]        rf_ra1,   
    input                   [ 4 : 0]        rf_wa,
    input                   [ 0 : 0]        rf_we,
    input                   [31 : 0]        rf_wd,

    output        reg          [31 : 0]        rf_rd0,
    output        reg          [31 : 0]        rf_rd1,
    input      [4:0] dbg_reg_ra,
    output reg [31:0] dbg_reg_rd
);

    reg [31 : 0] reg_file [0 : 31];

    // 用于初始化寄存器
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            reg_file[i] = 0;
    end

    always @(posedge clk) begin
        if(rf_we&&rf_wa!=0)begin
            reg_file[rf_wa] <= rf_wd;
        end 
        else begin
           reg_file[rf_wa] <= reg_file[rf_wa]; 
        end
    end

    always @(*) begin
        rf_rd0      =   (rf_wa==rf_ra0&&rf_wa!=0)?           rf_wd:reg_file[rf_ra0];
        rf_rd1      =   (rf_wa==rf_ra1&&rf_wa!=0)?           rf_wd:reg_file[rf_ra1];
        dbg_reg_rd  =    reg_file[dbg_reg_ra];
    end

endmodule