--------------------------------------------------------------------------------
-- 文件名称 : mac_mgmt_regs.vhd
-- 模块功能 : 以太网 MAC 管理寄存器块（MDIO 寄存器区 0x0500 ~ 0x050C）
--            依据 Xilinx TEMAC 手册 Table 40 ~ Table 43 实现：
--              0x0500  MDIO Setup Word      —— bit6 使能，bit5:0 时钟分频（R/W）
--              0x0504  MDIO Control Word    —— PHYAD/REGAD/OP，bit11 启动（自清），bit7 就绪
--              0x0508  MDIO Write Data      —— bit15:0 写数据（R/W）
--              0x050C  MDIO Read Data       —— bit16 就绪，bit15:0 读数据（RO）
--            写操作支持 32bit 字节选通（wstrb），未实现位读回为 0。
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity mac_mgmt_regs is
  port (
    clk            : in  std_logic;                                   -- AXI 时钟
    rstn           : in  std_logic;                                   -- 同步复位，低有效

    -- 来自 axi_lite_slave 的寄存器总线
    i_wr_en        : in  std_logic;
    i_wr_addr      : in  std_logic_vector(1 downto 0);
    i_wr_data      : in  std_logic_vector(31 downto 0);
    i_wr_strb      : in  std_logic_vector(3 downto 0);
    i_rd_addr      : in  std_logic_vector(1 downto 0);
    o_rd_data      : out std_logic_vector(31 downto 0);

    -- MDIO 用户接口
    o_mdio_en      : out std_logic;                                   -- MDIO 使能（0x0500 bit6）
    o_mdio_clk_div : out std_logic_vector(5 downto 0);                -- MDC 分频（0x0500 bit5:0）
    o_mdio_start   : out std_logic;                                   -- 启动脉冲，单周期
    o_mdio_phyad   : out std_logic_vector(4 downto 0);                -- PHY 地址
    o_mdio_regad   : out std_logic_vector(4 downto 0);                -- 寄存器地址
    o_mdio_op      : out std_logic;                                   -- '0'=写, '1'=读
    o_mdio_wdata   : out std_logic_vector(15 downto 0);               -- 写数据
    i_mdio_ready   : in  std_logic;                                   -- MDIO 忙闲/就绪状态
    i_mdio_rdata   : in  std_logic_vector(15 downto 0)                -- MDIO 读回数据
  );
end entity mac_mgmt_regs;

architecture rtl of mac_mgmt_regs is

  -- 0x0500：MDIO Setup
  signal setup_en  : std_logic;
  signal setup_div : std_logic_vector(5 downto 0);

  -- 0x0504：MDIO Control（仅保存可写字段）
  signal ctrl_phyad : std_logic_vector(4 downto 0);
  signal ctrl_regad : std_logic_vector(4 downto 0);
  signal ctrl_op    : std_logic_vector(1 downto 0);   -- "00"=写, "01"=读
  signal start_r    : std_logic;

  -- 0x0508：MDIO Write Data
  signal wdata_r : std_logic_vector(15 downto 0);

begin

  ------------------------------------------------------------------------------
  -- 写寄存器（字节选通生效）
  ------------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rstn = '0' then
        setup_en   <= '0';
        setup_div  <= (others => '0');
        ctrl_phyad <= (others => '0');
        ctrl_regad <= (others => '0');
        ctrl_op    <= "00";
        wdata_r    <= (others => '0');
        start_r    <= '0';
      else
        start_r <= '0';                       -- 启动脉冲默认只有一个周期

        if i_wr_en = '1' then
          case i_wr_addr is
            -- 0x0500 MDIO Setup Word
            when "00" =>
              if i_wr_strb(0) = '1' then
                setup_en  <= i_wr_data(6);
                setup_div <= i_wr_data(5 downto 0);
              end if;

            -- 0x0504 MDIO Control Word
            when "01" =>
              if i_wr_strb(1) = '1' then
                ctrl_op <= i_wr_data(15 downto 14);       -- bit15:14 = TX_OP
              end if;
              if (i_wr_strb(1) = '1') and (i_wr_data(11) = '1') then
                start_r <= '1';                           -- 写 1 到 bit11 启动一次 MDIO 传输
              end if;
              if i_wr_strb(2) = '1' then
                ctrl_regad <= i_wr_data(20 downto 16);
              end if;
              if i_wr_strb(3) = '1' then
                ctrl_phyad <= i_wr_data(28 downto 24);
              end if;

            -- 0x0508 MDIO Write Data
            when "10" =>
              if i_wr_strb(0) = '1' then
                wdata_r(7 downto 0) <= i_wr_data(7 downto 0);
              end if;
              if i_wr_strb(1) = '1' then
                wdata_r(15 downto 8) <= i_wr_data(15 downto 8);
              end if;

            when others =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- 读寄存器（组合读，地址由 AXI 从机保持一拍）
  ------------------------------------------------------------------------------
  process (i_rd_addr, setup_en, setup_div, ctrl_phyad, ctrl_regad,
           ctrl_op, wdata_r, i_mdio_ready, i_mdio_rdata)
    variable v : std_logic_vector(31 downto 0);
  begin
    v := (others => '0');
    case i_rd_addr is
      when "00" =>                                   -- 0x0500 MDIO Setup Word
        v(6)          := setup_en;
        v(5 downto 0) := setup_div;

      when "01" =>                                   -- 0x0504 MDIO Control Word
        v(28 downto 24) := ctrl_phyad;
        v(20 downto 16) := ctrl_regad;
        v(15 downto 14) := ctrl_op;
        v(7)            := i_mdio_ready;             -- bit11 为自清启动位，读回 0

      when "10" =>                                   -- 0x0508 MDIO Write Data
        v(15 downto 0) := wdata_r;

      when others =>                                 -- 0x050C MDIO Read Data
        v(16)         := i_mdio_ready;
        v(15 downto 0):= i_mdio_rdata;

    end case;
    o_rd_data <= v;
  end process;

  ------------------------------------------------------------------------------
  -- 输出
  ------------------------------------------------------------------------------
  o_mdio_en      <= setup_en;
  o_mdio_clk_div <= setup_div;
  o_mdio_start   <= start_r;
  o_mdio_phyad   <= ctrl_phyad;
  o_mdio_regad   <= ctrl_regad;
  o_mdio_op      <= ctrl_op(0);
  o_mdio_wdata   <= wdata_r;

end architecture rtl;
