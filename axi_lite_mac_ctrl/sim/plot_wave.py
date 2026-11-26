#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 GHDL 生成的 wave.vcd 中提取 AXI4-Lite 关键信号，绘制握手时序图。
用法：python3 sim/plot_wave.py [wave.vcd] [out.png]"""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

vcd_path = sys.argv[1] if len(sys.argv) > 1 else "sim/wave.vcd"
out_path = sys.argv[2] if len(sys.argv) > 2 else "sim/waveform.png"

want = ["s_axi_awvalid", "s_axi_awready", "s_axi_wvalid", "s_axi_wready",
        "s_axi_bvalid", "s_axi_bready", "s_axi_arvalid", "s_axi_arready",
        "s_axi_rvalid", "s_axi_rready", "s_axi_awaddr[16:0]",
        "s_axi_wdata[31:0]", "s_axi_rdata[31:0]", "o_mdio_start"]
clk_name = "s_axi_aclk"

lines = open(vcd_path, errors="ignore").read().splitlines()

scope, decls = [], []          # decls: (scope_tuple, name, vid)
for ln in lines:
    t = ln.strip()
    if t.startswith("$scope"):
        scope.append(t.split()[2])
    elif t.startswith("$upscope"):
        scope.pop()
    elif t.startswith("$var"):
        p = t.split()
        decls.append((tuple(scope), p[4], p[3]))

def pick(name):
    """优先选择 u_dut 实例内的信号"""
    cands = [(sc, vid) for sc, n, vid in decls if n == name]
    for sc, vid in cands:
        if "u_dut" in sc:
            return vid
    return cands[0][1] if cands else None

sig_ids = {n: pick(n) for n in want}
sig_ids[clk_name] = pick(clk_name)
id2name = {vid: n for n, vid in sig_ids.items() if vid}
trans = {n: [] for n in id2name.values()}

cur, t_ns = {vid: "x" for vid in id2name}, 0.0
for t in lines:
    if not t:
        continue
    if t[0] == "#":
        t_ns = int(t[1:]) / 1e6          # fs -> ns
        continue
    if t[0] in "01xzXZ" and len(t) >= 2 and t[1:] in id2name:
        vid, val = t[1:], t[0]
        if cur[vid] != val:
            cur[vid] = val
            trans[id2name[vid]].append((t_ns, val))
    elif t[0] in "bB" and " " in t:
        val, vid = t[1:].split()[:2]
        if vid in id2name and cur[vid] != val:
            cur[vid] = val
            trans[id2name[vid]].append((t_ns, val))

def val_at(name, t):
    v = "x"
    for tt, vv in trans[name]:
        if tt <= t:
            v = vv
        else:
            break
    return v

def to_int(v):
    try:
        return int(v, 2)
    except Exception:
        return None

T0, T1 = 40.0, 420.0
rows = ["s_axi_awvalid", "s_axi_awready", "s_axi_wvalid", "s_axi_wready",
        "s_axi_bvalid", "s_axi_bready",
        "s_axi_arvalid", "s_axi_arready", "s_axi_rvalid", "s_axi_rready"]

fig, (axc, ax) = plt.subplots(2, 1, figsize=(11.5, 6.4), sharex=True,
                              gridspec_kw={"height_ratios": [0.55, 4.6]})
fig.patch.set_facecolor("white")

# 时钟
ts = [T0] + [tt for tt, _ in trans[clk_name] if T0 < tt < T1] + [T1]
vs = [1.0 if val_at(clk_name, t) == "1" else 0.0 for t in ts]
axc.step(ts, vs, where="post", color="#1f3b73", lw=1.3)
axc.set_ylim(-0.25, 1.45)
axc.set_yticks([0.2, 1.0])
axc.set_yticklabels(["0", "1"])
axc.set_ylabel("ACLK", rotation=0, ha="right", va="center")
axc.set_title("AXI4-Lite handshake: 0x0500 write / read-back (GHDL simulation)",
              fontsize=11)
for sp in ["top", "right", "left"]:
    axc.spines[sp].set_visible(False)

for i, n in enumerate(rows):
    y = len(rows) - i
    ts = [T0] + [tt for tt, _ in trans[n] if T0 < tt < T1] + [T1]
    vs = [1.0 if val_at(n, t) == "1" else 0.0 for t in ts]
    color = "#1f77b4" if n.endswith("valid") else "#c0392b"
    ax.step(ts, [y + 0.16 * v for v in vs], where="post", color=color, lw=1.5)
    ax.text(T0 - 2.5, y + 0.08, n.replace("s_axi_", ""), ha="right", va="center",
            fontsize=8, family="monospace")

ax.set_ylim(0.2, len(rows) + 1.0)
ax.set_yticks([])
ax.set_xlim(T0, T1)
ax.set_xlabel("time (ns)")
for sp in ["top", "right", "left"]:
    ax.spines[sp].set_visible(False)
ax.grid(axis="x", ls=":", color="#cccccc")

def annotate(name, fmt, ytext, xoff=1.5, yoff=0.9):
    seen = set()
    for tt, vv in trans[name]:
        if T0 < tt < T1:
            iv = to_int(vv)
            if iv is None or (iv, ) in seen:
                continue
            seen.add((iv, ))
            ax.annotate(fmt(iv), xy=(tt, ytext), xytext=(tt + xoff, ytext + yoff),
                        fontsize=7.2, color="#333333",
                        arrowprops=dict(arrowstyle="-", lw=0.5, color="#999999"))

annotate("s_axi_awaddr[16:0]", lambda v: f"awaddr=0x{v:03X}", len(rows) + 0.05, 2, 0.55)
annotate("s_axi_wdata[31:0]", lambda v: f"wdata=0x{v:08X}", len(rows) - 2.15, 2, -0.8)
annotate("s_axi_rdata[31:0]", lambda v: f"rdata=0x{v:08X}", len(rows) - 8.15, 2, 0.45)

plt.tight_layout()
plt.savefig(out_path, dpi=170, bbox_inches="tight")
print("saved", out_path, "| signals:", [k for k in sig_ids.values() if k])
