#!/usr/bin/env python3
"""CUPS filter: JPEG -> PDF，不重新编码（直接把 JPEG 作为 DCTDecode 图像嵌入）。
相比 cups-filters 的 imagetopdf（解码+缩放+重编码，4000x3000 要约 28 秒），
这里只做字节搬运，通常 < 100ms，缩放交给下游的 CAPT 驱动一次性完成。
"""
import sys, struct

SOF = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def jpeg_info(data: bytes):
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG")
    i = 2
    n = len(data)
    while i < n - 1:
        if data[i] != 0xFF:
            i += 1
            continue
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            break
        marker = data[i]; i += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if i + 2 > n:
            break
        seg_len = struct.unpack(">H", data[i:i+2])[0]
        if marker in SOF and i + 7 <= n:
            precision = data[i+2]
            h = struct.unpack(">H", data[i+3:i+5])[0]
            w = struct.unpack(">H", data[i+5:i+7])[0]
            comps = data[i+7]
            return w, h, comps
        i += seg_len
    raise ValueError("no SOF marker")


def build_pdf(jpg: bytes, w: int, h: int, comps: int) -> bytes:
    page_w, page_h = 595.0, 842.0
    if w > h:                     # 横图 → 横向纸
        page_w, page_h = 842.0, 595.0
    scale = min(page_w / w, page_h / h)
    dw, dh = w * scale, h * scale
    tx, ty = (page_w - dw) / 2, (page_h - dh) / 2
    cs = {1: "/DeviceGray", 3: "/DeviceRGB", 4: "/DeviceCMYK"}.get(comps, "/DeviceRGB")

    content = f"q {dw:.2f} 0 0 {dh:.2f} {tx:.2f} {ty:.2f} cm /Im0 Do Q\n".encode()

    objs = []
    objs.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objs.append(
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {page_w:.0f} {page_h:.0f}] "
        f"/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>".encode())
    objs.append(
        f"<< /Type /XObject /Subtype /Image /Width {w} /Height {h} "
        f"/ColorSpace {cs} /BitsPerComponent 8 /Filter /DCTDecode "
        f"/Length {len(jpg)} >>\nstream\n".encode() + jpg + b"\nendstream")
    objs.append(f"<< /Length {len(content)} >>\nstream\n".encode() + content + b"endstream")

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for idx, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{idx} 0 obj\n".encode() + body + b"\nendobj\n"
    xref_pos = len(out)
    out += f"xref\n0 {len(objs)+1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n").encode()
    return bytes(out)


def read_input() -> bytes:
    """CUPS 把作业文件作为第 7 个参数(argv[6])传入；cupsfilter/管道则走 stdin。"""
    import os
    if len(sys.argv) > 6:
        path = sys.argv[6]
        if path and path != "-" and os.path.isfile(path):
            with open(path, "rb") as f:
                return f.read()
    return sys.stdin.buffer.read()


def main():
    data = read_input()
    if not data:
        sys.exit(1)
    try:
        w, h, comps = jpeg_info(data)
    except Exception as e:
        sys.stderr.write(f"jpeg2pdf: {e}\n")
        sys.exit(1)
    sys.stdout.buffer.write(build_pdf(data, w, h, comps))


if __name__ == "__main__":
    main()
