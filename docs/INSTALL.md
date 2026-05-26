# Installing Netra (macOS)

## If you see「"Netra" 已损坏，无法打开」

This is **not** file corruption. macOS Gatekeeper blocks apps downloaded from the internet when they are not signed with a paid Apple Developer ID.

### Quick fix (recommended)

Open **Terminal** and run:

```bash
xattr -cr /Applications/Netra.app
```

Then open Netra from Applications as usual.

### Alternative

1. **Right-click** `Netra.app` → **Open** → confirm **Open** again  
2. Or: **System Settings** → **Privacy & Security** → allow Netra if shown

### Install steps

1. Download `Netra-*-macos.zip` from [Releases](https://github.com/frontitle/Netra/releases)
2. Unzip and drag `Netra.app` to **Applications**
3. Run the `xattr` command above if macOS blocks launch
4. For Wi-Fi scanning: grant **Location Services** when prompted

---

## 中文

### 提示「已损坏，无法打开」？

这不是安装包坏了，而是 macOS 对**未使用 Apple 开发者证书公证**的下载应用的默认拦截。

**终端执行（推荐）：**

```bash
xattr -cr /Applications/Netra.app
```

然后正常从启动台或应用程序文件夹打开即可。

**或：** 右键 `Netra.app` → **打开** → 再次点 **打开**。

正式版将提供 Apple 公证签名；当前 Beta 为社区 ad-hoc 签名构建。
