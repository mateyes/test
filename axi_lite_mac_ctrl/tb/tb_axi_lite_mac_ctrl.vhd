--------------------------------------------------------------------------------
-- 文件名称 : tb_axi_lite_mac_ctrl.vhd
-- 测试对象 : axi_lite_mac_ctrl（AXI4-Lite 管理接口 + MDIO 寄存器块）
-- 测试内容 : 1) 复位状态
--            2) 寄存器写后读（0x0500 / 0x0508）
--            3) 字节选通写（wstrb）
--            4) MDIO Control 写：PHYAD/REGAD/OP 与 bit11 启动脉冲（自清）
--            5) MDIO Read Data 只读、Ready 状态映射
--            6) 未映射地址访问返回 SLVERR
--            7) 全 0 字节选通不改变寄存器
-- 结果判定 : 所有检查通过打印 "ALL TESTS PASSED"，否则打印失败并结束仿真
-- 说明     : GHDL 不支持字符串中的 UTF-8 汉字，故打印信息使用英文
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axi_lite_mac_ctrl is
end entity tb_axi_lite_mac_ctrl;

architecture sim of tb_axi_lite_mac_ctrl is

  constant CLK_PERIOD  : time := 10 ns;
  constant AXI_OKAY    : std_logic_vector(1 downto 0) := "00";
  constant AXI_SLVERR  : std_logic_vector(1 downto 0) := "10";

  -- 地址常量（17bit，与 MAC IP 一致）
  constant A_SETUP  : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#00500#, 17));
  constant A_CTRL   : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#00504#, 17));
  constant A_WDATA  : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#00508#, 17));
  constant A_RDATA  : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#0050C#, 17));
  constant A_WINOUT : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#00518#, 17)); -- 窗口外
  constant A_OTHER  : std_logic_vector(16 downto 0) := std_logic_vector(to_unsigned(16#00600#, 17)); -- 未映射

  -- AXI 主机输出 / 从机响应，用记录聚合，便于作为过程参数
  type axi_req_t is record
    awaddr  : std_logic_vector(16 downto 0);
    awvalid : std_logic;
    wdata   : std_logic_vector(31 downto 0);
    wstrb   : std_logic_vector(3 downto 0);
    wvalid  : std_logic;
    bready  : std_logic;
    araddr  : std_logic_vector(16 downto 0);
    arvalid : std_logic;
    rready  : std_logic;
  end record;

  type axi_rsp_t is record
    awready : std_logic;
    wready  : std_logic;
    bresp   : std_logic_vector(1 downto 0);
    bvalid  : std_logic;
    arready : std_logic;
    rdata   : std_logic_vector(31 downto 0);
    rresp   : std_logic_vector(1 downto 0);
    rvalid  : std_logic;
  end record;

  signal clk   : std_logic := '0';
  signal rstn  : std_logic := '0';

  signal m : axi_req_t := (awaddr => (others => '0'), awvalid => '0',
                           wdata => (others => '0'), wstrb => (others => '0'),
                           wvalid => '0', bready => '0',
                           araddr => (others => '0'), arvalid => '0', rready => '0');
  signal s : axi_rsp_t;

  -- MDIO
  signal mdio_en      : std_logic;
  signal mdio_clk_div : std_logic_vector(5 downto 0);
  signal mdio_start   : std_logic;
  signal mdio_phyad   : std_logic_vector(4 downto 0);
  signal mdio_regad   : std_logic_vector(4 downto 0);
  signal mdio_op      : std_logic;
  signal mdio_wdata   : std_logic_vector(15 downto 0);
  signal mdio_ready   : std_logic := '1';
  signal mdio_rdata   : std_logic_vector(15 downto 0) := x"1234";

  signal start_cnt : integer := 0;

  ------------------------------------------------------------------------------
  -- 计数器（受保护类型，保证同一 delta 内多次调用不丢计数）
  ------------------------------------------------------------------------------
  type counter_t is protected
    procedure inc_check;
    procedure inc_err;
    impure function checks return integer;
    impure function errors return integer;
  end protected counter_t;

  type counter_t is protected body
    variable c : integer := 0;
    variable e : integer := 0;
    procedure inc_check is
    begin
      c := c + 1;
    end procedure;
    procedure inc_err is
    begin
      e := e + 1;
    end procedure;
    impure function checks return integer is
    begin
      return c;
    end function;
    impure function errors return integer is
    begin
      return e;
    end function;
  end protected body counter_t;

  shared variable cnt : counter_t;

  ------------------------------------------------------------------------------
  -- 检查
  ------------------------------------------------------------------------------
  procedure check (cond : boolean; tag : string) is
  begin
    cnt.inc_check;
    if cond then
      report "[PASS] " & tag severity note;
    else
      report "[FAIL] " & tag severity error;
      cnt.inc_err;
    end if;
  end procedure;

  ------------------------------------------------------------------------------
  -- AXI 写事务：AW 与 W 同时发起，等待 B 响应
  ------------------------------------------------------------------------------
  procedure axi_write (
    signal clk        : in    std_logic;
    signal m          : inout axi_req_t;
    signal s          : in    axi_rsp_t;
    constant addr     : in    std_logic_vector(16 downto 0);
    constant data     : in    std_logic_vector(31 downto 0);
    constant strb     : in    std_logic_vector(3 downto 0);
    constant exp_resp : in    std_logic_vector(1 downto 0);
    constant tag      : in    string) is
  begin
    wait until falling_edge(clk);
    m.awaddr  <= addr;
    m.awvalid <= '1';
    m.wdata   <= data;
    m.wstrb   <= strb;
    m.wvalid  <= '1';

    -- AW / W 握手
    wait until rising_edge(clk);
    m.awvalid <= '0';
    m.wvalid  <= '0';

    -- 等待写响应
    loop
      wait until rising_edge(clk);
      exit when s.bvalid = '1';
    end loop;

    check(s.bresp = exp_resp, tag & " (resp)");

    m.bready <= '1';
    wait until rising_edge(clk);
    m.bready <= '0';

    -- 等待通道回到空闲
    loop
      wait until rising_edge(clk);
      exit when s.awready = '1';
    end loop;
  end procedure;

  ------------------------------------------------------------------------------
  -- AXI 写事务：先发 AW，延迟若干拍再发 W（验证 AW/W 通道独立握手）
  ------------------------------------------------------------------------------
  procedure axi_write_split (
    signal clk        : in    std_logic;
    signal m          : inout axi_req_t;
    signal s          : in    axi_rsp_t;
    constant addr     : in    std_logic_vector(16 downto 0);
    constant data     : in    std_logic_vector(31 downto 0);
    constant strb     : in    std_logic_vector(3 downto 0);
    constant exp_resp : in    std_logic_vector(1 downto 0);
    constant tag      : in    string) is
  begin
    wait until falling_edge(clk);
    m.awaddr  <= addr;
    m.awvalid <= '1';

    wait until rising_edge(clk);          -- AW 握手
    m.awvalid <= '0';

    wait for 3 * CLK_PERIOD;              -- 写数据延后到达

    wait until falling_edge(clk);
    m.wdata   <= data;
    m.wstrb   <= strb;
    m.wvalid  <= '1';

    wait until rising_edge(clk);          -- W 握手
    m.wvalid  <= '0';

    loop
      wait until rising_edge(clk);
      exit when s.bvalid = '1';
    end loop;

    check(s.bresp = exp_resp, tag & " (resp)");

    m.bready <= '1';
    wait until rising_edge(clk);
    m.bready <= '0';

    loop
      wait until rising_edge(clk);
      exit when s.awready = '1' and s.wready = '1';
    end loop;
  end procedure;

  ------------------------------------------------------------------------------
  -- AXI 读事务
  ------------------------------------------------------------------------------
  procedure axi_read (
    signal clk        : in    std_logic;
    signal m          : inout axi_req_t;
    signal s          : in    axi_rsp_t;
    constant addr     : in    std_logic_vector(16 downto 0);
    constant exp_data : in    std_logic_vector(31 downto 0);
    constant exp_resp : in    std_logic_vector(1 downto 0);
    constant tag      : in    string) is
    variable vd : std_logic_vector(31 downto 0);
    variable vr : std_logic_vector(1 downto 0);
  begin
    wait until falling_edge(clk);
    m.araddr  <= addr;
    m.arvalid <= '1';

    wait until rising_edge(clk);
    m.arvalid <= '0';

    -- 等待读数据
    loop
      wait until rising_edge(clk);
      exit when s.rvalid = '1';
    end loop;

    vd := s.rdata;
    vr := s.rresp;

    check(vr = exp_resp, tag & " (resp)");
    if exp_resp = AXI_OKAY then
      check(vd = exp_data, tag & " (data)");
    end if;

    m.rready <= '1';
    wait until rising_edge(clk);
    m.rready <= '0';

    loop
      wait until rising_edge(clk);
      exit when s.arready = '1';
    end loop;
  end procedure;

begin

  -- 时钟
  clk <= not clk after CLK_PERIOD / 2;

  -- MDIO 启动脉冲计数（验证单周期、自清）
  process (clk)
  begin
    if rising_edge(clk) then
      if mdio_start = '1' then
        start_cnt <= start_cnt + 1;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- 主激励
  ------------------------------------------------------------------------------
  process
  begin
    -- 初始状态
    rstn <= '0';
    wait for 5 * CLK_PERIOD;

    -- 0. 复位检查
    check(s.awready = '1' and s.wready = '1' and s.arready = '1',
          "reset: all channels ready");
    check(s.bvalid = '0' and s.rvalid = '0', "reset: no pending response");

    rstn <= '1';
    wait until rising_edge(clk);

    -- 1. 写 / 读 MDIO Setup（0x0500）：使能 + 分频 = 7
    axi_write(clk, m, s, A_SETUP, x"00000047", "1111", AXI_OKAY, "write 0x0500 Setup");
    axi_read (clk, m, s, A_SETUP, x"00000047", AXI_OKAY, "read 0x0500 Setup");
    check(mdio_en = '1' and mdio_clk_div = "000111", "MDIO enable & clk divider");

    -- 2. 写 / 读 MDIO Write Data（0x0508）
    axi_write(clk, m, s, A_WDATA, x"0000A55A", "1111", AXI_OKAY, "write 0x0508 WriteData");
    axi_read (clk, m, s, A_WDATA, x"0000A55A", AXI_OKAY, "read 0x0508 WriteData");
    check(mdio_wdata = x"A55A", "MDIO write data output");

    -- 3. 字节选通：只写 Byte1（bit15:8），低位保持不变
    axi_write(clk, m, s, A_WDATA, x"00001200", "0010", AXI_OKAY, "byte-strobe write 0x0508");
    axi_read (clk, m, s, A_WDATA, x"0000125A", AXI_OKAY, "read-back after byte strobe");

    -- 4. 写 MDIO Control（0x0504）：PHYAD=5, REGAD=0x11, OP=1(读), 启动
    --    0x0511_4800 = PHYAD(5)<<24 | REGAD(0x11)<<16 | OP(01)<<14 | 启动位(1)<<11
    axi_write(clk, m, s, A_CTRL, x"05114800", "1111", AXI_OKAY, "write 0x0504 Control + start");
    check(start_cnt = 1, "start pulse generated once");
    check(mdio_phyad = "00101" and mdio_regad = "10001" and mdio_op = '1',
          "PHYAD/REGAD/OP outputs");
    axi_read (clk, m, s, A_CTRL, x"05114080", AXI_OKAY, "read 0x0504 (start self-clear)");

    -- 5. 不写启动位时不应产生脉冲
    axi_write(clk, m, s, A_CTRL, x"05110000", "1111", AXI_OKAY, "write 0x0504 without start");
    check(start_cnt = 1, "no start pulse without initiate");
    axi_read (clk, m, s, A_CTRL, x"05110080", AXI_OKAY, "read 0x0504 (OP=write)");

    -- 6. 读 MDIO Read Data（0x050C）：Ready=1 + 数据 0x1234
    axi_read (clk, m, s, A_RDATA, x"00011234", AXI_OKAY, "read 0x050C ReadData");

    -- 7. Ready=0 时的状态映射
    mdio_ready <= '0';
    wait until rising_edge(clk);
    axi_read (clk, m, s, A_RDATA, x"00001234", AXI_OKAY, "read 0x050C when ready=0");
    axi_read (clk, m, s, A_CTRL,  x"05110000", AXI_OKAY, "read 0x0504 when ready=0");
    mdio_ready <= '1';
    wait until rising_edge(clk);

    -- 8. 未映射地址：写/读均返回 SLVERR
    axi_write(clk, m, s, A_OTHER,  x"00000001", "1111", AXI_SLVERR, "write unmapped 0x0600");
    axi_read (clk, m, s, A_OTHER,  x"00000000", AXI_SLVERR, "read unmapped 0x0600");
    axi_write(clk, m, s, A_WINOUT, x"00000001", "1111", AXI_SLVERR, "write outside window 0x0518");
    axi_read (clk, m, s, A_WINOUT, x"00000000", AXI_SLVERR, "read outside window 0x0518");

    -- 9. 字节选通全 0：寄存器内容保持不变
    axi_write(clk, m, s, A_SETUP, x"00000000", "0000", AXI_OKAY, "write 0x0500 with wstrb=0000");
    axi_read (clk, m, s, A_SETUP, x"00000047", AXI_OKAY, "confirm 0x0500 unchanged");

    -- 10. AW/W 分离到达的写事务（验证通道独立性）
    axi_write_split(clk, m, s, A_WDATA, x"0000C3D4", "1111", AXI_OKAY,
                    "split AW/W write 0x0508");
    axi_read (clk, m, s, A_WDATA, x"0000C3D4", AXI_OKAY, "read after split write");

    -- 结果汇总
    wait for 5 * CLK_PERIOD;
    if cnt.errors = 0 then
      report "=============== ALL TESTS PASSED (" &
             integer'image(cnt.checks) & " checks) ===============" severity note;
    else
      report "=============== TEST FAILED: " & integer'image(cnt.errors) &
             " error(s) ===============" severity failure;
    end if;

    wait;
  end process;

  ------------------------------------------------------------------------------
  -- 被测模块
  ------------------------------------------------------------------------------
  u_dut : entity work.axi_lite_mac_ctrl
    generic map (
      C_S_AXI_ADDR_WIDTH => 17,
      C_BASE_ADDR        => x"00000500"
    )
    port map (
      s_axi_aclk    => clk,
      s_axi_aresetn => rstn,
      s_axi_awaddr  => m.awaddr,
      s_axi_awvalid => m.awvalid,
      s_axi_awready => s.awready,
      s_axi_wdata   => m.wdata,
      s_axi_wstrb   => m.wstrb,
      s_axi_wvalid  => m.wvalid,
      s_axi_wready  => s.wready,
      s_axi_bresp   => s.bresp,
      s_axi_bvalid  => s.bvalid,
      s_axi_bready  => m.bready,
      s_axi_araddr  => m.araddr,
      s_axi_arvalid => m.arvalid,
      s_axi_arready => s.arready,
      s_axi_rdata   => s.rdata,
      s_axi_rresp   => s.rresp,
      s_axi_rvalid  => s.rvalid,
      s_axi_rready  => m.rready,
      o_mdio_en      => mdio_en,
      o_mdio_clk_div => mdio_clk_div,
      o_mdio_start   => mdio_start,
      o_mdio_phyad   => mdio_phyad,
      o_mdio_regad   => mdio_regad,
      o_mdio_op      => mdio_op,
      o_mdio_wdata   => mdio_wdata,
      i_mdio_ready   => mdio_ready,
      i_mdio_rdata   => mdio_rdata
    );

end architecture sim;
