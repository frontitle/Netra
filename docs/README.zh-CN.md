# Netra

Netra（梵语「眼」）是 macOS 原生局域网扫描与网络拓扑工具，帮助发现设备、绘制路由链并诊断网络质量。

## 功能

- **局域网扫描** — ARP + 多网段 ping 遍历
- **网络拓扑** — 根据同 MAC 多 IP 推断多层路由
- **设备表** — 可排序列表与右侧 Inspector
- **Wi-Fi** — CoreWLAN 扫描附近热点
- **质量诊断** — 网关与公网延迟
- **历史记录** — 按网络保存快照

## 界面语言

- 产品**默认英文界面**
- 仅当 macOS 系统首选语言为中文（`zh*`）时自动使用简体中文
- 可在 **设置 → 语言** 中手动切换

## 构建

```bash
./native/scripts/build-native-macos.sh
open release/Netra.app
```

## 开源

官方仓库：[github.com/frontitle/Netra](https://github.com/frontitle/Netra)

- Beta 版本：`0.1.1-beta`、`0.1.2-beta` …（第三位 patch 递增）
- 应用内检查更新仅对照该仓库的 GitHub Releases
- 发布范围见 [PUBLISHING.md](PUBLISHING.md)

MIT 许可证。
