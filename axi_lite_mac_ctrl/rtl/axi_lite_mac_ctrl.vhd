--------------------------------------------------------------------------------
-- 文件名称 : axi_lite_mac_ctrl.vhd
-- 模块功能 : AXI4-Lite 管理接口顶层
--            由 AXI4-Lite 从机（axi_lite_slave）+ MAC 管理寄存器块（mac_mgmt_regs）
--            组成，实现 TEMAC 管理寄存器区 0x0500 ~ 0x050C 的读写访问，
--            并输出 MDIO 控制信号。窗口之外的地址返回 SLVERR。
--
-- 寄存器映射（与 TEMAC 手册 Table 40~43 一致）：
--   0x0500  MDIO Setup Word     R/W   bit6 = MDIO 使能, bit5:0 = MDC 分频
--   0x0504  MDIO Control Word   R/W   bit28:24 = PHYAD, bit20:16 = REGAD,
--                                     bit15:14 = OP(0 写/1 读), bit11 = 启动(写 1, 自清),
--                                     bit7 = MDIO Ready(只读)
--   0x0508  MDIO Write Data     R/W   bit15:0 = 写数据
--   0x050C  MDIO Read Data      RO    bit16 = MDIO Ready, bit15:0 = 读数据
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity axi_lite_mac_ctrl is
  generic (
    C_S_AXI_ADDR_WIDTH : integer := 17;    -- 与 MAC IP 的 s_axi_awaddr[16:0] 一致
    C_BASE_ADDR        : std_logic_vector(31 downto 0) := x"00000500"
  );
  port (
    -- AXI4-Lite 时钟与复位
    s_axi_aclk    : in  std_logic;
    s_axi_aresetn : in  std_logic;

    -- 写地址通道
    s_axi_awaddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;

    -- 写数据通道
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;

    -- 写响应通道
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;

    -- 读地址通道
    s_axi_araddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;

    -- 读数据通道
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;

    -- MDIO 用户接口
    o_mdio_en      : out std_logic;
    o_mdio_clk_div : out std_logic_vector(5 downto 0);
    o_mdio_start   : out std_logic;
    o_mdio_phyad   : out std_logic_vector(4 downto 0);
    o_mdio_regad   : out std_logic_vector(4 downto 0);
    o_mdio_op      : out std_logic;
    o_mdio_wdata   : out std_logic_vector(15 downto 0);
    i_mdio_ready   : in  std_logic;
    i_mdio_rdata   : in  std_logic_vector(15 downto 0)
  );
end entity axi_lite_mac_ctrl;

architecture rtl of axi_lite_mac_ctrl is

  signal reg_wr_en   : std_logic;
  signal reg_wr_addr : std_logic_vector(1 downto 0);
  signal reg_wr_data : std_logic_vector(31 downto 0);
  signal reg_wr_strb : std_logic_vector(3 downto 0);
  signal reg_rd_en   : std_logic;
  signal reg_rd_addr : std_logic_vector(1 downto 0);
  signal reg_rd_data : std_logic_vector(31 downto 0);

begin

  ------------------------------------------------------------------------------
  -- AXI4-Lite 从机：协议握手、地址译码、响应生成
  ------------------------------------------------------------------------------
  u_axi_slave : entity work.axi_lite_slave
    generic map (
      C_S_AXI_DATA_WIDTH => 32,
      C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH,
      C_BASE_ADDR        => C_BASE_ADDR,
      C_REG_IDX_WIDTH    => 2
    )
    port map (
      s_axi_aclk    => s_axi_aclk,
      s_axi_aresetn => s_axi_aresetn,
      s_axi_awaddr  => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata   => s_axi_wdata,
      s_axi_wstrb   => s_axi_wstrb,
      s_axi_wvalid  => s_axi_wvalid,
      s_axi_wready  => s_axi_wready,
      s_axi_bresp   => s_axi_bresp,
      s_axi_bvalid  => s_axi_bvalid,
      s_axi_bready  => s_axi_bready,
      s_axi_araddr  => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata   => s_axi_rdata,
      s_axi_rresp   => s_axi_rresp,
      s_axi_rvalid  => s_axi_rvalid,
      s_axi_rready  => s_axi_rready,
      o_reg_wr_en   => reg_wr_en,
      o_reg_wr_addr => reg_wr_addr,
      o_reg_wr_data => reg_wr_data,
      o_reg_wr_strb => reg_wr_strb,
      o_reg_rd_en   => reg_rd_en,
      o_reg_rd_addr => reg_rd_addr,
      i_reg_rd_data => reg_rd_data
    );

  ------------------------------------------------------------------------------
  -- MAC 管理寄存器块：0x0500 ~ 0x050C
  ------------------------------------------------------------------------------
  u_mac_regs : entity work.mac_mgmt_regs
    port map (
      clk            => s_axi_aclk,
      rstn           => s_axi_aresetn,
      i_wr_en        => reg_wr_en,
      i_wr_addr      => reg_wr_addr,
      i_wr_data      => reg_wr_data,
      i_wr_strb      => reg_wr_strb,
      i_rd_addr      => reg_rd_addr,
      o_rd_data      => reg_rd_data,
      o_mdio_en      => o_mdio_en,
      o_mdio_clk_div => o_mdio_clk_div,
      o_mdio_start   => o_mdio_start,
      o_mdio_phyad   => o_mdio_phyad,
      o_mdio_regad   => o_mdio_regad,
      o_mdio_op      => o_mdio_op,
      o_mdio_wdata   => o_mdio_wdata,
      i_mdio_ready   => i_mdio_ready,
      i_mdio_rdata   => i_mdio_rdata
    );

end architecture rtl;
