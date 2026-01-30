`resetall
`timescale 1ns/1ps
`default_nettype none
/*
 * Identify ethernet frame preamble and payload data to next layer. 
 *
 * Use a LFSR (linear feedback shift register) to check FCS.
 *
 * Check lfsr.v for CRC details.
 *
 * References : Alexforencich-verilog-ethernet, Wikipedia - ethernet frame.
 *
 * Date - uj1
 */

/* TODO:
 * 1. add FCS - finished
 * 2. add PTP
 * 3. testbench
 */

module axis_gmii_rx #(
    parameter DATA_W = 8
)(
    input wire                  clk,
    input wire                  rst_n,

    /* GMII Input Interface */
    input wire [DATA_W-1:0]     gmii_rxd,
    input wire                  gmii_rx_dv,
    input wire                  gmii_rx_er,

    /* AXI Output */
    output wire [DATA_W-1:0]    m_axis_tdata,
    output wire                 m_axis_tvalid,
    output wire                 m_axis_tlast,
    output wire                 m_axis_tuser,

    /* Status Output */
    output wire                 er_bad_frame,
    output wire                 er_bad_fcs
);

localparam [7:0]
    ETH_PRE = 8'h55,// unused
    ETH_SFD = 8'hD5;

// state machine
reg s_idle_q        = 1'b1, s_idle_next;
reg s_payload_q     = 1'b0, s_payload_next;
reg s_wait_end_q    = 1'b0, s_wait_end_next;

// input shift reg
// use shift reg of 5 levels ONLY for FCS 
reg [DATA_W-1:0]    gmii_rxd_d0 = {DATA_W{1''b0}};
reg [DATA_W-1:0]    gmii_rxd_d1 = {DATA_W{1''b0}};
reg [DATA_W-1:0]    gmii_rxd_d2 = {DATA_W{1''b0}};
reg [DATA_W-1:0]    gmii_rxd_d3 = {DATA_W{1''b0}};
reg [DATA_W-1:0]    gmii_rxd_d4 = {DATA_W{1''b0}};

reg                 gmii_rx_dv_d0 = 1'b0;
reg                 gmii_rx_dv_d1 = 1'b0;
reg                 gmii_rx_dv_d2 = 1'b0;
reg                 gmii_rx_dv_d3 = 1'b0;
reg                 gmii_rx_dv_d4 = 1'b0;

reg                 gmii_rx_er_d0 = 1'b0;
reg                 gmii_rx_er_d1 = 1'b0;
reg                 gmii_rx_er_d2 = 1'b0;
reg                 gmii_rx_er_d3 = 1'b0;
reg                 gmii_rx_er_d4 = 1'b0;

// output data path
reg [DATA_W-1:0]    m_axis_tdata_q = {DATA_W{1'b0}},    m_axis_tdata_next;
reg                 m_axis_tvalid_q = 1'b0,             m_axis_tvalid_next;
reg                 m_axis_tlast_q = 1'b0,              m_axis_tlast_next;
reg                 m_axis_tuser_q = 1'b0,              m_axis_tuser_next;

reg                 er_bad_frame_q = 1'b0,              er_bad_frame_next;
reg                 er_bad_fcs_q   = 1'b0,              er_bad_fcs_next;

reg                 reset_crc;
reg                 update_crc;

reg [31:0]          crc_state = 32'hFFFFFFFF;
wire [31:0]         crc_next;

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(8),
    .STYLE("AUTO")
)
eth_crc_8 (
    .data_in(gmii_rxd_d4),
    .state_in(crc_state),
    .data_out(),
    .state_out(crc_next)
);

assign              m_axis_tdata    = m_axis_tdata_q;
assign              m_axis_tvalid   = m_axis_tvalid_q;
assign              m_axis_tlast    = m_axis_tlast_q;
assign              m_axis_tuser    = m_axis_tuser_q;
assign              er_bad_frame    = er_bad_frame_q;
assign              er_bad_fcs      = er_bad_fcs_q;

// calculate the next state and next output
always @(*) begin
    s_idle_next     = s_idle_q;
    s_payload_next  = s_payload_q;
    s_wait_end_next = s_wait_end_q;

    m_axis_tdata_next   = {DATA_W{1'b0}};
    m_axis_tvalid_next  = 1'b0;
    m_axis_tlast_next   = 1'b0;
    m_axis_tuser_next   = 1'b0;

    er_bad_frame_next   = 1'b0;
    er_bad_fcs_next     = 1'b0;
    
    if (s_idle_q) begin
        reset_crc = 1'b1;
        s_idle_next     = 1'b1;
        s_payload_next  = 1'b0;
        if (gmii_rx_dv_d4 && !gmii_rx_er_d4 && (gmii_rxd == ETH_SFD)) begin
            s_idle_next = 1'b0;
            s_payload_next = 1'b1;
        end
    end
    
    if (s_payload_q) begin
        update_crc = 1'b1;
        s_payload_next = 1'b1;
        m_axis_tdata_next = gmii_rxd_d4;
        m_axis_tvalid_next = 1'b1;
        // frame end
        if (!gmii_rx_dv) begin
            s_idle_next = 1'b1;
            s_payload_next = 1'b0;
            m_axis_tlast_next = 1'b1;
            if (gmii_rx_er_d0 || gmii_rx_er_d1 || gmii_rx_er_d2 || gmii_rx_er_d3) begin
                m_axis_tuser_next = 1'b1;
                error_bad_frame_next = 1'b1;
            end else if ({gmii_rxd_d0, gmii_rxd_d1, gmii_rxd_d2, gmii_rxd_d3} == ~crc_next) begin
                m_axis_tuser_next = 1'b0;
            end else begin
                m_axis_tuser_next = 1'b1;
                error_bad_frame_next = 1'b1;
                error_bad_fcs_next = 1'b1;
            end
                s_idle_next = 1'b1;
        end
        // error in packet
        if (gmii_rx_dv && gmii_rx_er) begin
            s_payload_next = 1'b0;
            s_wait_end_next = 1'b1;
            m_axis_tvalid_next = 1'b0;
            m_axis_tlast_next = 1'b1;
            m_axis_tuser_next = 1'b1;
            er_bad_frame_next = 1'b1;
        end
    end

    if (s_wait_end_q) begin
        s_wait_end_next = 1'b1;
        s_idle_next = 1'b0;
        if (!gmii_rx_dv) begin
            s_wait_end_next = 1'b0;
            s_idle_next = 1'b1;
        end
    end
end

// data sampling
always @(posedge clk) begin
    s_idle_q        <= s_idle_next;
    s_payload_q     <= s_payload_next;
    s_wait_end_q    <= s_wait_end_next;

    gmii_rxd_d0     <= gmii_rxd;
    gmii_rxd_d1     <= gmii_rxd_d0;
    gmii_rxd_d2     <= gmii_rxd_d1;
    gmii_rxd_d3     <= gmii_rxd_d2;
    gmii_rxd_d4     <= gmii_rxd_d3;

    gmii_rx_dv_d0   <= gmii_rx_dv;
    gmii_rx_dv_d1   <= gmii_rx_dv & gmii_rx_dv_d0;
    gmii_rx_dv_d2   <= gmii_rx_dv & gmii_rx_dv_d1;
    gmii_rx_dv_d3   <= gmii_rx_dv & gmii_rx_dv_d2;
    gmii_rx_dv_d4   <= gmii_rx_dv & gmii_rx_dv_d3;

    gmii_rx_er_d0   <= gmii_rx_er;
    gmii_rx_er_d1   <= gmii_rx_er_d0;
    gmii_rx_er_d2   <= gmii_rx_er_d1;
    gmii_rx_er_d3   <= gmii_rx_er_d2;
    gmii_rx_er_d4   <= gmii_rx_er_d3;

    m_axis_tdata_q  <= m_axis_tdata_next;
    m_axis_tvalid_q <= m_axis_tvalid_next;
    m_axis_tlast_q  <= m_axis_tlast_next;
    m_axis_tuser_q  <= m_axis_tuser_next;

    if (reset_crc) begin
        crc_state <= 32'hFFFFFFFF;
    end else if (update_crc) begin
        crc_state <= crc_next;
    end
    
    if (!rst_n) begin
        s_idle_q     <= 1'b1;
        s_payload_q  <= 1'b0;
        s_wait_end_q <= 1'b0;

        m_axis_tvalid_q <= 1'b0;

        er_bad_frame_q  <= 1'b0;
        er_bad_fcs_q    <= 1'b0;

        gmii_rx_dv_d0 <= 1'b0;
        gmii_rx_dv_d1 <= 1'b0;
        gmii_rx_dv_d2 <= 1'b0;
        gmii_rx_dv_d3 <= 1'b0;
        gmii_rx_dv_d4 <= 1'b0;
    end
end

endmodule
`resetall