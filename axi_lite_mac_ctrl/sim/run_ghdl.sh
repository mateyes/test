#!/bin/bash
# ------------------------------------------------------------------------------
# GHDL 仿真脚本：分析 -> 精化 -> 运行 -> 输出波形
# 用法：bash sim/run_ghdl.sh
# ------------------------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."

STD=08
WORK=sim/work
mkdir -p sim

# 清理旧的分析结果
rm -rf "$WORK" sim/wave.vcd
mkdir -p "$WORK"

echo "[1/3] 分析 VHDL 源码 ..."
ghdl -a --std=$STD --workdir="$WORK" \
     rtl/axi_lite_slave.vhd \
     rtl/mac_mgmt_regs.vhd \
     rtl/axi_lite_mac_ctrl.vhd \
     tb/tb_axi_lite_mac_ctrl.vhd

echo "[2/3] 精化顶层 ..."
ghdl -e --std=$STD --workdir="$WORK" tb_axi_lite_mac_ctrl

echo "[3/3] 运行仿真（输出 VCD 波形到 sim/wave.vcd）..."
ghdl -r --std=$STD --workdir="$WORK" tb_axi_lite_mac_ctrl \
     --vcd=sim/wave.vcd --stop-time=100us --assert-level=error 2>&1 | tee sim/sim_log.txt

echo "仿真结束：波形 sim/wave.vcd（可用 GTKWave 打开）"
