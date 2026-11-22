#!/bin/sh
# CUPS filter: PDF -> PDF
#
# 作用有两个：
#   1. 规避 CAPT 驱动对 CMYK 图像的缺陷（会渲染成黑块）—— 只在检测到 CMYK 时才转
#   2. 纯 RGB 的 PDF（手机照片、普通文档）直接透传，省掉一次完整 gs 重编码
#
# 说明：CUPS 可能把作业文件作为 argv[6] 传入，也可能用 stdin，两种都支持。
tmp=$(mktemp /tmp/canon-pdf-XXXXXX.pdf) || exit 1
trap 'rm -f "$tmp"' EXIT INT TERM

if [ -n "${6:-}" ] && [ "$6" != "-" ] && [ -f "$6" ]; then
    cp -- "$6" "$tmp" || exit 1
else
    cat > "$tmp" || exit 1
fi
[ -s "$tmp" ] || exit 1

if grep -qa '/DeviceCMYK' "$tmp"; then
    exec /usr/bin/gs -q -dBATCH -dNOPAUSE -dSAFER \
         -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 \
         -sColorConversionStrategy=RGB -dProcessColorModel=/DeviceRGB \
         -dAutoFilterColorImages=false -sColorImageFilter=DCTEncode -dJPEGQ=92 \
         -sOutputFile=- "$tmp"
else
    cat "$tmp"
fi
