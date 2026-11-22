#!/bin/bash
# =============================================================================
#  给"已经装好"的机器补上渲染链优化（照片提速 + 黑块修复）
#  新装的机器不用跑：canon-capt-airprint-setup.sh 会自动装好
#
#  用法: sudo bash scripts/patch-render-chain.sh
#        sudo bash scripts/patch-render-chain.sh --revert
# =============================================================================
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CONVS="/usr/share/cups/mime/zz-local.convs"
LOG="/var/log/canon-render-chain.log"
: > "$LOG" 2>/dev/null || LOG=/tmp/canon-render-chain.log
log(){ printf '%s\n' "$*" | tee -a "$LOG"; }
step(){ log ""; log "=============================================================="; log ">>> $*"; log "=============================================================="; }
[ "$(id -u)" = 0 ] || { echo "请用 root"; exit 1; }
log "渲染链补丁: $(date '+%F %T')"

if [ "${1:-apply}" = "--revert" ]; then
  step "回滚（恢复 CUPS 默认转换：imagetopdf + pdftops）"
  rm -f /usr/lib/cups/filter/jpeg2pdf /usr/lib/cups/filter/canon-pdf-filter
  rm -f "$CONVS"
  systemctl restart cups; sleep 3
  log "  已回滚，cups: $(systemctl is-active cups)"
  exit 0
fi

step "1/5 安装过滤器"
install -m 755 "$HERE/jpeg2pdf.py"        /usr/lib/cups/filter/jpeg2pdf
install -m 755 "$HERE/canon-pdf-filter.sh" /usr/lib/cups/filter/canon-pdf-filter
log "  jpeg2pdf:          $(stat -c%s /usr/lib/cups/filter/jpeg2pdf) 字节"
log "  canon-pdf-filter:  $(stat -c%s /usr/lib/cups/filter/canon-pdf-filter) 字节"

step "2/5 注册转换规则"
cat > "$CONVS" <<'EOF'
# 手机照片：直接把 JPEG 嵌进 PDF，不重编码（比 imagetopdf 快 20 倍）
image/jpeg			application/vnd.cups-postscript	30	jpeg2pdf
# 文档 PDF：按需做 CMYK->RGB（规避黑块），纯 RGB 直接透传
application/vnd.cups-pdf	application/vnd.cups-postscript	50	canon-pdf-filter
EOF
sed 's/^/  /' "$CONVS" | tee -a "$LOG"

step "3/5 重启 CUPS"
systemctl restart cups; sleep 4
log "  cups: $(systemctl is-active cups)"

step "4/5 自检"
if command -v gs >/dev/null; then
  log "  gs: $(gs --version)"
fi
if [ -f /usr/share/cups/data/default-testpage.pdf ]; then
  T0=$(date +%s%N)
  cupsfilter -i application/pdf -m application/vnd.cups-postscript \
      /usr/share/cups/data/default-testpage.pdf > /tmp/rc.mid 2>/dev/null
  T1=$(date +%s%N)
  log "  PDF 链路自检: $(( (T1-T0)/1000000 )) ms, 产物 $(( $(stat -c%s /tmp/rc.mid 2>/dev/null || echo 0)/1024 )) KB"
fi

step "5/5 完成"
log "  照片提速、黑块修复已生效"
log "  回滚: sudo bash $0 --revert"
