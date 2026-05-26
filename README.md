# Netra

**Netra — LAN Scanner & Network Topology for macOS**  
*See your network. Clearly.*

Native LAN scanner and topology tool (SwiftUI + CoreWLAN). No WebView.

**Repository:** [github.com/frontitle/Netra](https://github.com/frontitle/Netra) · **Status:** Beta (`0.1.x-beta`)

| Language | Documentation |
|----------|----------------|
| English | [docs/README.en.md](docs/README.en.md) |
| 中文 | [docs/README.zh-CN.md](docs/README.zh-CN.md) |

## Quick start

```bash
chmod +x native/scripts/build-native-macos.sh
./native/scripts/build-native-macos.sh
```

Output: **`release/Netra.app`**

## Features

- Full LAN scan on launch; auto ping sweep when new segments appear
- Multi-hop router topology from shared MAC addresses
- Sortable device table with inspector panel
- Wi-Fi scan (CoreWLAN), port probe, quality diagnostics, history

## Requirements

- macOS 13.0+
- Xcode Command Line Tools / Swift 5.9+

## Versioning & releases

- Marketing version starts at **`0.1.1-beta`**; patch bumps: `0.1.2-beta`, `0.1.3-beta`, …
- In-app **Check for Updates** uses [GitHub Releases](https://github.com/frontitle/Netra/releases) on this repo only
- See [docs/PUBLISHING.md](docs/PUBLISHING.md) for what to commit vs. exclude

## License

MIT — see [LICENSE](LICENSE)
