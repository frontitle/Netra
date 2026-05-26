# 发布指南 / Publishing Guide

官方仓库：[**frontitle/Netra**](https://github.com/frontitle/Netra)

---

## 什么应该发布到 GitHub（提交源码）

| 路径 | 说明 |
|------|------|
| `native/Sources/Netra/` | Swift 源码、视图、服务 |
| `native/Sources/Netra/Resources/` | `AppIcon.png`、`master_oui.txt`（IEEE OUI 公开数据，构建必需） |
| `native/Package.swift` | Swift Package 定义 |
| `native/Info.plist` | 版本号与 Bundle 元数据（**版本以这里为准写入应用**） |
| `native/scripts/build-native-macos.sh` | 本地打包脚本 |
| `README.md`、`docs/`、`LICENSE` | 文档与许可证 |
| `VERSION` | 与 `Info.plist` 同步的版本备忘（便于人工核对） |
| `package.json` | 可选：`npm run build` 脚本别名 |

## 什么不应发布（已在 `.gitignore`）

| 路径 | 原因 |
|------|------|
| `release/`、`native/.build/` | 编译产物、`.app` 二进制，体积大且可重现 |
| `*.dSYM` | 调试符号 |
| `.cursor/`、`.idea/` | 个人 IDE 状态 |
| `.env`、`credentials.json` 等 | 密钥与私有配置 |
| 任何 API Token、证书、私钥 | 安全 |

**GitHub Releases** 上可单独上传构建好的 `Netra.app`（zip），但**不要**把 `release/` 目录提交进 git 历史。

---

## 版本号规则（Beta）

- 当前产品线处于 **Beta**，营销版本形如：`0.1.1-beta`、`0.1.2-beta` …
- **小版本**指第三位（patch）：`0.1.1` → `0.1.2` → `0.1.3` …
- `CFBundleVersion`（构建号）每次打包可 +1，用于区分同营销版本的多次构建
- 根目录 `VERSION` 与 `native/Info.plist` 的 `CFBundleShortVersionString` 应保持一致

### GitHub Release 保留策略（开发期）

开发阶段小版本迭代快，**不在 GitHub 长期保留每一个 `0.1.x-beta`**：

| 保留 | 说明 |
|------|------|
| **当前最新** | 例如 `v0.1.4-beta`（始终只有一个最新的 patch） |
| **里程碑 0.x** | 进入新次版本线时保留的上一个大版本标签（如将来 `v0.2.0-beta` 发布后，可保留 `v0.1.0-beta` 作归档） |

每次发布新 patch 后，删除旧的 `v0.1.N-beta`（N 小于当前）：

```bash
chmod +x native/scripts/prune-patch-releases.sh
./native/scripts/prune-patch-releases.sh v0.1.4-beta
```

### 发布新版本到 GitHub 时

1. 修改 `native/Info.plist`：`CFBundleShortVersionString`（如 `0.1.4-beta`），`CFBundleVersion` +1
2. 同步 `VERSION` 与 `package.json` 的 `version`
3. 本地执行 `./native/scripts/build-native-macos.sh`
4. 打包 `release/Netra.app` 为 zip，创建 Release 标签 **`v0.1.4-beta`**
5. 执行 `./native/scripts/prune-patch-releases.sh v0.1.4-beta` 清理过期小版本

应用内 **设置 → 检查更新** 读取 GitHub Releases 列表 API，取**最新已发布**的预发布版本。

---

## 首次推送仓库示例

```bash
git remote add origin https://github.com/frontitle/Netra.git
git add README.md LICENSE docs/ native/ package.json VERSION .gitignore
git commit -m "Initial open-source release: Netra 0.1.1-beta"
git push -u origin main
```

---

## English summary

**Publish:** source under `native/`, docs, `LICENSE`, build script, resources (`AppIcon`, OUI DB).  
**Do not publish:** `release/`, `native/.build/`, secrets, IDE folders.  
**Updates:** in-app check uses [frontitle/Netra releases](https://github.com/frontitle/Netra/releases) only.  
**Versioning:** beta channel `0.1.x-beta`, bump patch (`x`) for small releases; tag e.g. `v0.1.2-beta`.
