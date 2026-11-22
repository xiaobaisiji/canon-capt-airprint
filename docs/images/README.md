# 截图存放说明

README 中引用了这里的图片。建议提交以下几张（PNG，宽度 ≤ 1600px，单张 ≤ 500KB）：

| 文件名 | 内容 | 建议来源 |
|---|---|---|
| `ios-airprint.png` | iPhone 打印面板里选中 `Canon LBP7010C (主机名)` 的画面 | 照片 → 分享 → 打印 → 打印机 |
| `ios-paper-size.png` | 展开「纸张大小」能看到 A4 / A5 / B5 的画面 | 同上，点「纸张大小」 |
| `cups-queue.png` | CUPS 队列状态页（显示 idle、设备 URI、作业列表） | `http://<NAS-IP>:631/printers/<队列>` |

`flow.svg` 是仓库自带的架构图（矢量，无需替换）。

## 拍摄注意事项

- **打码**：截图里若出现主机名、内网 IP、序列号，请先遮挡，或改成示例值
- **不要露出**：其他设备名称、Wi-Fi SSID、Apple ID 等个人信息
- **格式**：PNG；iPhone 截图默认就是 PNG，可直接用
- **体积**：可用 `pngquant` / `tinypng` 压一下，仓库里不宜放 5MB 的大图

## 提交后

在 `README.md` 的「效果」小节里取消注释：

```markdown
![iPhone 隔空打印](docs/images/ios-airprint.png)
```

本地预览方法（不需要装工具）：

```bash
python3 -m http.server 8000
# 浏览器打开 http://localhost:8000 查看 README 渲染效果
```
