--------------------------------------------------------------------------------
-- 文件名称 : axi_lite_slave.vhd
-- 模块功能 : AXI4-Lite 从机读写控制模块
--            将 AXI4-Lite 的五条通道（AW/W/B/AR/R）转换为一组简单的
--            "寄存器总线"：写脉冲 + 写地址 + 写数据 + 字节选通，读地址 + 读数据。
--            支持：独立 AW/W 握手、字节选通写、OKAY/SLVERR 响应、单笔未完成事务。
-- 参考     : Xilinx TEMAC《Management Interface》AXI4-Lite 时序（Table 12,
--            Figure 61/62）与 AMBA AXI4-Lite 协议（ARM IHI 0022）
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_lite_slave is
  generic (
    C_S_AXI_DATA_WIDTH : integer := 32;                    -- 数据位宽，固定 32
    C_S_AXI_ADDR_WIDTH : integer := 17;                    -- 与 MAC IP 的 s_axi_awaddr[16:0] 一致
    C_BASE_ADDR        : std_logic_vector(31 downto 0) := x"00000500"; -- 窗口基地址（字节地址）
    C_REG_IDX_WIDTH    : integer := 2                      -- 窗口内寄存器索引位宽：2 -> 4 个 32bit 寄存器
  );
  port (
    -- 全局信号
    s_axi_aclk    : in  std_logic;                                        -- AXI 时钟
    s_axi_aresetn : in  std_logic;                                        -- AXI 复位，低有效

    -- 写地址通道（Write Address Channel）
    s_axi_awaddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;

    -- 写数据通道（Write Data Channel）
    s_axi_wdata   : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_wstrb   : in  std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;

    -- 写响应通道（Write Response Channel）
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;

    -- 读地址通道（Read Address Channel）
    s_axi_araddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;

    -- 读数据通道（Read Data Channel）
    s_axi_rdata   : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;

    -- 用户寄存器总线（与内部寄存器块/用户逻辑对接）
    o_reg_wr_en   : out std_logic;                                        -- 写使能，单周期脉冲
    o_reg_wr_addr : out std_logic_vector(C_REG_IDX_WIDTH-1 downto 0);     -- 寄存器索引（字地址）
    o_reg_wr_data : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);  -- 写数据
    o_reg_wr_strb : out std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);-- 字节选通
    o_reg_rd_en   : out std_logic;                                        -- 读使能，单周期脉冲
    o_reg_rd_addr : out std_logic_vector(C_REG_IDX_WIDTH-1 downto 0);     -- 读地址（保持到下次读）
    i_reg_rd_data : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0)   -- 读数据（组合返回）
  );
end entity axi_lite_slave;

architecture rtl of axi_lite_slave is

  constant C_BYTES_PER_WORD : integer := C_S_AXI_DATA_WIDTH / 8;
  constant C_WINDOW_BYTES   : integer := (2 ** C_REG_IDX_WIDTH) * C_BYTES_PER_WORD;

  -- AXI 响应码
  constant AXI_OKAY   : std_logic_vector(1 downto 0) := "00";  -- 正常完成
  constant AXI_SLVERR : std_logic_vector(1 downto 0) := "10";  -- 从机错误（地址未映射）

  -- 读状态机
  type r_state_t is (R_IDLE, R_DATA, R_HOLD);

  -- 写通道寄存
  signal awready_r  : std_logic;
  signal wready_r   : std_logic;
  signal arready_r  : std_logic;
  signal bvalid_r   : std_logic;
  signal bresp_r    : std_logic_vector(1 downto 0);
  signal aw_captured : std_logic;
  signal w_captured  : std_logic;
  signal awaddr_r   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
  signal wdata_r    : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
  signal wstrb_r    : std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);

  -- 读通道寄存
  signal r_state    : r_state_t;
  signal rvalid_r   : std_logic;
  signal rdata_r    : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
  signal rresp_r    : std_logic_vector(1 downto 0);
  signal rerr_r     : std_logic;      -- 本次读访问地址非法

  ------------------------------------------------------------------------------
  -- 判断地址是否落在本从机窗口内（要求 4 字节对齐）
  ------------------------------------------------------------------------------
  function addr_hit (addr : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0))
    return boolean is
    variable a : unsigned(31 downto 0);
    variable b : unsigned(31 downto 0);
  begin
    a := resize(unsigned(addr), 32);
    b := unsigned(C_BASE_ADDR);
    return (a >= b) and (a < (b + C_WINDOW_BYTES)) and (a(1 downto 0) = "00");
  end function;

