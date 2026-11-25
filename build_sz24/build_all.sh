#!/bin/bash
set -e
cd /workspace/build_sz24

# 1. 无字背景
rm -rf bg && mkdir -p bg
DECK_MODE=bg python3 build_deck.py
soffice --headless --convert-to pdf --outdir . bg_deck.pptx >/dev/null 2>&1
pdftoppm -png -r 200 -sep "" bg_deck.pdf bg/page
python3 - <<'EOF'
import glob, os
for f in glob.glob('bg/page*.png'):
    n = int(''.join(c for c in os.path.basename(f) if c.isdigit()))
    os.rename(f, f'bg/{n:02d}.png')
print('bg:', sorted(os.listdir('bg')))
EOF

# 2. 标准矢量版 pptx + PDF
DECK_MODE=full python3 build_deck.py
rm -f "神舟二十四号_3.5小时太空穿针.pdf"
soffice --headless --convert-to pdf --outdir . "神舟二十四号_3.5小时太空穿针.pptx" >/dev/null 2>&1

# 3. 兼容 Office 2003 的 .ppt（背景图 + 可编辑文字）
DECK_MODE=final python3 build_deck.py
rm -f "神舟二十四号_3.5小时太空穿针.ppt"
soffice --headless --convert-to ppt --outdir . ppt2003_source.pptx >/dev/null 2>&1

echo done
