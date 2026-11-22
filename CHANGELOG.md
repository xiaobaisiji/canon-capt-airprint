# 变更记录

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 文档
- 新增英文版 `README.en.md`，并在两个 README 顶部加入语言切换
- README 重构：痛点表、三步上手、适合/不适合、FAQ 折叠、测试环境

## [1.0.0] - 2026-11-22

### 新增
- 一键部署脚本 `canon-capt-airprint-setup.sh`（驱动安装、i386 运行库、udev、CUPS、队列、ccpd、AirPrint、自检）
- 完整文档：原理、部署、排障、运维、附录五篇
- 架构图 `docs/images/flow.svg`（含逐层故障点标注）

### 修复（记录踩过的坑）
- `ccpd` 单元 `Type=simple` 导致 fork 出的守护进程被 systemd 杀掉 → 改 `Type=forking`
- 64 位驱动包内部助手是 32 位，缺库时 `exit 127` → 安装 `libxml2:i386` / `libpopt0:i386`
- `ccpd` 服务缺 locale 导致 `captmoncnacb` 在 `strcmp` 处段错误 → 注入 `LANG=en_US.UTF-8`
- `ipp-usb` 抢占 USB 打印接口 → `systemctl mask ipp-usb`
- 多打印机共用 `lpN` 编号漂移 → udev 按 VID/PID 生成固定软链接
- CUPS 重启后 TCP 631 返回 403 → `<Location>` 改显式 `Allow all` + `ServerAlias *`
- iOS 26 不识别传统 AirPrint TXT → 改用 `image/urf` 优先 + `URF=W8,SRGB24,CP255,RS600,DM1` 的字段组合
- iOS 纸张列表缺失 A4/A5/B5 → 显式 `ReadyPaperSizes`（**不能加引号**）
- 手工向 PPD 添加 A6 导致所有作业卡死 → 移除，禁止改 PPD

### 已知问题
- Windows 的 IPP 客户端偶发不发送作业（CUPS 侧收不到报文），可用 RAW 9100 中转规避
- `dmesg` 偶见 `c3pldrv` segfault，不影响实际出纸（2017 年 64 位构建的已知缺陷）
