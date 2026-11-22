# 参与贡献

感谢你愿意帮忙！这个项目的价值来自**真实的机型与环境案例**。

## 最有用的贡献

1. **报告你的环境**：机型、USB PID、发行版、内核、CUPS 版本
2. **提交排障结果**：现象 → 定位过程 → 最终原因
3. **补充机型 PPD 对照**：让 `docs/05-附录.md` 的表格更全

## 提交 Issue 请包含

```
机型：
USB ID（lsusb | grep -i canon）：
发行版 / 内核：
CUPS 版本（cupsd --version）：
驱动版本：
现象：
已尝试的操作：
相关日志（journalctl -u ccpd -n 50 / tail -50 /var/log/cups/error_log）：
```

> 提交前请**脱敏**：删掉内网 IP、主机名、序列号、Wi-Fi 名称。

## 提交 Pull Request

```bash
git clone https://github.com/<owner>/canon-capt-airprint.git
cd canon-capt-airprint
git checkout -b fix/your-topic
# 修改后
bash -n canon-capt-airprint-setup.sh     # 语法检查
git commit -m "fix: 说明改了什么"
git push origin fix/your-topic
```

约定：

- 脚本保持**幂等**（可重复执行）
- 涉及系统配置的改动，请同时在 `docs/` 里更新说明
- 不要提交 Canon 的二进制、驱动包、抓包文件

## 不接受的改动

- 把 PPD 里的纸张尺寸硬编码进来（会破坏 `gs -sDEVICE=opvp`，见 `docs/03-故障排查.md`）
- 为了“一键”而引入未经审计的第三方二进制
