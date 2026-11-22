#!/bin/bash
# =============================================================================
#  Canon CAPT 打印机 → Linux 网络打印 + AirPrint 一键部署
#  适用: fnOS / Debian 12 / CUPS 2.4 / x86_64
#  实测机型: Canon i-SENSYS LBP7010C (USB 04a9:271c)
#  用法: sudo bash canon-capt-airprint-setup.sh
#
#  说明: 本脚本整合了实际排障中验证过的全部步骤，可重复执行（幂等）。
#        其他 CAPT 机型请修改 QUEUE / PPD_NAME / USB_PID 三个变量。
# =============================================================================
set -uo pipefail

# ---------------------------------------------------------------- 可调参数
QUEUE="LBP7010C"                       # CUPS 队列名（也是 AirPrint 显示名的基础）
MODEL="Canon LBP7010C"                 # 显示用型号
USB_VID="04a9"                         # Canon
USB_PID="271c"                         # LBP7010C / LBP7018C
DEV_LINK="/dev/usb/lbp7010c"           # 稳定的设备软链接
PPD_NAME="CNCUPSLBP7010CCAPTJ.ppd"     # 驱动包内 PPD 文件名
CCP_PORT=59687                         # ccpd 数据端口（Canon 官方值）
LOG="/var/log/canon-capt-setup.log"
WORKDIR="/opt/canon-capt"
DRV_URL="https://gdlp01.c-wss.com/gds/6/0100004596/05/linux-capt-drv-v271-uken.tar.gz"

ok=0; bad=0
log(){ printf '%s\n' "$*" | tee -a "$LOG"; }
cap(){ log "\$ $*"; "$@" 2>&1 | sed 's/^/  /' | tee -a "$LOG"; log "  (exit=${PIPESTATUS[0]})"; }
step(){ log ""; log "=============================================================="; log ">>> $*"; log "=============================================================="; }
pass(){ ok=$((ok+1)); log "  [ OK ] $*"; }
warn(){ log "  [WARN] $*"; }
fail(){ bad=$((bad+1)); log "  [FAIL] $*"; }

: > "$LOG"
log "Canon CAPT 部署开始: $(date '+%F %T')  $(hostname) $(uname -r)"

