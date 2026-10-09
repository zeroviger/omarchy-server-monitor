# Omarchy Server Monitor

🇬🇧 English · 🇮🇹 [Italiano](README.it.md)

A bar widget for Omarchy 4.x that checks whether your servers are reachable and shows each one with a green (online) or red (offline) dot.

![Server Monitor](preview.png)

> The widget's interface is in Italian.

## Features

- Bar icon with the number of servers online, e.g. `󰒍 2/3`. When at least one server is offline the icon takes the theme's alert color.
- Popup with the server list: status dot, name, address, check type and latency.
- Add, edit, reorder and remove servers directly from the popup.
- Two kinds of check:
  - **no port**: ICMP ping;
  - **with a port**: TCP connection to that port, useful for servers that block ping.
- All servers are checked in parallel, automatically every 60 seconds (configurable).
- Desktop notification when a server goes offline or comes back online (can be turned off).
- Look and colors follow the active Omarchy theme: the green and red dots are the `green` and `red` keys of the theme's `colors.toml` and change along with the theme.

## Requirements

- Omarchy 4.x with Omarchy Shell (Quickshell).
- `bash`, `ping` (iputils), `timeout` (coreutils) and `notify-send` (libnotify), all of which ship with Omarchy.

## Install

```bash
omarchy plugin add https://github.com/GiuseppeSolla/omarchy-server-monitor.git --enable
```

The widget is placed in the right section of the bar. To move it:

```bash
omarchy bar move mcp64.server-monitor --section left   # or center
```

### Manual install

```bash
git clone https://github.com/GiuseppeSolla/omarchy-server-monitor.git \
  ~/.config/omarchy/plugins/mcp64.server-monitor
omarchy-shell shell rescanPlugins
omarchy plugin enable mcp64.server-monitor
```

## Usage

The labels in brackets are the Italian ones shown in the widget.

- **Left click** on the icon: open or close the popup.
- **Middle click**: check all servers now.
- **Add a server** ("Aggiungi server"): enter a name ("Nome"), an IP or hostname ("IP o hostname") and, optionally, a port ("Porta"), then press Enter or "Aggiungi".
- 󰏫 **Edit** ("Modifica"): loads the server into the form below; "Salva" saves it, 󰅖 or Esc cancel.
- 󰁝 / 󰁅 **Reorder**: move the server up or down the list.
- 󰆴 **Remove** ("Rimuovi"): deletes the server from the list.
- 󰑐 in the header: check all servers now.

## Configuration

The server list is stored in `~/.config/omarchy/server-monitor.json`:

```json
[
  { "name": "Cloudflare DNS", "host": "1.1.1.1", "port": 0 },
  { "name": "Website", "host": "example.com", "port": 443 }
]
```

`port: 0` means ICMP ping. You can also edit the file by hand: the popup updates on its own.

Widget options (in `~/.config/omarchy/shell.json`, on the widget's entry):

| Key           | Default | Description                                    |
|---------------|---------|------------------------------------------------|
| `intervalSec` | `60`    | Seconds between checks (10–3600)               |
| `notify`      | `true`  | Notify when a server changes state             |

Example:

```json
{ "id": "mcp64.server-monitor", "intervalSec": 30, "notify": false }
```

## Remove

```bash
omarchy plugin remove mcp64.server-monitor
```

The server list in `~/.config/omarchy/server-monitor.json` is not deleted.

## Limits

- Ping waits at most 2 seconds, the TCP connection at most 3.
- A server that only answers over IPv6 must be entered with its IPv6 address; checks use `ping` and bash's `/dev/tcp`, so they follow the system's network configuration.

## License

MIT. See [LICENSE](LICENSE).
