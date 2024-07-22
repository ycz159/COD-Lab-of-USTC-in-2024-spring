`define ADD                 5'B00000    
`define SUB                 5'B00010   
`define SLT                 5'B00100
`define SLTU                5'B00101
`define AND                 5'B01001
`define OR                  5'B01010
`define XOR                 5'B01011
`define SLL                 5'B01110   
`define SRL                 5'B01111    
`define SRA                 5'B10000  
`define SRC0                5'B10001
`define SRC1                5'B10010
//new
`define jal     4'b1001
`define jalr    4'b1010

`define beq     4'b1000
`define bne     4'b0001
`define blt     4'b0100
`define bge     4'b0101
`define bltu    4'b0110
`define bgeu    4'b0111

`define I_beq     3'b000
`define I_bne     3'b001
`define I_blt     3'b100
`define I_bge     3'b101
`define I_bltu    3'b110
`define I_bgeu    3'b111


`define lb  4'b0000
`define lbu 4'b0001
`define lh  4'b0010
`define lhu 4'b0011
`define lw  4'b0100
`define sb  4'b1000
`define sh  4'b1010
`define sw  4'b1100


module CPU (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,

    input                   [ 0 : 0]            global_en,

/* ------------------------------ Memory (inst) ----------------------------- */
    output                  [31 : 0]            imem_raddr,
    input                   [31 : 0]            imem_rdata,

/* ------------------------------ Memory (data) ----------------------------- */
    input                   [31 : 0]            dmem_rdata,
    output                  [ 0 : 0]            dmem_we,
    output                  [31 : 0]            dmem_addr,
    output                  [31 : 0]            dmem_wdata,

/* ---------------------------------- Debug --------------------------------- */
    output                  [ 0 : 0]            commit,
    output                  [31 : 0]            commit_pc,
    output                  [31 : 0]            commit_inst,
    output                  [ 0 : 0]            commit_halt,
    output                  [ 0 : 0]            commit_reg_we,
    output                  [ 4 : 0]            commit_reg_wa,
    output                  [31 : 0]            commit_reg_wd,
    output                  [ 0 : 0]            commit_dmem_we,
    output                  [31 : 0]            commit_dmem_wa,
    output                  [31 : 0]            commit_dmem_wd,

    input                   [ 4 : 0]            debug_reg_ra,   // TODO
    output                  [31 : 0]            debug_reg_rd    // TODO
);

//IF
assign dmem_we=global_en;
wire [31:0] pc_out_IF,npc;
PC pc(
    .clk(clk),
    .rst(rst),
    .en(global_en),
    .npc(npc),
    .pc_out(pc_out_IF)
);
assign imem_raddr=pc_out_IF;