begin

  ------------------------------------------------------------------------------
  -- 写通道：AW/W 各自握手，两者齐备后产生一次写脉冲，随后给出 B 响应
  ------------------------------------------------------------------------------
  process (s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        awready_r    <= '1';
        wready_r     <= '1';
        bvalid_r     <= '0';
        bresp_r      <= AXI_OKAY;
        aw_captured  <= '0';
        w_captured   <= '0';
        awaddr_r     <= (others => '0');
        wdata_r      <= (others => '0');
        wstrb_r      <= (others => '0');
        o_reg_wr_en  <= '0';
        o_reg_wr_addr<= (others => '0');
        o_reg_wr_data<= (others => '0');
        o_reg_wr_strb<= (others => '0');
      else
        -- 写脉冲默认拉低（仅保持一个时钟周期）
        o_reg_wr_en <= '0';

        -- 1) 接收写地址
        if (awready_r = '1') and (s_axi_awvalid = '1') then
          awaddr_r   <= s_axi_awaddr;
          aw_captured<= '1';
          awready_r  <= '0';           -- 本笔事务完成前不再接收新地址
        end if;

        -- 2) 接收写数据
        if (wready_r = '1') and (s_axi_wvalid = '1') then
          wdata_r    <= s_axi_wdata;
          wstrb_r    <= s_axi_wstrb;
          w_captured <= '1';
          wready_r   <= '0';
        end if;

        -- 3) 地址与数据都到位：执行写，并给出写响应
        if (aw_captured = '1') and (w_captured = '1') and (bvalid_r = '0') then
          if addr_hit(awaddr_r) then
            o_reg_wr_en   <= '1';
            o_reg_wr_addr <= awaddr_r(C_REG_IDX_WIDTH+1 downto 2);
            o_reg_wr_data <= wdata_r;
            o_reg_wr_strb <= wstrb_r;
            bresp_r       <= AXI_OKAY;
          else
            bresp_r       <= AXI_SLVERR;    -- 地址未映射，不写寄存器
          end if;
          bvalid_r    <= '1';
          aw_captured <= '0';
          w_captured  <= '0';
        end if;

        -- 4) 主机接收写响应后，释放通道
        if (bvalid_r = '1') and (s_axi_bready = '1') then
          bvalid_r <= '0';
          awready_r<= '1';
          wready_r <= '1';
        end if;
      end if;
    end if;
  end process;

  s_axi_awready <= awready_r;
  s_axi_wready  <= wready_r;
  s_axi_bvalid  <= bvalid_r;
  s_axi_bresp   <= bresp_r;

  ------------------------------------------------------------------------------
  -- 读通道：AR -> 采样寄存器读数据 -> R 保持到握手完成
  ------------------------------------------------------------------------------
  process (s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        r_state       <= R_IDLE;
        arready_r     <= '1';
        rvalid_r      <= '0';
        rdata_r       <= (others => '0');
        rresp_r       <= AXI_OKAY;
        rerr_r        <= '0';
        o_reg_rd_en   <= '0';
        o_reg_rd_addr <= (others => '0');
      else
        o_reg_rd_en <= '0';

        case r_state is
          when R_IDLE =>
            arready_r <= '1';
            if (s_axi_arvalid = '1') and (arready_r = '1') then
              arready_r     <= '0';
              o_reg_rd_addr <= s_axi_araddr(C_REG_IDX_WIDTH+1 downto 2);
              o_reg_rd_en   <= '1';
              if addr_hit(s_axi_araddr) then
                rresp_r <= AXI_OKAY;
                rerr_r  <= '0';
              else
                rresp_r <= AXI_SLVERR;
                rerr_r  <= '1';
              end if;
              r_state <= R_DATA;
            end if;

          when R_DATA =>
            -- 此拍寄存器读数据已有效（地址在上拍给出），锁存并拉高 rvalid
            if rerr_r = '1' then
              rdata_r <= (others => '0');
            else
              rdata_r <= i_reg_rd_data;
            end if;
            rvalid_r <= '1';
            r_state  <= R_HOLD;

          when R_HOLD =>
            if s_axi_rready = '1' then
              rvalid_r <= '0';
              arready_r<= '1';
              r_state  <= R_IDLE;
            end if;

          when others =>
            r_state <= R_IDLE;
        end case;
      end if;
    end if;
  end process;

  s_axi_arready <= arready_r;
  s_axi_rvalid  <= rvalid_r;
  s_axi_rdata   <= rdata_r;
  s_axi_rresp   <= rresp_r;

end architecture rtl;
