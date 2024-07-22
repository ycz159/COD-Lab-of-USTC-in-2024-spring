`include "src/bram.v"
/*
直接映射Cache
- Cache行数：8行
- 块大小：4字（16字节 128位）
- 采用写回写分配策略
*/
module cache #(
    parameter INDEX_WIDTH       = 3,    // Cache索引位宽 2^3=8行
    parameter LINE_OFFSET_WIDTH = 2,    // 行偏移位宽，决定了一行的宽度 2^2=4字
    parameter SPACE_OFFSET      = 2,    // 一个地址空间占1个字节，因此一个字需要4个地址空间，由于假设为整字读取，处理地址的时候可以默认后两位为0
    parameter WAY_NUM           = 2     // Cache N路组相联(N=1的时候是直接映射)
)(
    input                     clk,    
    input                     rstn,
    /* CPU接口 */  
    input [31:0]              addr,   // CPU地址
    input                     r_req, // CPU读请求
    input                     w_req,  // CPU写请求
    input [31:0]              w_data,  // CPU写数据
    output [31:0]             r_data,  // CPU读数据
    output reg                miss,   // 缓存未命中
    /* 内存接口 */  
    output reg                     mem_r, // 内存读请求
    output reg                     mem_w,  // 内存写请求
    output reg [31:0]              mem_addr,  // 内存地址
    output reg [127:0] mem_w_data,  // 内存写数据 一次写一行
    input      [127:0] mem_r_data,  // 内存读数据 一次读一行
    input                          mem_ready  // 内存就绪信号
);

    // Cache参数
    localparam
        // Cache行宽度
        LINE_WIDTH = 32 << LINE_OFFSET_WIDTH,
        // 标记位宽度
        TAG_WIDTH = 32 - INDEX_WIDTH - LINE_OFFSET_WIDTH - SPACE_OFFSET,
        // Cache行数
        SET_NUM   = 1 << INDEX_WIDTH;
    
    // Cache相关寄存器
    reg [31:0]           addr_buf;    // 请求地址缓存-用于保留CPU请求地址
    reg [31:0]           w_data_buf;  // 写数据缓存
    reg op_buf;  // 读写操作缓存，用于在MISS状态下判断是读还是写，如果是写则需要将数据写回内存 0:读 1:写
    reg [LINE_WIDTH-1:0] ret_buf;     // 返回数据缓存-用于保留内存返回数据

    // Cache导线
    wire [INDEX_WIDTH-1:0] r_index;  // 索引读地址
    wire [INDEX_WIDTH-1:0] w_index;  // 索引写地址
    reg  [LINE_WIDTH-1:0]  r_line;   // Data Bram读数据
    wire [LINE_WIDTH-1:0]  w_line;   // Data Bram写数据
    wire [LINE_WIDTH-1:0]  w_line_mask;  // Data Bram写数据掩码
    wire [LINE_WIDTH-1:0]  w_data_line;  // 输入写数据移位后的数据
    wire [TAG_WIDTH-1:0]   tag;      // CPU请求地址中分离的标记 用于比较 也可用于写入
    reg  [TAG_WIDTH-1:0]   r_tag;    // Tag Bram读数据 用于比较
    wire [LINE_OFFSET_WIDTH-1:0] word_offset;  // 字偏移
    reg  [31:0]            cache_data;  // Cache数据
    reg  [31:0]            mem_data;    // 内存数据
    wire [31:0]            dirty_mem_addr; // 通过读出的tag和对应的index，偏移等得到脏块对应的内存地址并写回到正确的位置
    reg  valid;  // Cache有效位
    reg  dirty;  // Cache脏位.
    reg  w_valid;  // Cache写有效位
    reg  w_dirty;  // Cache写脏位
    wire hit;    // Cache命中

    // Cache相关控制信号
    reg addr_buf_we;  // 请求地址缓存写使能
    reg ret_buf_we;   // 返回数据缓存写使能
    reg data_we;      // Cache写使能
    reg tag_we;       // Cache标记写使能
    reg data_from_mem;  // 从内存读取数据
    reg refill;       // 标记需要重新填充，在MISS状态下接受到内存数据后置1,在IDLE状态下进行填充后置0

    // 状态机信号
    localparam 
        IDLE      = 3'd0,  // 空闲状态
        READ      = 3'd1,  // 读状态
        MISS      = 3'd2,  // 缺失时等待主存读出新块
        WRITE     = 3'd3,  // 写状态
        W_DIRTY   = 3'd4;  // 写缺失时等待主存写入脏块
    reg [2:0] CS;  // 状态机当前状态
    reg [2:0] NS;  // 状态机下一状态

    // 状态机
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            CS <= IDLE;
        end else begin
            CS <= NS;
        end
    end

    // 中间寄存器保留初始的请求地址和写数据，可以理解为addr_buf中的地址为当前Cache正在处理的请求地址，而addr中的地址为新的请求地址
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            addr_buf <= 0;
            ret_buf <= 0;
            w_data_buf <= 0;
            op_buf <= 0;
            refill <= 0;
        end else begin
            if (addr_buf_we) begin
                addr_buf <= addr;
                w_data_buf <= w_data;
                op_buf <= w_req;
            end
            if (ret_buf_we) begin
                ret_buf <= mem_r_data;
            end
            if (CS == MISS && mem_ready) begin
                refill <= 1;
            end
            if (CS == IDLE) begin
                refill <= 0;
            end
        end
    end

    // 对输入地址进行解码
    assign r_index = addr[INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET - 1: LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign w_index = addr_buf[INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET - 1: LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign tag = addr_buf[31:INDEX_WIDTH+LINE_OFFSET_WIDTH+SPACE_OFFSET];
    assign word_offset = addr_buf[LINE_OFFSET_WIDTH+SPACE_OFFSET-1:SPACE_OFFSET];

    // 脏块地址计算
    assign dirty_mem_addr = {r_tag, w_index}<<(LINE_OFFSET_WIDTH+SPACE_OFFSET);

    // 写回地址、数据寄存器
    reg [31:0] dirty_mem_addr_buf;
    reg [127:0] dirty_mem_data_buf;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dirty_mem_addr_buf <= 0;
            dirty_mem_data_buf <= 0;
        end else begin
            if (CS == READ || CS == WRITE) begin
                dirty_mem_addr_buf <= dirty_mem_addr;
                dirty_mem_data_buf <= r_line;
            end
        end
    end

    // Tag1 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram1(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we1),
        .dout({valid1, dirty1, r_tag1})
    );

    // Data1 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram1(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we1),
        .dout(r_line1)
    );


    // Tag2 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram2(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we2),
        .dout({valid2, dirty2, r_tag2})
    );

    // Data2 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram2(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we2),
        .dout(r_line2)
    );


    // Tag3 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram3(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we3),
        .dout({valid3, dirty3, r_tag3})
    );

    // Data3 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram3(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we3),
        .dout(r_line3)
    );


    // Tag4 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram4(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we4),
        .dout({valid4, dirty4, r_tag4})
    );

    // Data4 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram4(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we4),
        .dout(r_line4)
    );    


     // Tag5 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram5(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we5),
        .dout({valid5, dirty5, r_tag5})
    );

    // Data5 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram5(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we5),
        .dout(r_line5)
    );


    // Tag6 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram6(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we6),
        .dout({valid6, dirty6, r_tag6})
    );

    // Data6 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram6(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we6),
        .dout(r_line6)
    );


    // Tag7 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram7(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we7),
        .dout({valid7, dirty7, r_tag7})
    );

    // Data7 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram7(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we7),
        .dout(r_line7)
    );

    
    // Tag8 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram8(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we8),
        .dout({valid8, dirty8, r_tag8})
    );

    // Data8 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram8(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we8),
        .dout(r_line8)
    );  
    
    
     // Tag9 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram9(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we9),
        .dout({valid9, dirty9, r_tag9})
    );

    // Data9 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram9(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we9),
        .dout(r_line9)
    );


    // Tag10 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram10(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we10),
        .dout({valid10, dirty10, r_tag10})
    );

    // Data10 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram10(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we10),
        .dout(r_line10)
    );


    // Tag11 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram11(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we11),
        .dout({valid11, dirty11, r_tag11})
    );

    // Data11 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram11(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we11),
        .dout(r_line11)
    );


    // Tag12 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram12(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we12),
        .dout({valid12, dirty12, r_tag12})
    );

    // Data12 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram12(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we12),
        .dout(r_line12)
    );    


     // Tag13 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram13(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we13),
        .dout({valid13, dirty13, r_tag13})
    );

    // Data13 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram13(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we13),
        .dout(r_line13)
    );


    // Tag14 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram14(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we14),
        .dout({valid14, dirty14, r_tag14})
    );

    // Data14 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram14(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we14),
        .dout(r_line14)
    );


    // Tag15 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram15(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we15),
        .dout({valid15, dirty15, r_tag15})
    );

    // Data15 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram15(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we15),
        .dout(r_line15)
    );

    
    // Tag16 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(TAG_WIDTH + 2) // 最高位为有效位，次高位为脏位，再次为最近访问位，低位为标记位
    ) tag_bram16(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din({w_valid, w_dirty, tag}),
        .we(tag_we16),
        .dout({valid16, dirty16, r_tag16})
    );

    // Data16 Bram
    bram #(
        .ADDR_WIDTH(INDEX_WIDTH),
        .DATA_WIDTH(LINE_WIDTH)
    ) data_bram16(
        .clk(clk),
        .raddr(r_index),
        .waddr(w_index),
        .din(w_line),
        .we(data_we16),
        .dout(r_line16)
    );    
    /*
    Tag Bram control interface 
    input(  hit, 
            mem_ready, 
            tag_we, 
            r_index, 
            r_line,
            {valid1, dirty1, r_tag1},
            {valid2, dirty2, r_tag2});
    output( tag_we1, 
            tag_we2, 
            data_we1,
            data_we2,
            {valid, dirty, r_tag})
    */
    //reg  w_age1,w_age2;
    //wire r_age1, r_age2;
    wire [14:0]age_out;
    reg  [14:0]age_data;
    reg        age_en;
    reg  [14:0] age[0:(1 << INDEX_WIDTH)-1];

    reg  tag_we1,tag_we2,tag_we3,tag_we4,tag_we5,tag_we6,tag_we7,tag_we8,tag_we9,tag_we10,tag_we11,tag_we12,tag_we13,tag_we14,tag_we15,tag_we16;
    reg  data_we1,data_we2,data_we3,data_we4,data_we5,data_we6,data_we7,data_we8,data_we9,data_we10,data_we11,data_we12,data_we13,data_we14,data_we15,data_we16;
    
    wire valid1,valid2,valid3,valid4,valid5,valid6,valid7,valid8,valid9,valid10,valid11,valid12,valid13,valid14,valid15,valid16;
    wire dirty1,dirty2,dirty3,dirty4,dirty5,dirty6,dirty7,dirty8,dirty9,dirty10,dirty11,dirty12,dirty13,dirty14,dirty15,dirty16;
    wire [TAG_WIDTH-1:0] r_tag1,r_tag2,r_tag3,r_tag4,r_tag5,r_tag6,r_tag7,r_tag8,r_tag9,r_tag10,r_tag11,r_tag12,r_tag13,r_tag14,r_tag15,r_tag16;

    wire hit1,hit2,hit3,hit4,hit5,hit6,hit7,hit8,hit9,hit10,hit11,hit12,hit13,hit14,hit15,hit16;

    wire [LINE_WIDTH-1:0] r_line1,r_line2,r_line3,r_line4,r_line5,r_line6,r_line7,r_line8,r_line9,r_line10,r_line11,r_line12,r_line13,r_line14,r_line15,r_line16;

    integer i;
    initial begin
        for (i = 0; i < (1 << INDEX_WIDTH); i = i + 1) begin
            age[i] = 0;
        end

        age_out_buf = 14'h0000;
        flag = 1'b0;
    end

    //reg [LINE_WIDTH-1:0] w_line_buf;
    //reg [TAG_WIDTH-1:0]  tag_buf;
    //reg forward,forward_buf,w_valid_buf,w_dirty_buf;

    
    //Tag Bram control
    
    always @(*) begin
        //init
        /*tag_we1=0;tag_we2=0;data_we1=0;data_we2=0;
        valid=0;dirty=0;r_tag=0;r_line=0;
        age_data=0;*/
        tag_we1=1'b0;
        tag_we2=1'b0;
        tag_we3=1'b0;
        tag_we4=1'b0;
        tag_we5=1'b0;
        tag_we6=1'b0;
        tag_we7=1'b0;
        tag_we8=1'b0;
        tag_we9=1'b0;
        tag_we10=1'b0;
        tag_we11=1'b0;
        tag_we12=1'b0;
        tag_we13=1'b0;
        tag_we14=1'b0;
        tag_we15=1'b0;
        tag_we16=1'b0;

        data_we1=1'b0;
        data_we2=1'b0;
        data_we3=1'b0;
        data_we4=1'b0;
        data_we5=1'b0;
        data_we6=1'b0;
        data_we7=1'b0;
        data_we8=1'b0;
        data_we9=1'b0;
        data_we10=1'b0;
        data_we11=1'b0;
        data_we12=1'b0;
        data_we13=1'b0;
        data_we14=1'b0;
        data_we15=1'b0;
        data_we16=1'b0;
        if(hit1&&(CS==READ||CS==WRITE))begin
            valid = valid1;
            dirty = dirty1;
            r_tag = r_tag1;

            tag_we1 =tag_we;
            data_we1=data_we;
            r_line  =r_line1;

            //age_data<=1'b1;
            //age_en<=1;
            case (WAY_NUM)
                2:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:0]};
                end 
                4:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],1'b1,age_out_buf[2:0]};
                end
                8:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],4'b1010};
                end
                16:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],1'b1,age_out_buf[2:2],1'b1,1'b1};
                end 
            endcase

        end
        else if(hit2&&(CS==READ||CS==WRITE))begin
            valid = valid2;
            dirty = dirty2;
            r_tag = r_tag2;

            tag_we2 =tag_we;
            data_we2=data_we;
            r_line  =r_line2;

            //age_data
            case (WAY_NUM)
            2:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:0]};
            end 
            4:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],1'b1,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],4'b1010};
            end
            16:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],1'b1,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
        end

        else if(hit3&&(CS==READ||CS==WRITE))begin
            valid = valid3;
            dirty = dirty3;
            r_tag = r_tag3;

            tag_we3 =tag_we;
            data_we3=data_we;
            r_line  =r_line3;

            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],1'b0,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],4'b0010};
            end
            16:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],1'b0,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
        end
        else if(hit4&&(CS==READ||CS==WRITE))begin
            valid = valid4;
            dirty = dirty4;
            r_tag = r_tag4;

            tag_we4 =tag_we;
            data_we4=data_we;
            r_line  =r_line4;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],1'b0,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],4'b0010};
            end
            16:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],1'b0,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
        end
        else if(hit5&&(CS==READ||CS==WRITE))begin
            valid = valid5;
            dirty = dirty5;
            r_tag = r_tag5;

            tag_we5 =tag_we;
            data_we5=data_we;
            r_line  =r_line5;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:10],1'b1,age_out_buf[8:5],1'b1,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:10],1'b1,age_out_buf[8:5],1'b1,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
        end
        else if(hit6&&(CS==READ||CS==WRITE))begin
            valid = valid6;
            dirty = dirty6;
            r_tag = r_tag6;

            tag_we6 =tag_we;
            data_we6=data_we;
            r_line  =r_line6;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:10],1'b0,age_out_buf[8:5],1'b1,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:10],1'b0,age_out_buf[8:5],1'b1,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
        end
        else if(hit7&&(CS==READ||CS==WRITE))begin
            valid = valid7;
            dirty = dirty7;
            r_tag = r_tag7;

            tag_we7=tag_we;
            data_we7=data_we;
            r_line=r_line7;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:11],1'b1,age_out_buf[9:5],1'b0,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:11],1'b1,age_out_buf[9:5],1'b0,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
        end
        else if(hit8&&(CS==READ||CS==WRITE))begin
            valid = valid8;
            dirty = dirty8;
            r_tag = r_tag8;

            tag_we8=tag_we;
            data_we8=data_we;
            r_line=r_line8;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:11],1'b0,age_out_buf[9:5],1'b0,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:11],1'b0,age_out_buf[9:5],1'b0,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
        end
        else if(hit9&&(CS==READ||CS==WRITE))begin
            valid = valid9;
            dirty = dirty9;
            r_tag = r_tag9;

            tag_we9=tag_we;
            data_we9=data_we;
            r_line=r_line9;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:12],1'b1,age_out_buf[10:6],1'b1,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit10&&(CS==READ||CS==WRITE))begin
            valid = valid10;
            dirty = dirty10;
            r_tag = r_tag10;

            tag_we10=tag_we;
            data_we10=data_we;
            r_line=r_line10;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:12],1'b0,age_out_buf[10:6],1'b1,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit11&&(CS==READ||CS==WRITE))begin
            valid = valid11;
            dirty = dirty11;
            r_tag = r_tag11;

            tag_we11=tag_we;
            data_we11=data_we;
            r_line=r_line11;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:13],1'b1,age_out_buf[11:6],1'b0,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit12&&(CS==READ||CS==WRITE))begin
            valid = valid12;
            dirty = dirty12;
            r_tag = r_tag12;
            
            tag_we12=tag_we;
            data_we12=data_we;
            r_line=r_line12;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:13],1'b0,age_out_buf[11:6],1'b0,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit13&&(CS==READ||CS==WRITE))begin
            valid = valid13;
            dirty = dirty13;
            r_tag = r_tag13;

            tag_we13=tag_we;
            data_we13=data_we;
            r_line=r_line13;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:14],1'b1,age_out_buf[12:7],1'b1,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit14&&(CS==READ||CS==WRITE))begin
            valid = valid14;
            dirty = dirty14;
            r_tag = r_tag14;

            tag_we14=tag_we;
            data_we14=data_we;
            r_line=r_line14;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:14],1'b0,age_out_buf[12:7],1'b1,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit15&&(CS==READ||CS==WRITE))begin
            valid = valid15;
            dirty = dirty15;
            r_tag = r_tag15;

            tag_we15=tag_we;
            data_we15=data_we;
            r_line=r_line15;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={1'b1,age_out_buf[13:7],1'b0,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
        end
        else if(hit16&&(CS==READ||CS==WRITE))begin
            valid = valid16;
            dirty = dirty16;
            r_tag = r_tag16;

            tag_we16=tag_we;
            data_we16=data_we;
            r_line=r_line16;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={1'b0,age_out_buf[13:7],1'b0,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
        end

        else begin
/*            
            if(age_out_buf)begin
                valid <= valid2;
                dirty <= dirty2;
                r_tag <= r_tag2;               
                
                tag_we2<=tag_we;
                tag_we1<=1'b0;
                data_we2<=data_we;
                data_we1<=1'b0; 

                r_line<=r_line2;

                //age_data<=1'b0;
                //age_en<=1;
            end
            else begin                            
                valid <= valid1;
                dirty <= dirty1;
                r_tag <= r_tag1;     

                tag_we1<=tag_we;
                tag_we2<=1'b0;
                data_we1<=data_we;
                data_we2<=1'b0;
                
                r_line<=r_line1;

                //age_data<=1'b1;
                //age_en<=1;
            end
*/
            case (age_out_buf[0:0])
                1'b0:begin
                    case (age_out_buf[1:1])
                        1'b0:begin
                            case (age_out_buf[3:3])
                                1'b0:begin
                                    case (age_out_buf[7:7])
                                        1'b0:begin//1
                                            valid = valid1;
            dirty = dirty1;
            r_tag = r_tag1;

            tag_we1=tag_we;
            data_we1=data_we;
            r_line=r_line1;

            //age_data<=1'b1;
            //age_en<=1;
            case (WAY_NUM)
                2:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:0]};
                end 
                4:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],1'b1,age_out_buf[2:0]};
                end
                8:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],4'b1010};
                end
                16:begin
                    age_data={age_out_buf[14:8],1'b1,age_out_buf[6:4],1'b1,age_out_buf[2:2],1'b1,1'b1};
                end 
            endcase
                                        end 
                                        default: begin//2
                                            valid = valid2;
            dirty = dirty2;
            r_tag = r_tag2;

            tag_we2=tag_we;
            data_we2=data_we;
            r_line=r_line2;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:0]};
            end 
            4:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],1'b1,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],4'b1010};
            end
            16:begin
                age_data={age_out_buf[14:8],1'b0,age_out_buf[6:4],1'b1,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
                                        end
                                    endcase
                                end 
                                default: begin
                                    case (age_out_buf[8:8])
                                        1'b0:begin//3
                                            valid = valid3;
            dirty = dirty3;
            r_tag = r_tag3;

            tag_we3=tag_we;
            data_we3=data_we;
            r_line=r_line3;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],1'b0,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],4'b0010};
            end
            16:begin
                age_data={age_out_buf[14:9],1'b1,age_out_buf[7:4],1'b0,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
                                        end 
                                        default: begin//4
                                            valid = valid4;
            dirty = dirty4;
            r_tag = r_tag4;

            tag_we4=tag_we;
            data_we4=data_we;
            r_line=r_line4;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],1'b0,age_out_buf[2:0]};
            end
            8:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],4'b0010};
            end
            16:begin
                age_data={age_out_buf[14:9],1'b0,age_out_buf[7:4],1'b0,age_out_buf[2:2],1'b1,1'b1};
            end 
        endcase
                                        end
                                    endcase
                                end
                            endcase
                        end 
                        default: begin
                            case (age_out_buf[4:4])
                                1'b0:begin
                                    case (age_out_buf[9:9])
                                        1'b0:begin//5
                                            valid = valid5;
            dirty = dirty5;
            r_tag = r_tag5;

            tag_we5=tag_we;
            data_we5=data_we;
            r_line=r_line5;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:10],1'b1,age_out_buf[8:5],1'b1,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:10],1'b1,age_out_buf[8:5],1'b1,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
                                        end 
                                        default: begin//6
                                            valid = valid6;
            dirty = dirty6;
            r_tag = r_tag6;

            tag_we6=tag_we;
            data_we6=data_we;
            r_line=r_line6;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:10],1'b0,age_out_buf[8:5],1'b1,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:10],1'b0,age_out_buf[8:5],1'b1,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
                                        end
                                    endcase                               
                                end 
                                default: begin
                                    case (age_out_buf[10:10])
                                         1'b0:begin//7
                                            valid = valid7;
            dirty = dirty7;
            r_tag = r_tag7;

            tag_we7=tag_we;
            data_we7=data_we;
            r_line=r_line7;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:11],1'b1,age_out_buf[9:5],1'b0,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:11],1'b1,age_out_buf[9:5],1'b0,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
                                        end 
                                        default: begin//8
                                            valid = valid8;
            dirty = dirty8;
            r_tag = r_tag8;

            tag_we8=tag_we;
            data_we8=data_we;
            r_line=r_line8;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data={age_out_buf[14:11],1'b0,age_out_buf[9:5],1'b0,age_out_buf[3:2],2'b00};
            end
            16:begin
                age_data={age_out_buf[14:11],1'b0,age_out_buf[9:5],1'b0,age_out_buf[3:2],1'b0,1'b1};
            end 
        endcase
                                        end
                                    endcase                               
                                end
                            endcase                            
                        end
                    endcase
                end 
                default:begin
                    case (age_out_buf[2:2])
                        1'b0:begin
                            case (age_out_buf[5:5])
                                1'b0:begin
                                    case (age_out_buf[11:11])
                                        1'b0:begin//9
                                            valid = valid9;
            dirty = dirty9;
            r_tag = r_tag9;

            tag_we9=tag_we;
            data_we9=data_we;
            r_line=r_line9;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:12],1'b1,age_out_buf[10:6],1'b1,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end 
                                        default: begin//10
                                            valid = valid10;
            dirty = dirty10;
            r_tag = r_tag10;

            tag_we10=tag_we;
            data_we10=data_we;
            r_line=r_line10;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:12],1'b0,age_out_buf[10:6],1'b1,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end
                                    endcase
                                end 
                                default: begin
                                    case (age_out_buf[12:12])
                                        1'b0:begin//11
                                            valid = valid11;
            dirty = dirty11;
            r_tag = r_tag11;

            tag_we11=tag_we;
            data_we11=data_we;
            r_line=r_line11;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:13],1'b1,age_out_buf[11:6],1'b0,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end 
                                        default: begin//12
                                            valid = valid12;
            dirty = dirty12;
            r_tag = r_tag12;

            tag_we12=tag_we;
            data_we12=data_we;
            r_line=r_line12;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:13],1'b0,age_out_buf[11:6],1'b0,age_out_buf[4:3],1'b1,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end
                                    endcase
                                end
                            endcase                        
                        end 
                        default: begin
                            case (age_out_buf[6:6])
                                1'b0:begin
                                    case (age_out_buf[13:13])
                                        1'b0:begin//13
                                            valid = valid13;
            dirty = dirty13;
            r_tag = r_tag13;

            tag_we13=tag_we;
            data_we13=data_we;
            r_line=r_line13;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:14],1'b1,age_out_buf[12:7],1'b1,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end 
                                        default: begin//14
                                            valid = valid14;
            dirty = dirty14;
            r_tag = r_tag14;

            tag_we14=tag_we;
            data_we14=data_we;
            r_line=r_line14;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={age_out_buf[14:14],1'b0,age_out_buf[12:7],1'b1,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end
                                endcase
                                end 
                                default: begin
                                    case (age_out_buf[14:14])
                                        1'b0:begin//15
                                            valid = valid15;
            dirty = dirty15;
            r_tag = r_tag15;

            tag_we15=tag_we;
            data_we15=data_we;
            r_line=r_line15;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={1'b1,age_out_buf[13:7],1'b0,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end 
                                        default: begin//16
                                            valid = valid16;
            dirty = dirty16;
            r_tag = r_tag16;

            tag_we16=tag_we;
            data_we16=data_we;
            r_line=r_line16;


            //age_data
            case (WAY_NUM)
            2:begin
                age_data=15'h7fff;
            end 
            4:begin
                age_data=15'h7fff;
            end
            8:begin
                age_data=15'h7fff;
            end
            16:begin
                age_data={1'b0,age_out_buf[13:7],1'b0,age_out_buf[5:3],1'b0,age_out_buf[1:1],1'b0};
            end 
        endcase
                                        end
                                endcase
                                end
                        endcase
                        end
                    endcase                   
                end 
            endcase
        end
    end
    
    reg [14:0] age_out_buf;
    reg flag;
    always @(posedge clk) begin
        if((CS==READ&&hit)||(CS==WRITE&&hit)||(CS==IDLE&&refill))
            age_en<=1;
        else
            age_en<=0;
        
        if(addr_buf_we&&flag)begin
            age_out_buf<=age_out;
        end
        else begin
            age_out_buf<=age_out_buf;
            if(addr_buf_we)
                flag<=1'b1;
            else
                flag<=flag;
        end
    end

    reg [2:0] r_age_addr;
    always @(posedge clk) begin
        if(age_en)
            age[w_index]<=age_data;
        else 
            age[w_index]<=age[w_index];
        r_age_addr<=r_index;   
    end
    assign  age_out=age[r_age_addr];


    // 判定Cache是否命中
    assign hit1 = (valid1 && (r_tag1 == tag));
    assign hit2 = (valid2 && (r_tag2 == tag));
    assign hit3 = (valid3 && (r_tag3 == tag));
    assign hit4 = (valid4 && (r_tag4 == tag));
    assign hit5 = (valid5 && (r_tag5 == tag));
    assign hit6 = (valid6 && (r_tag6 == tag));
    assign hit7 = (valid7 && (r_tag7 == tag));
    assign hit8 = (valid8 && (r_tag8 == tag));
    assign hit9 = (valid9 && (r_tag9 == tag));
    assign hit10 = (valid10 && (r_tag10 == tag));
    assign hit11 = (valid11 && (r_tag11 == tag));
    assign hit12 = (valid12 && (r_tag12 == tag));
    assign hit13 = (valid13 && (r_tag13 == tag));
    assign hit14 = (valid14 && (r_tag14 == tag));
    assign hit15 = (valid15 && (r_tag15 == tag));
    assign hit16 = (valid16 && (r_tag16 == tag));
    assign hit  = hit1||hit2||hit3||hit4||hit5||hit6||hit7||hit8||hit9||hit10||hit11||hit12||hit13||hit14||hit15||hit16;


    // 写入Cache 这里要判断是命中后写入还是未命中后写入
    assign w_line_mask = 32'hFFFFFFFF << (word_offset*32);   // 写入数据掩码
    assign w_data_line = w_data_buf << (word_offset*32);     // 写入数据移位
    assign w_line = (CS == IDLE && op_buf) ? ret_buf & ~w_line_mask | w_data_line : // 写入未命中，需要将内存数据与写入数据合并
                    (CS == IDLE) ? ret_buf : // 读取未命中
                    r_line & ~w_line_mask | w_data_line; // 写入命中,需要对读取的数据与写入的数据进行合并

    // 选择输出数据 从Cache或者从内存 这里的选择与行大小有关，因此如果你调整了行偏移位宽，这里也需要调整
    always @(*) begin
        case (word_offset)
            0: begin
                cache_data = r_line[31:0];
                mem_data = ret_buf[31:0];
            end
            1: begin
                cache_data = r_line[63:32];
                mem_data = ret_buf[63:32];
            end
            2: begin
                cache_data = r_line[95:64];
                mem_data = ret_buf[95:64];
            end
            3: begin
                cache_data = r_line[127:96];
                mem_data = ret_buf[127:96];
            end
            default: begin
                cache_data = 0;
                mem_data = 0;
            end
        endcase
    end

    assign r_data = data_from_mem ? mem_data : hit ? cache_data : 0;

    // 状态机更新逻辑
    always @(*) begin
        case(CS)
            IDLE: begin
                if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            READ: begin
                if (miss&& !dirty) begin
                    NS = MISS;
                end else if (miss && dirty) begin
                    NS = W_DIRTY;
                end else if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            MISS: begin
                if (mem_ready) begin // 这里回到IDLE的原因是为了延迟一周期，等待主存读出的新块写入Cache中的对应位置
                    NS = IDLE;
                end else begin
                    NS = MISS;
                end
            end
            WRITE: begin
                if (miss && !dirty) begin
                    NS = MISS;
                end else if (miss && dirty) begin
                    NS = W_DIRTY;
                end else if (r_req) begin
                    NS = READ;
                end else if (w_req) begin
                    NS = WRITE;
                end else begin
                    NS = IDLE;
                end
            end
            W_DIRTY: begin
                if (mem_ready) begin  // 写完脏块后回到MISS状态等待主存读出新块
                    NS = MISS;
                end else begin
                    NS = W_DIRTY;
                end
            end
            default: begin
                NS = IDLE;
            end
        endcase
    end

    // 状态机控制信号
    always @(*) begin
        addr_buf_we   = 1'b0;
        ret_buf_we    = 1'b0;
        data_we       = 1'b0;
        tag_we        = 1'b0;
        w_valid       = 1'b0;
        w_dirty       = 1'b0;
        data_from_mem = 1'b0;
        miss          = 1'b0;
        mem_r         = 1'b0;
        mem_w         = 1'b0;
        mem_addr      = 32'b0;
        mem_w_data    = 0;
        case(CS)
            IDLE: begin
                addr_buf_we = 1'b1; // 请求地址缓存写使能
                miss = 1'b0;
                ret_buf_we = 1'b0;
                if(refill) begin
                    data_from_mem = 1'b1;
                    w_valid = 1'b1;
                    w_dirty = 1'b0;
                    data_we = 1'b1;
                    tag_we = 1'b1;
                    if (op_buf) begin // 写
                        w_dirty = 1'b1;
                    end 
                end
            end
            READ: begin
                data_from_mem = 1'b0;
                if (hit) begin // 命中
                    miss = 1'b0;
                    addr_buf_we = 1'b1; // 请求地址缓存写使能
                end else begin // 未命中
                    miss = 1'b1;
                    addr_buf_we = 1'b0; 
                    if (dirty) begin // 脏数据需要写回
                        mem_w = 1'b1;
                        mem_addr = dirty_mem_addr;
                        mem_w_data = r_line; // 写回数据
                    end
                end
            end
            MISS: begin
                miss = 1'b1;
                mem_r = 1'b1;
                mem_addr = addr_buf;
                if (mem_ready) begin
                    mem_r = 1'b0;
                    ret_buf_we = 1'b1;
                end 
            end
            WRITE: begin
                data_from_mem = 1'b0;
                if (hit) begin // 命中
                    miss = 1'b0;
                    addr_buf_we = 1'b1; // 请求地址缓存写使能
                    w_valid = 1'b1;
                    w_dirty = 1'b1;
                    data_we = 1'b1;
                    tag_we = 1'b1;
                end else begin // 未命中
                    miss = 1'b1;
                    addr_buf_we = 1'b0; 
                    if (dirty) begin // 脏数据需要写回
                        mem_w = 1'b1;
                        mem_addr = dirty_mem_addr;
                        mem_w_data = r_line; // 写回数据
                    end
                end
            end
            W_DIRTY: begin
                miss = 1'b1;
                mem_w = 1'b1;
                mem_addr = dirty_mem_addr_buf;
                mem_w_data = dirty_mem_data_buf;
                if (mem_ready) begin
                    mem_w = 1'b0;
                end
            end
            default:;
        endcase
    end

endmodule