wire [31:0] alu_res_EX;
wire [1:0] npc_sel_EX;
NPC_MUX npc_mux(
    .npc_sel(npc_sel_EX),
    .pc_add4(pc_out_IF+4),
    .pc_offset(alu_res_EX),
    .pc_j(alu_res_EX&32'hfffffffe),
    .npc(npc)
);

wire [0:0] flush_IFID,stall_IFID,commit_ID;
wire [31:0] pc_out_ID,pc_out_add4_ID,inst_ID;
Interval_Reg intereg_IFID(
    .rst(rst),
    .en(global_en),
    .flush(1'b0),
    .stall(1'b0),
    .clk(clk),

    .i_pc_out(pc_out_IF),
    .i_pc_out_add4(pc_out_IF+4),
    .i_inst(imem_rdata),

    .i_alu_op(5'b00000),
    .i_dmem_access(4'hf),
    .i_imm(32'h00000000),
    .i_rf_wa(5'b00000),
    .i_rf_we(1'b0),
    .i_rf_wd_sel(2'b00),
    .i_alu_src0_sel(1'b0),
    .i_alu_src1_sel(1'b0),
    .i_br_type(4'hf),

    .i_rf_rd0(32'h00000000),
    .i_rf_rd1(32'h00000000),
    .i_dbg_reg_ra(5'b00000),
    .i_dbg_reg_rd(32'h00000000),

    .i_alu_res(32'h00000000),
    .i_dmem_rd_out(32'h00000000),
    .i_commit(global_en),

    .o_pc_out(pc_out_ID),
    .o_pc_out_add4(pc_out_add4_ID),
    .o_inst(inst_ID),
    .o_commit(commit_ID)
);

//ID
wire [4:0] alu_op_ID,rf_ra0,rf_ra1,rf_wa_ID;
wire [31 : 0] imm_ID;
wire [0:0] rf_we_ID,alu_src0_sel_ID,alu_src1_sel_ID;
wire [3:0] dmem_access_ID,br_type_ID;
wire [1:0] rf_wd_sel_ID;
DECODER decoder(
    .inst(inst_ID),
    .alu_op(alu_op_ID),
    .dmem_access(dmem_access_ID),
    .imm(imm_ID),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa_ID),
    .rf_we(rf_we_ID),
    .rf_wd_sel(rf_wd_sel_ID),
    .alu_src0_sel(alu_src0_sel_ID),
    .alu_src1_sel(alu_src1_sel_ID),
    .br_type(br_type_ID)
);

wire [31:0] rf_wd_mux_outdata_WB,rf_rd0_ID,rf_rd1_ID;
wire [0:0]  rf_we_WB;
wire [4:0]  rf_wa_WB;
REG_FILE reg_file(
    .clk(clk),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa_WB),
    .rf_we(rf_we_WB),
    .rf_wd(rf_wd_mux_outdata_WB),
    .rf_rd0(rf_rd0_ID),
    .rf_rd1(rf_rd1_ID),
    .dbg_reg_ra(debug_reg_ra),
    .dbg_reg_rd(debug_reg_rd)
);

wire [31:0] pc_out_EX,pc_out_add4_EX,imm_EX,rf_rd0_EX,rf_rd1_EX,dbg_reg_rd_EX,inst_EX;
wire [4:0]  alu_op_EX,rf_wa_EX;
wire [3:0]  dmem_access_EX,br_type_EX;
wire [1:0]  rf_wd_sel_EX;
wire [0:0]  rf_we_EX,alu_src0_sel_EX,alu_src1_sel_EX,commit_EX;
Interval_Reg intereg_IDEX(
    .rst(rst),
    .en(global_en),
    .flush(1'b0),
    .stall(1'b0),
    .clk(clk),

    .i_pc_out(pc_out_ID),
    .i_pc_out_add4(pc_out_add4_ID),
    .i_inst(inst_ID),

    .i_alu_op(alu_op_ID),
    .i_dmem_access(dmem_access_ID),
    .i_imm(imm_ID),
    .i_rf_wa(rf_wa_ID),
    .i_rf_we(rf_we_ID),
    .i_rf_wd_sel(rf_wd_sel_ID),
    .i_alu_src0_sel(alu_src0_sel_ID),
    .i_alu_src1_sel(alu_src1_sel_ID),
    .i_br_type(br_type_ID),

    .i_rf_rd0(rf_rd0_ID),
    .i_rf_rd1(rf_rd1_ID),
    .i_dbg_reg_ra(5'b00000),
    .i_dbg_reg_rd(32'b00000000),

    .i_alu_res(32'h00000000),
    .i_dmem_rd_out(32'h00000000),
    .i_commit(commit_ID),

    .o_pc_out(pc_out_EX),
    .o_pc_out_add4(pc_out_add4_EX),

    .o_alu_op(alu_op_EX),
    .o_dmem_access(dmem_access_EX),
    .o_inst(inst_EX),
    .o_imm(imm_EX),
    .o_rf_wa(rf_wa_EX),
    .o_rf_we(rf_we_EX),
    .o_rf_wd_sel(rf_wd_sel_EX),
    .o_alu_src0_sel(alu_src0_sel_EX),
    .o_alu_src1_sel(alu_src1_sel_EX),
    .o_br_type(br_type_EX),

    .o_rf_rd0(rf_rd0_EX),
    .o_rf_rd1(rf_rd1_EX),
    .o_dbg_reg_rd(dbg_reg_rd_EX),
    .o_commit(commit_EX)
);

//EX
wire [31:0] alu_src0,alu_src1;
MUX2 mux0(
    .src0(pc_out_EX),
    .src1(rf_rd0_EX),
    .sel(alu_src0_sel_EX),
    .res(alu_src0)
);
MUX2 mux1(
    .src0(rf_rd1_EX),
    .src1(imm_EX),
    .sel(alu_src1_sel_EX),
    .res(alu_src1)
);

BRANCH branch(
    .br_type(br_type_EX),
    .br_src0(rf_rd0_EX),
    .br_src1(rf_rd1_EX),
    .npc_sel(npc_sel_EX)
);

ALU alu(
    .alu_op(alu_op_EX),
    .alu_src0(alu_src0),
    .alu_src1(alu_src1),
    .alu_res(alu_res_EX)
);

wire [31:0] alu_res_MEM,pc_out_MEM,pc_out_add4_MEM,rf_rd1_MEM,inst_MEM;
wire [4:0]  rf_wa_MEM;
wire [3:0]  dmem_access_MEM;
wire [1:0]  rf_wd_sel_MEM;
wire [0:0]  rf_we_MEM,commit_MEM;
Interval_Reg intereg_EXMEM(
    .rst(rst),
    .en(global_en),
    .flush(1'b0),
    .stall(1'b0),
    .clk(clk),

    .i_pc_out(pc_out_EX),
    .i_pc_out_add4(pc_out_add4_EX),
    .i_inst(inst_EX),

    .i_alu_op(5'b00000),
    .i_dmem_access(dmem_access_EX),
    .i_imm(32'h00000000),
    .i_rf_wa(rf_wa_EX),
    .i_rf_we(rf_we_EX),
    .i_rf_wd_sel(rf_wd_sel_EX),
    .i_alu_src0_sel(1'b0),
    .i_alu_src1_sel(1'b0),
    .i_br_type(4'hf),

    .i_rf_rd0(32'h00000000),
    .i_rf_rd1(rf_rd1_EX),
    .i_dbg_reg_ra(5'b00000),
    .i_dbg_reg_rd(32'h00000000),

    .i_alu_res(alu_res_EX),
    .i_dmem_rd_out(32'h00000000),
    .i_commit(commit_EX),

    .o_pc_out(pc_out_MEM),
    .o_pc_out_add4(pc_out_add4_MEM),
    .o_inst(inst_MEM),

    .o_dmem_access(dmem_access_MEM),
    .o_rf_wa(rf_wa_MEM),
    .o_rf_we(rf_we_MEM),
    .o_rf_wd_sel(rf_wd_sel_MEM),
    .o_rf_rd1(rf_rd1_MEM),
    .o_alu_res(alu_res_MEM),
    .o_commit(commit_MEM)
);

//MEM
wire [31:0] dmem_wdata_slu,dmem_rd_out_MEM;
SLU slu(
    .addr(alu_res_MEM),
    .dmem_access(dmem_access_MEM),
    .rd_in(dmem_rdata),
    .rd_out(dmem_rd_out_MEM),
    .wd_in(rf_rd1_MEM),
    .wd_out(dmem_wdata_slu)
);
assign dmem_wdata=dmem_wdata_slu;
assign dmem_addr=alu_res_MEM;

wire [31:0] alu_res_WB,pc_out_WB,pc_out_add4_WB,inst_WB,dmem_rd_out_WB,dmem_addr_WB,dmem_wdata_WB;
wire [1:0]  rf_wd_sel_WB;
wire [0:0]  commit_WB;
Interval_Reg intereg_MEMWB(
    .rst(rst),
    .en(global_en),
    .flush(1'b0),
    .stall(1'b0),
    .clk(clk),

    .i_pc_out(pc_out_MEM),
    .i_pc_out_add4(pc_out_add4_MEM),
    .i_inst(inst_MEM),

    .i_alu_op(5'b00000),
    .i_dmem_access(4'hf),
    .i_imm(32'h00000000),
    .i_rf_wa(rf_wa_MEM),
    .i_rf_we(rf_we_MEM),
    .i_rf_wd_sel(rf_wd_sel_MEM),
    .i_alu_src0_sel(1'b0),
    .i_alu_src1_sel(1'b0),
    .i_br_type(4'hf),

    .i_rf_rd0(dmem_wdata_slu),//借用
    .i_rf_rd1(32'h00000000),
    .i_dbg_reg_ra(5'b00000),
    .i_dbg_reg_rd(32'h00000000),

    .i_alu_res(alu_res_MEM),
    .i_dmem_rd_out(dmem_rd_out_MEM),
    .i_commit(commit_MEM),

    .o_pc_out(pc_out_WB),
    .o_pc_out_add4(pc_out_add4_WB),
    .o_inst(inst_WB),

    .o_rf_rd0(dmem_wdata_WB),//借用

    .o_rf_wa(rf_wa_WB),
    .o_rf_we(rf_we_WB),
    .o_rf_wd_sel(rf_wd_sel_WB),
    .o_alu_res(alu_res_WB),
    .o_dmem_rd_out(dmem_rd_out_WB),
    .o_commit(commit_WB)
);

//WB
MUX4 rf_wd_mux(
    .src0(pc_out_add4_WB),
    .src1(alu_res_WB),
    .src2(dmem_rd_out_WB),
    .src3(32'h00000000),
    .sel(rf_wd_sel_WB),
    .res(rf_wd_mux_outdata_WB)
);



    // Commit
    reg  [ 0 : 0]   commit_reg          ;
    reg  [31 : 0]   commit_pc_reg       ;
    reg  [31 : 0]   commit_inst_reg     ;
    reg  [ 0 : 0]   commit_halt_reg     ;
    reg  [ 0 : 0]   commit_reg_we_reg   ;
    reg  [ 4 : 0]   commit_reg_wa_reg   ;
    reg  [31 : 0]   commit_reg_wd_reg   ;
    reg  [ 0 : 0]   commit_dmem_we_reg  ;
    reg  [31 : 0]   commit_dmem_wa_reg  ;
    reg  [31 : 0]   commit_dmem_wd_reg  ;

    // Commit
    always @(posedge clk) begin
        if (rst) begin
            commit_reg          <= 1'B0;
            commit_pc_reg       <= 32'H0;
            commit_inst_reg     <= 32'H0;
            commit_halt_reg     <= 1'B0;
            commit_reg_we_reg   <= 1'B0;
            commit_reg_wa_reg   <= 5'H0;
            commit_reg_wd_reg   <= 32'H0;
            commit_dmem_we_reg  <= 1'B0;
            commit_dmem_wa_reg  <= 32'H0;
            commit_dmem_wd_reg  <= 32'H0;
        end
        else if (global_en) begin
            commit_reg          <= commit_WB;
            commit_pc_reg       <= pc_out_WB;   // TODO
            commit_inst_reg     <= inst_WB;   // TODO
            commit_halt_reg     <= inst_WB==32'h00100073;   // TODO
            commit_reg_we_reg   <= rf_we_WB;   // TODO
            commit_reg_wa_reg   <= rf_wa_WB;   // TODO
            commit_reg_wd_reg   <= rf_wd_mux_outdata_WB;   // TODO
            commit_dmem_we_reg  <= global_en;   // TODO
            commit_dmem_wa_reg  <= alu_res_WB;   // TODO
            commit_dmem_wd_reg  <= dmem_wdata_WB;   // TODO
        end
    end

    assign commit           = commit_reg;
    assign commit_pc        = commit_pc_reg;
    assign commit_inst      = commit_inst_reg;
    assign commit_halt      = commit_halt_reg;
    assign commit_reg_we    = commit_reg_we_reg;
    assign commit_reg_wa    = commit_reg_wa_reg;
    assign commit_reg_wd    = commit_reg_wd_reg;
    assign commit_dmem_we   = commit_dmem_we_reg;
    assign commit_dmem_wa   = commit_dmem_wa_reg;
    assign commit_dmem_wd   = commit_dmem_wd_reg;

endmodule


module PC (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [ 0 : 0]            en,
    input                   [31 : 0]            npc,

    output                  [31 : 0]            pc_out
);
reg [31:0] pc;
always @(posedge clk) begin
    if(rst)
        pc<=32'h00400000;
    else if(en)
        pc<=npc;
end

assign pc_out=pc;

endmodule






module Interval_Reg (
    input                  [ 0 : 0]            rst,
    input                  [ 0 : 0]            en,
    input                  [ 0 : 0]            flush,
    input                  [ 0 : 0]            stall,
    input                  [ 0 : 0]            clk,
    //pc
    input                  [31 : 0]            i_pc_out,
    input                  [31 : 0]            i_pc_out_add4,
    input                  [31 : 0]            i_inst,
    //decoder
    input                  [ 4 : 0]            i_alu_op,
    input                  [ 3 : 0]            i_dmem_access,
    input                  [31 : 0]            i_imm,
    input                  [ 4 : 0]            i_rf_wa,
    input                  [ 0 : 0]            i_rf_we,
    input                  [ 1 : 0]            i_rf_wd_sel,
    input                  [ 0 : 0]            i_alu_src0_sel,
    input                  [ 0 : 0]            i_alu_src1_sel,
    input                  [ 3 : 0]            i_br_type,
    //RegFile
    input                   [31 : 0]           i_rf_rd0,
    input                   [31 : 0]           i_rf_rd1,
    input                   [ 4 : 0]           i_dbg_reg_ra,
    input                   [31 : 0]           i_dbg_reg_rd,
    //ALU
    input                   [31 : 0]           i_alu_res,
    //SLU
    input                   [31 : 0]           i_dmem_rd_out,
    //commit
    input                   [ 0 : 0]           i_commit,



    output                  [31 : 0]           o_pc_out,
    output                  [31 : 0]           o_pc_out_add4,
    output                  [31 : 0]           o_inst,
    //decoder
    output                  [ 4 : 0]           o_alu_op,
    output                  [ 3 : 0]           o_dmem_access,
    output                  [31 : 0]           o_imm,
    output                  [ 4 : 0]           o_rf_wa,
    output                  [ 0 : 0]           o_rf_we,
    output                  [ 1 : 0]           o_rf_wd_sel,
    output                  [ 0 : 0]           o_alu_src0_sel,
    output                  [ 0 : 0]           o_alu_src1_sel,
    output                  [ 3 : 0]           o_br_type,
    //RegFile
    output                   [31 : 0]          o_rf_rd0,
    output                   [31 : 0]          o_rf_rd1,
    output                   [ 4 : 0]          o_dbg_reg_ra,
    output                   [31 : 0]          o_dbg_reg_rd,
    //ALU
    output                   [31 : 0]          o_alu_res,
    //SLU
    output                   [31 : 0]          o_dmem_rd_out,
    //commit
    output                   [ 0 : 0]          o_commit
);

    reg                  [31 : 0]            pc_out;
    reg                  [31 : 0]            pc_out_add4;
    reg                  [31 : 0]            inst;
    //decoder
    reg                  [ 4 : 0]            alu_op;
    reg                  [ 3 : 0]            dmem_access;
    reg                  [31 : 0]            imm;
    reg                  [ 4 : 0]            rf_wa;
    reg                  [ 0 : 0]            rf_we;
    reg                  [ 1 : 0]            rf_wd_sel;
    reg                  [ 0 : 0]            alu_src0_sel;
    reg                  [ 0 : 0]            alu_src1_sel;
    reg                  [ 3 : 0]            br_type;
    //RegFile
    reg                   [31 : 0]           rf_rd0;
    reg                   [31 : 0]           rf_rd1;
    reg                   [ 4 : 0]           dbg_reg_ra;
    reg                   [31 : 0]           dbg_reg_rd;
    //ALU
    reg                   [31 : 0]           alu_res;
    //SLU
    reg                   [31 : 0]           dmem_rd_out;
    //commit
    reg                   [ 0 : 0]           commit;

    assign o_pc_out=pc_out;
    assign o_pc_out_add4=pc_out_add4;
    assign o_inst=inst;

    assign o_alu_op=alu_op;
    assign o_dmem_access=dmem_access;
    assign o_imm=imm;
    assign o_rf_wa=rf_wa;
    assign o_rf_we=rf_we;
    assign o_rf_wd_sel=rf_wd_sel;
    assign o_alu_src0_sel=alu_src0_sel;
    assign o_alu_src1_sel=alu_src1_sel;
    assign o_br_type=br_type;

    assign o_rf_rd0=rf_rd0;
    assign o_rf_rd1=rf_rd1;
    assign o_dbg_reg_ra=dbg_reg_ra;
    assign o_dbg_reg_rd=dbg_reg_rd;

    assign o_alu_res=alu_res;
    assign o_dmem_rd_out=dmem_rd_out;

    assign o_commit=commit;

always @(posedge clk) begin
    if (rst) begin
        // rst 操作的逻辑
        pc_out<=32'h00000000;
        pc_out_add4<=32'h00000000;
        inst<=32'h00000000;
        //decoder
        alu_op<=5'b00000;
        dmem_access<=4'hf;
        imm<=32'h00000000;
        rf_wa<=5'b00000;
        rf_we<=1'b0;
        rf_wd_sel<=2'b00;
        alu_src0_sel<=1'b0;
        alu_src1_sel<=1'b0;
        br_type<=4'b0000;
        //RegFile
        rf_rd0<=32'h00000000;
        rf_rd1<=32'h00000000;
        dbg_reg_ra<=5'b00000;
        dbg_reg_rd<=32'h00000000;
        //ALU
        alu_res<=5'b00000;
        //SLU
        dmem_rd_out<=32'h00000000;
        //commit
        commit<=1'b0;
    end
    else if (en) begin
        // flush 和 stall 操作的逻辑, flush 的优先级更高
        if(flush)begin
            pc_out<=32'h00000000;
            pc_out_add4<=32'h00000000;
            inst<=32'h00000000;
            //decoder
            alu_op<=5'b00000;
            dmem_access<=4'hf;
            imm<=32'h00000000;
            rf_wa<=5'b00000;
            rf_we<=1'b0;
            rf_wd_sel<=2'b00;
            alu_src0_sel<=1'b0;
            alu_src1_sel<=1'b0;
            br_type<=4'b0000;
            //RegFile
            rf_rd0<=32'h00000000;
            rf_rd1<=32'h00000000;
            dbg_reg_ra<=5'b00000;
            dbg_reg_rd<=32'h00000000;
            //ALU
            alu_res<=5'b00000;
            //SLU
            dmem_rd_out<=32'h00000000;
            //commit
            commit<=1'b0;
        end
        else if(stall)begin
            pc_out<=pc_out;
            pc_out_add4<=pc_out_add4;
            inst<=inst;
            //decoder
            alu_op<=alu_op;
            dmem_access<=dmem_access;
            imm<=imm;
            rf_wa<=rf_wa;
            rf_we<=rf_we;
            rf_wd_sel<=rf_wd_sel;
            alu_src0_sel<=alu_src0_sel;
            alu_src1_sel<=alu_src1_sel;
            br_type<=br_type;
            //RegFile
            rf_rd0<=rf_rd0;
            rf_rd1<=rf_rd1;
            dbg_reg_ra<=dbg_reg_ra;
            dbg_reg_rd<=dbg_reg_rd;
            //ALU
            alu_res<=alu_res;
            //SLU
            dmem_rd_out<=dmem_rd_out;
            //commit
            commit<=commit;
        end
        else begin
            pc_out<=i_pc_out;
            pc_out_add4<=i_pc_out_add4;
            inst<=i_inst;
            //decoder
            alu_op<=i_alu_op;
            dmem_access<=i_dmem_access;
            imm<=i_imm;
            rf_wa<=i_rf_wa;
            rf_we<=i_rf_we;
            rf_wd_sel<=i_rf_wd_sel;
            alu_src0_sel<=i_alu_src0_sel;
            alu_src1_sel<=i_alu_src1_sel;
            br_type<=i_br_type;
            //RegFile
            rf_rd0<=i_rf_rd0;
            rf_rd1<=i_rf_rd1;
            dbg_reg_ra<=i_dbg_reg_ra;
            dbg_reg_rd<=i_dbg_reg_rd;
            //ALU
            alu_res<=i_alu_res;
            //SLU
            dmem_rd_out<=i_dmem_rd_out;
            //commit
            commit<=i_commit;
        end
    end
end

endmodule


module NPC_MUX # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           pc_add4,pc_offset,pc_j,
    input                   [      1 : 0]           npc_sel,

    output        reg       [WIDTH-1 : 0]           npc
);

    always @(*) begin
        case (npc_sel)
            2'b00:
                npc = pc_add4; 
            2'b01:
                npc = pc_offset; 
            2'b10:
                npc = pc_j;
        endcase
    end

endmodule


module DECODER (
    input                   [31 : 0]            inst,

    output      reg         [ 4 : 0]            alu_op,

    output      reg         [ 3 : 0]            dmem_access,

    output      reg         [31 : 0]            imm,

    output                  [ 4 : 0]            rf_ra0,
    output                  [ 4 : 0]            rf_ra1,
    output                  [ 4 : 0]            rf_wa,
    output                  [ 0 : 0]            rf_we,
    output                  [ 1 : 0]            rf_wd_sel,

    output                  [ 0 : 0]            alu_src0_sel,
    output                  [ 0 : 0]            alu_src1_sel,

    output                  [ 3 : 0]            br_type
);

reg [4:0] rf_ra0_reg,rf_ra1_reg,rf_wa_reg;
reg [3:0] br_type_reg;
reg [0:0] rf_we_reg,alu_src0_sel_reg,alu_src1_sel_reg;
reg [1:0] rf_wd_sel_reg;

always @(*) begin

    case (inst[6:0])
        7'b0110011:begin//R-Type
            imm<=32'h00000000;

            rf_ra0_reg<=inst[19:15];
            rf_ra1_reg<=inst[24:20];
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b0;
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;

            case (inst[14:12])
                3'b000:begin//add,sub,
                    case (inst[31:25])
                        7'b0000000:begin//add
                            alu_op=`ADD;
                        end 
                        7'b0100000:begin//sub
                            alu_op=`SUB;
                        end
                    endcase
                end 
                3'b001:begin//sll
                    alu_op=`SLL;
                end
                3'b010:begin//slt
                    alu_op=`SLT;                   
                end
                3'b011:begin//sltu
                    alu_op=`SLTU;                   
                end
                3'b100:begin//xor
                    alu_op=`XOR;
                end
                3'b101:begin//srl,sra
                    case (inst[31:25])
                        7'b0000000:begin//srl
                            alu_op=`SRL;
                        end
                        7'b0100000:begin//sra
                            alu_op=`SRA;
                        end 
                    endcase
                end
                3'b110:begin//or
                    alu_op=`OR;
                end
                3'b111:begin//and
                    alu_op=`AND;
                end
            endcase
        end
        7'b0010011:begin//I-Type
            rf_ra0_reg<=inst[19:15];
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;            
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;

            case (inst[14:12])
                3'b000:begin//addi
                    alu_op=`ADD;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b010:begin//slti
                    alu_op=`SLT;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b011:begin//sltiu
                    alu_op=`SLTU;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end 
                3'b100:begin//xori
                    alu_op=`XOR;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b110:begin//ori
                    alu_op=`OR;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b111:begin//andi
                    alu_op=`AND;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b001:begin//slli
                    alu_op=`SLL;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b101:begin//srli,srai
                    case (inst[31:25])
                        7'b0000000: begin//srli
                            alu_op=`SRL;
                            imm={27'b0,inst[24:20]};
                        end
                        7'b0100000:begin//srai
                            alu_op=`SRA;
                            imm={27'b0,inst[24:20]};
                        end
                    endcase
                end
            endcase
        end 
        7'b0110111:begin//lui
            alu_op=`ADD;
            imm={inst[31:12],12'h000};

            rf_ra0_reg<=5'b00000;
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;  
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;  
        end
        7'b0010111:begin//auipc
            alu_op=`ADD;
            imm={inst[31:12],12'h000};

            rf_ra0_reg<=5'b00000;
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1; 
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;   
        end
        7'b1100011:begin//B-Type
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{20{inst[31:31]}},inst[7:7],inst[30:25],inst[11:8],1'b0};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=inst[24:20];
            rf_wa_reg=5'b00000;
            rf_we_reg=1'b0;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1;

            case (inst[14:12])
                `I_beq:
                    br_type_reg=`beq;
                `I_bne:
                    br_type_reg=`bne;
                `I_blt:
                    br_type_reg=`blt;
                `I_bge:
                    br_type_reg=`bge;
                `I_bltu:
                    br_type_reg=`bltu;
                `I_bgeu:
                    br_type_reg=`bgeu;
            endcase
        end
        7'b1101111:begin//jal
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{12{inst[31:31]}},inst[19:12],inst[20:20],inst[30:21],1'b0};

            rf_ra0_reg=5'b00000;
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1;

            br_type_reg=`jal;

        end
        7'b1100111:begin//jalr
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{21{inst[31:31]}},inst[30:20]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=`jalr;
            
        end
        7'b0000011:begin//L-Type
            alu_op=`ADD;
            imm={20'h00000,inst[31:20]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b10;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=4'hf;

            case (inst[14:12])
                3'b000:begin//lb
                    dmem_access=`lb;
                end 
                3'b001:begin//lh
                    dmem_access=`lh;
                end
                3'b010:begin//lw
                    dmem_access=`lw;
                end
                3'b100:begin//lbu
                    dmem_access=`lbu;
                end
                3'b101:begin//lhu
                    dmem_access=`lhu;
                end
                default:begin
                    dmem_access=4'b1111;
                end
            endcase
        end
        7'b0100011:begin//S-Type
            alu_op=`ADD;
            imm={inst[31:25],inst[11:7]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=inst[24:20];
            rf_wa_reg=5'b00000;
            rf_we_reg=1'b0;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=4'hf;
            case (inst[14:12])
                3'b000:begin//sb
                    dmem_access=`sb;
                end 
                3'b001:begin//sh
                    dmem_access=`sh;
                end
                3'b010:begin//sw
                    dmem_access=`sw;
                end
                default: begin
                    dmem_access=4'b1111;
                end
            endcase
        end
        default:begin
            alu_op=`ADD;
            dmem_access=4'hf;
            imm=32'h00000000;

            rf_ra0_reg=5'b00000;
            rf_ra1_reg=5'b00000;
            rf_wa_reg=5'b00000;
            rf_we_reg=1'b0;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b0;

            br_type_reg=4'hf;
        end
    endcase
end

assign rf_ra0=rf_ra0_reg;
assign rf_ra1=rf_ra1_reg;
assign rf_wa=rf_wa_reg;
assign rf_wd_sel=rf_wd_sel_reg;
assign br_type=br_type_reg;
assign rf_we=rf_we_reg;
assign alu_src0_sel=alu_src0_sel_reg;
assign alu_src1_sel=alu_src1_sel_reg;

endmodule

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


module MUX2 # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           src0, src1,
    input                   [      0 : 0]           sel,

    output                  [WIDTH-1 : 0]           res
);

    assign res = sel ? src1 : src0;

endmodule

module MUX4 # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           src0, src1, src2, src3,
    input                   [      1 : 0]           sel,

    output                  [WIDTH-1 : 0]           res
);

    assign res = sel[1] ? (sel[0] ? src3 : src2) : (sel[0] ? src1 : src0);

endmodule


module ALU (
    input                   [31 : 0]            alu_src0,
    input                   [31 : 0]            alu_src1,
    input                   [ 4 : 0]            alu_op,

    output      reg         [31 : 0]            alu_res
);

    always @(*) begin
        case(alu_op)
            `ADD  :
                alu_res = alu_src0 + alu_src1;
            `SUB:
                alu_res=alu_src0-alu_src1;
            `SLTU:
                if(alu_src0<alu_src1)
                    alu_res=1;
                else
                    alu_res=0;
            `SLT:
                if(alu_src0[31]==1&&alu_src1[31]==0)
                    alu_res=1;
                else if(alu_src0[31]==0&&alu_src1[31]==1)
                    alu_res=0;
                else if(alu_src0[30:0]<alu_src1[30:0])
                    alu_res=1;
                else
                    alu_res=0;
            `AND:
                alu_res=alu_src0&alu_src1;
            `OR:
                alu_res=alu_src0|alu_src1;
             `XOR:
                alu_res=alu_src0^alu_src1;
            `SLL:
                alu_res=alu_src0<<alu_src1[4:0];
            `SRL:
                alu_res=alu_src0>>alu_src1[4:0];
            `SRA:
                alu_res=($signed(alu_src0))>>>alu_src1[4:0];
            `SRC0:
                alu_res=alu_src0;
            `SRC1:
                alu_res=alu_src1;
            default :
                alu_res = 32'H0;
        endcase
    end
endmodule


module BRANCH(
    input                   [ 3 : 0]            br_type,

    input                   [31 : 0]            br_src0,
    input                   [31 : 0]            br_src1,

    output      reg         [ 1 : 0]            npc_sel
);

always @(*) begin
    case (br_type)          
        `jal:begin
            npc_sel=2'b01;
        end
        `jalr:begin
            npc_sel=2'b10;
        end  
        `beq:begin
            if(br_src0==br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
        end
        `bne:begin
            if(br_src0!=br_src1)
                npc_sel=2'b10;
            else
                npc_sel=2'b00;
        end           
        `blt:begin
            if(br_src0[31]==1'b1&&br_src1[31]==1'b0)
                npc_sel=2'b01;
            else if(br_src0[31]==1'b0&&br_src1[31]==1'b1)
                npc_sel=2'b00;
            else if(br_src0[30:0]<br_src1[30:0])
                npc_sel=2'b01;
            else 
                npc_sel=2'b00;
        end
        `bge:begin
            if(br_src0[31]==1'b0&&br_src1[31]==1'b1)
                npc_sel=2'b01;
            else if(br_src0[31]==1'b1&&br_src1[31]==1'b0)
                npc_sel=2'b00;
            else if(br_src0[30:0]>=br_src1[30:0])
                npc_sel=2'b01;
            else 
                npc_sel=2'b00;
        end
        `bltu:begin
            if(br_src0<br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
        end
        `bgeu:begin
            if(br_src0>=br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
    end
        default:
            npc_sel=2'b00;
    endcase
end

endmodule


module SLU (
    input                   [31 : 0]                addr,
    input                   [ 3 : 0]                dmem_access,

    input                   [31 : 0]                rd_in,
    input                   [31 : 0]                wd_in,

    output      reg         [31 : 0]                rd_out,
    output      reg         [31 : 0]                wd_out
);

always @(*) begin
    case (dmem_access)
        `lb:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={{24{rd_in[7:7]}},rd_in[7:0]};
                end 
                1:begin
                    rd_out={{24{rd_in[15:15]}},rd_in[15:8]};
                end
                2:begin
                    rd_out={{24{rd_in[23:23]}},rd_in[23:16]};
                end
                3:begin
                    rd_out={{24{rd_in[31:31]}},rd_in[31:24]};
                end
            endcase
        end 
        `lbu:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={24'h000000,rd_in[7:0]};
                end 
                1:begin
                    rd_out={24'h000000,rd_in[15:8]};
                end
                2:begin
                    rd_out={24'h000000,rd_in[23:16]};
                end
                3:begin
                    rd_out={24'h000000,rd_in[31:24]};
                end
            endcase
        end
        `lh:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={{16{rd_in[15:15]}},rd_in[15:0]};
                end
                2:begin
                    rd_out={{16{rd_in[31:31]}},rd_in[31:16]};
                end 
                default: begin
                    rd_out=32'hffffffff;
                end
            endcase
        end
        `lhu:begin
            wd_out=wd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={16'h0000,rd_in[15:0]};
                end
                2:begin
                    rd_out={16'h0000,rd_in[31:16]};
                end 
                default: begin
                    rd_out=32'hffffffff;
                end
            endcase
        end
        `lw:begin
            wd_out=wd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out=rd_in;
                end 
                default:begin
                    rd_out=32'hffffffff;
                end 
            endcase
        end
        `sb:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out={rd_in[31:8],wd_in[7:0]};
                end 
                1:begin
                    wd_out={rd_in[31:16],wd_in[7:0],rd_in[7:0]};
                end
                2:begin
                    wd_out={rd_in[31:24],wd_in[7:0],rd_in[15:0]};
                end
                3:begin
                    wd_out={rd_in[7:0],rd_in[23:0]};
                end 
            endcase
        end
        `sh:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out={rd_in[31:16],wd_in[15:0]};
                end 
                2:begin
                    wd_out={wd_in[31:16],rd_in[15:0]};
                end
                default: begin
                    wd_out=rd_in;
                end
            endcase
        end
        `sw:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out=wd_in;
                end 
                default:begin
                    wd_out=rd_in;
                end 
            endcase
        end
        default:begin
            wd_out=rd_in;
            rd_out=32'h00000000;
        end
    endcase
end

endmodule