# ---------------------------------------------------------------- 0. 前置检查
step "0/10 前置检查"
[ "$(id -u)" = 0 ] || { log "必须 root 运行"; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { log "CAPT 2.71 只提供 x86_64/amd64 构建，当前 $(uname -m) 不支持"; exit 1; }
command -v lpadmin >/dev/null && command -v cupsd >/dev/null || { log "缺少 CUPS"; exit 1; }
if lsusb | grep -q "$USB_VID:$USB_PID"; then pass "检测到打印机 $USB_VID:$USB_PID"; else warn "lsusb 未看到打印机，请确认已开机并接在 NAS 上"; fi
LANIP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
[ -n "$LANIP" ] || LANIP=$(hostname -I | awk '{print $1}')
log "  局域网地址: ${LANIP:-未知}"

# ---------------------------------------------------------------- 1. 驱动
step "1/10 下载并安装 Canon CAPT 2.71 (amd64)"
mkdir -p "$WORKDIR"
if [ ! -f "$WORKDIR/drv/linux-capt-drv-v271-uken.tar.gz" ]; then
  log "  下载驱动包（约 122MB）..."
  curl -# -L --retry 3 -m 900 -o "$WORKDIR/drv.tar.gz" "$DRV_URL" 2>&1 | tail -1
  mkdir -p "$WORKDIR/drv" && tar xzf "$WORKDIR/drv.tar.gz" -C "$WORKDIR/drv" --strip-components=1 || fail "驱动包解压失败"
else
  pass "驱动包已存在，跳过下载"
fi
DEBDIR="$WORKDIR/drv/64-bit_Driver/Debian"
if [ -f /usr/lib/cups/filter/pstocapt3 ] && [ -x /usr/sbin/ccpd ]; then
  pass "CAPT 驱动已安装"
else
  dpkg -i --force-depends "$DEBDIR/cndrvcups-common_3.21-1_amd64.deb" >>"$LOG" 2>&1
  dpkg -i --force-depends "$DEBDIR/cndrvcups-capt_2.71-1_amd64.deb"    >>"$LOG" 2>&1
  ldconfig
  [ -x /usr/lib/cups/filter/pstocapt3 ] && pass "dpkg 安装完成" || fail "驱动安装失败，查看 $LOG"
fi

# ---------------------------------------------------------------- 2. 32 位运行库
step "2/10 安装 i386 运行库（64 位包内部的助手是 32 位的）"
dpkg --add-architecture i386
apt-get update -qq >>"$LOG" 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libxml2:i386 libpopt0:i386 >>"$LOG" 2>&1
cat > /etc/ld.so.conf.d/zz-i386-multiarch.conf <<'EOF'
/lib/i386-linux-gnu
/usr/lib/i386-linux-gnu
EOF
ldconfig
MISS=$(ldd /usr/bin/captmoncnacb 2>/dev/null | grep -c 'not found')
[ "$MISS" = "0" ] && pass "32 位助手依赖完整" || fail "captmoncnacb 仍缺 $MISS 个库"

# ---------------------------------------------------------------- 3. udev 规则
step "3/10 udev: 固定设备名 + 禁止 USB 自动挂起"
cat > /etc/udev/rules.d/50-canon-lbp-no-autosuspend.rules <<RULE
# Canon CAPT 打印机禁止 USB 自动挂起（否则 ccpd 持有的句柄会失效）
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_VID", ATTR{idProduct}=="$USB_PID", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$USB_VID", ATTR{idProduct}=="$USB_PID", TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="-1"
RULE
cat > /etc/udev/rules.d/51-canon-lbp-link.rules <<RULE
# 按 VID/PID 生成稳定设备名，避免多台打印机争抢 lp0/lp1
SUBSYSTEM=="usbmisc", KERNEL=="lp*", ATTRS{idVendor}=="$USB_VID", ATTRS{idProduct}=="$USB_PID", SYMLINK+="usb/$(basename "$DEV_LINK")"
RULE
mkdir -p /usr/share/cups/usb
printf '# Canon CAPT 由 ccpd 驱动，阻止 CUPS usb 后端抢占\n%s %s no-reattach\n' "0x$USB_VID" "0x$USB_PID" \
  > /usr/share/cups/usb/capt-printers.usb-quirks
udevadm control --reload-rules
udevadm trigger --subsystem-match=usbmisc
udevadm trigger --subsystem-match=usb
sleep 2
[ -e "$DEV_LINK" ] && pass "$DEV_LINK -> $(readlink -f "$DEV_LINK")" || warn "udev 软链接尚未生成（重新插拔打印机后会生成）"

# ---------------------------------------------------------------- 4. USB 复位工具
step "4/10 安装 USB 复位工具（清 USB 端点 stall）"
cat > /usr/local/sbin/canon-usbreset <<'PYEOF'
#!/usr/bin/env python3
"""对 Canon CAPT 打印机发送 USBDEVFS_RESET，清除 stalled 端点。"""
import fcntl, glob, os, sys, time
USBDEVFS_RESET = 0x5514
VID, PID = os.environ.get("CANON_VID", "04a9"), os.environ.get("CANON_PID", "271c")
found = False
for f in glob.glob('/sys/bus/usb/devices/*/idVendor'):
    d = os.path.dirname(f)
    try:
        if (open(d + '/idVendor').read().strip(), open(d + '/idProduct').read().strip()) != (VID, PID):
            continue
    except OSError:
        continue
    found = True
    bus = int(open(d + '/busnum').read().strip())
    dev = int(open(d + '/devnum').read().strip())
    node = f'/dev/bus/usb/{bus:03d}/{dev:03d}'
    try:
        fd = os.open(node, os.O_RDWR)
        fcntl.ioctl(fd, USBDEVFS_RESET)
        os.close(fd)
        print(f'已复位 {node}')
    except OSError as e:
        print(f'复位 {node} 失败: {e}', file=sys.stderr)
    time.sleep(1)
if not found:
    print('未找到目标 USB 设备', file=sys.stderr)
sys.exit(0 if found else 1)
PYEOF
chmod 755 /usr/local/sbin/canon-usbreset
pass "已安装 /usr/local/sbin/canon-usbreset"

# ---------------------------------------------------------------- 5. CUPS 配置
step "5/10 CUPS: 局域网监听 + 访问控制 + 纸张尺寸"
cp -a /etc/cups/cupsd.conf "/etc/cups/cupsd.conf.bak.$(date +%Y%m%d%H%M%S)"
python3 - <<'PYEOF'
import re
p = '/etc/cups/cupsd.conf'
s = open(p).read()

# (a) 监听交给 systemd 的 cups.socket，避免重复绑定
s = re.sub(r'^[ \t]*(Listen|Port)[ \t]+.*$',
           lambda m: '# ' + m.group(0) + '  # 由 cups.socket 提供', s, flags=re.M)

# (b) 不广播：AirPrint 记录由 avahi 服务文件统一发布（TXT 字段可控）
s = re.sub(r'^BrowseLocalProtocols.*$', 'BrowseLocalProtocols none', s, flags=re.M)

# (c) ServerAlias *，避免 Host 头不匹配被 403
if 'ServerAlias' not in s:
    s = re.sub(r'^(LogLevel[ \t]+.*)$', r'\1\nServerAlias *', s, count=1, flags=re.M)

# (d) 纸张尺寸：默认 A4，就绪列表给 A4/A5/B5（不要加引号！）
s = re.sub(r'^DefaultPaperSize.*$', '', s, flags=re.M)
s = re.sub(r'^ReadyPaperSizes.*$', '', s, flags=re.M)
s = re.sub(r'^(ServerAlias[^\n]*)$',
           r'\1\nDefaultPaperSize A4\nReadyPaperSizes A4,A5,B5,Legal', s, count=1, flags=re.M)

# (e) 所有 Location 放开（/admin/conf、/admin/log 的 AuthType/Require 保留）
def fix(m):
    tag, body = m.group(1), m.group(2)
    inner = re.sub(r'^[ \t]*(Allow|Deny)\b.*\n?', '', body, flags=re.M)
    if re.search(r'^[ \t]*Order[ \t]+allow,deny[ \t]*$', inner, re.M):
        inner = re.sub(r'^([ \t]*Order[ \t]+allow,deny)[ \t]*$', r'\1\n  Allow all', inner, count=1, flags=re.M)
    else:
        inner = '\n  Order allow,deny\n  Allow all\n' + inner
    return tag + inner + '</Location>'
s = re.sub(r'(<Location\s+[^>]*>)(.*?)</Location>', fix, s, flags=re.S)
open(p, 'w').write(s)
print('cupsd.conf 已更新')
PYEOF
pass "cupsd.conf 已更新"

mkdir -p /etc/systemd/system/cups.socket.d
cat > /etc/systemd/system/cups.socket.d/10-lan-631.conf <<'EOF'
[Socket]
ListenStream=
ListenStream=/run/cups/cups.sock
ListenStream=631
EOF

systemctl daemon-reload
systemctl stop cups 2>/dev/null
systemctl restart cups.socket
systemctl start cups
for i in $(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:631/ && break; sleep 1; done
if ss -ltn 2>/dev/null | grep -qE '(^|[[:space:]])(\*|0\.0\.0\.0|\[::\]):631[[:space:]]'; then
  pass "631 已监听全网卡"
else
  warn "socket 激活未生效，回退为 cupsd 自行监听"
  python3 - <<'PYEOF'
p='/etc/cups/cupsd.conf'; s=open(p).read()
if 'Port 631' not in s: s = 'Port 631\n' + s
open(p,'w').write(s)
PYEOF
  printf '[Socket]\nListenStream=\nListenStream=/run/cups/cups.sock\n' > /etc/systemd/system/cups.socket.d/10-lan-631.conf
  systemctl daemon-reload; systemctl stop cups; systemctl restart cups.socket; systemctl start cups; sleep 3
  ss -ltn 2>/dev/null | grep -qE ':631[[:space:]]' && pass "631 已监听（cupsd 自行监听）" || fail "631 未监听"
fi

# ---------------------------------------------------------------- 6. 打印队列
step "6/10 创建打印队列"
PPD_PATH="/usr/share/cups/model/$PPD_NAME"
[ -f "$PPD_PATH" ] || { fail "找不到 PPD: $PPD_PATH"; }
lpadmin -x "$QUEUE" >/dev/null 2>&1
if lpadmin -p "$QUEUE" -E -v "ccp://localhost:$CCP_PORT" -P "$PPD_PATH" \
      -D "$MODEL" -L "USB ($DEV_LINK)" \
      -o printer-is-shared=true -o PageSize=A4 2>>"$LOG"; then
  pass "队列 $QUEUE 已创建"
else
  fail "队列创建失败"; tail -5 "$LOG" | sed 's/^/        /'
fi
cupsaccept "$QUEUE" >/dev/null 2>&1
cupsenable  "$QUEUE" >/dev/null 2>&1

# ---------------------------------------------------------------- 6.5 渲染链
step "6.5/10 安装渲染链优化（照片提速 + CMYK 黑块修复）"
HERE=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/scripts/patch-render-chain.sh" ]; then
  if bash "$HERE/scripts/patch-render-chain.sh" >>"$LOG" 2>&1; then
    pass "渲染链已优化（jpeg2pdf + 按需 RGB）"
  else
    warn "渲染链补丁执行失败，见 $LOG"
  fi
else
  warn "缺少 scripts/patch-render-chain.sh，跳过（照片会走较慢的 imagetopdf）"
fi

# ---------------------------------------------------------------- 7. ccpd
step "7/10 配置并启动 ccpd（Type=forking + locale + 启动前复位）"
[ -e "$DEV_LINK" ] || { ln -sf /dev/usb/lp0 "$DEV_LINK" 2>/dev/null; warn "软链接缺失，暂用 /dev/usb/lp0"; }
ccpdadmin -p "$QUEUE" -o "$DEV_LINK" >>"$LOG" 2>&1 && pass "ccpdadmin: $QUEUE -> $DEV_LINK" || fail "ccpdadmin 失败"

cat > /etc/systemd/system/ccpd.service <<'EOF'
[Unit]
Description=Canon CAPT Printer Daemon (ccpd)
After=network-online.target cups.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/ccpd
Restart=on-failure
RestartSec=3
KillMode=control-group
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/systemd/system/ccpd.service.d
cat > /etc/systemd/system/ccpd.service.d/20-locale.conf <<'EOF'
[Service]
# 关键：captmoncnacb 按 locale 查 msgtable（只有 en 条目），无 LANG 会 strcmp(NULL) 段错误
Environment=LANG=en_US.UTF-8
Environment=LC_ALL=en_US.UTF-8
Environment=HOME=/root
EOF
cat > /etc/systemd/system/ccpd.service.d/40-preflight.conf <<'EOF'
[Service]
# 启动前清掉可能残留的 32 位助手并复位 USB，否则新助手打不开被占用的设备
ExecStartPre=-/usr/bin/pkill -9 -x captmoncnacb
ExecStartPre=-/usr/local/sbin/canon-usbreset
ExecStartPre=/bin/sleep 2
EOF

systemctl daemon-reload
# enable 可能被 update-rc.d 拦截（Canon 的 init 脚本没有 runlevel），直接建 wants 链接
systemctl disable ccpd >/dev/null 2>&1
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/ccpd.service /etc/systemd/system/multi-user.target.wants/ccpd.service
systemctl reset-failed ccpd 2>/dev/null
systemctl restart ccpd
sleep 4
[ "$(systemctl is-active ccpd)" = "active" ] && pass "ccpd 运行中 (pid $(pgrep -x ccpd | tr '\n' ' '))" || fail "ccpd 未运行"
ss -ltn 2>/dev/null | grep -q ":$CCP_PORT" && pass "ccpd 监听 $CCP_PORT" || warn "端口 $CCP_PORT 未监听"

# ---------------------------------------------------------------- 8. AirPrint
step "8/10 发布 AirPrint（iOS 15 / iOS 26 均实测可用的字段组合）"
cat > /etc/avahi/services/canon-airprint.service <<EOF
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">$MODEL (%h)</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/$QUEUE</txt-record>
    <txt-record>ty=$MODEL</txt-record>
    <txt-record>note=fnOS</txt-record>
    <txt-record>pdl=image/urf,application/pdf,image/jpeg,image/png</txt-record>
    <txt-record>URF=W8,SRGB24,CP255,RS600,DM1</txt-record>
    <txt-record>Color=T</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>product=($MODEL)</txt-record>
    <txt-record>priority=50</txt-record>
    <txt-record>Transparent=F</txt-record>
    <txt-record>Binary=F</txt-record>
    <txt-record>TBCP=F</txt-record>
  </service>
</service-group>
EOF
avahi-daemon --check >/dev/null 2>&1 && pass "avahi 服务文件语法 OK"
systemctl restart avahi-daemon
sleep 3
systemctl is-active --quiet avahi-daemon && pass "avahi-daemon 运行中" || fail "avahi-daemon 未运行"

# ---------------------------------------------------------------- 9. 屏蔽 ipp-usb
step "9/10 屏蔽 ipp-usb（它会用 libusb 抢走打印机接口）"
systemctl disable --now ipp-usb >>"$LOG" 2>&1
systemctl mask ipp-usb >>"$LOG" 2>&1
pass "ipp-usb 已屏蔽"

# ---------------------------------------------------------------- 10. 验收
step "10/10 验收"
log "--- 队列 ---"; lpstat -p -d -v 2>&1 | sed 's/^/  /' | tee -a "$LOG"
log "--- 设备 ---"; ls -l "$DEV_LINK" 2>&1 | sed 's/^/  /' | tee -a "$LOG"
log "--- CAPT 协议探测 ---"
python3 - "$QUEUE" <<'PYEOF' 2>&1 | sed 's/^/  /' | tee -a "$LOG"
import socket, struct, sys
q = sys.argv[1].encode()
try:
    s = socket.create_connection(("127.0.0.1", 59687), 3)
    s.sendall(b"CCP2" + struct.pack("<i", len(q)) + q)
    r = s.recv(8); s.close()
    c = struct.unpack("<i", r[4:8])[0] if len(r) >= 8 else None
    print("ccpd:", {1: "TRUE(就绪)", 0: "FALSE", -1: "PARAMERR", -2: "NOQUEUE", -3: "BUSY", -4: "NOTHREAD"}.get(c, c))
except Exception as e:
    print("探测失败:", e)
PYEOF
log "--- IPP 纸张与格式 ---"
ipptool -tv "ipp://127.0.0.1:631/printers/$QUEUE" get-printer-attributes.test 2>/dev/null \
  | grep -E '^ *(media-ready|document-format-preferred|printer-state )' | cut -c1-220 | sed 's/^/  /' | tee -a "$LOG"
log "--- AirPrint 广播 ---"
timeout 8 avahi-browse -rtp _ipp._tcp 2>/dev/null | grep -c "$QUEUE" | sed 's/^/  匹配条目: /' | tee -a "$LOG"

log ""
log "  通过 $ok 项 / 失败 $bad 项"
log "  打印地址  : ipp://${LANIP}:631/printers/$QUEUE"
log "  Web 管理  : http://${LANIP}:631/"
log "  iPhone    : 打印面板里选 \"$MODEL (${HOSTNAME%%.*})\""
log "  Mac/Windows: 手动添加 IPP + 通用 PostScript 驱动"
log "  日志      : $LOG"
exit 0
