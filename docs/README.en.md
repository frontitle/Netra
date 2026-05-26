# Netra

Netra (“eye” in Sanskrit) is a native macOS application for discovering devices on your local network, mapping router topology, and diagnosing connectivity.

## Highlights

- **LAN scan** — ARP + ping sweep across local and routed segments
- **Topology** — infer multi-hop gateways from devices sharing a MAC
- **Device table** — sortable columns, inspector with ports and roles
- **Wi-Fi** — nearby networks via CoreWLAN
- **Quality** — gateway and internet latency checks
- **History** — snapshots per network

## UI language

- Default UI is **English**
- **简体中文** is used automatically when macOS preferred language is Chinese (`zh*`)
- Override anytime in **Settings → Language**

## Build

```bash
./native/scripts/build-native-macos.sh
open release/Netra.app
```

## Open source

Official repo: [github.com/frontitle/Netra](https://github.com/frontitle/Netra)

- Beta versions: `0.1.1-beta`, `0.1.2-beta`, … (patch increments)
- Update checks in the app use this repo’s GitHub Releases only
- See [PUBLISHING.md](PUBLISHING.md) for commit vs. ignore rules

MIT License.
