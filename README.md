# Omarchy Server Monitor

Widget per la barra di Omarchy 4.x che controlla se i tuoi server sono raggiungibili e mostra lo stato di ognuno con un pallino verde (online) o rosso (offline).

![Server Monitor](preview.png)

## Funzioni

- Icona nella barra con il conteggio dei server online, ad esempio `󰒍 2/3`. Se almeno un server è offline l'icona prende il colore di avviso del tema.
- Finestra con la lista dei server: pallino di stato, nome, indirizzo, tipo di controllo e latenza.
- Aggiunta, modifica, riordino e rimozione dei server direttamente dalla finestra.
- Due tipi di controllo:
  - **senza porta**: ping ICMP;
  - **con porta**: connessione TCP alla porta indicata, utile per i server che bloccano il ping.
- Tutti i server vengono controllati in parallelo, in automatico ogni 60 secondi (configurabile).
- Notifica desktop quando un server va offline o torna online (disattivabile).
- Grafica e colori presi dal tema Omarchy attivo: il verde e il rosso dei pallini sono le chiavi `green` e `red` del `colors.toml` del tema e cambiano insieme al tema.

## Requisiti

- Omarchy 4.x con Omarchy Shell (Quickshell).
- `bash`, `ping` (iputils), `timeout` (coreutils) e `notify-send` (libnotify), già presenti in Omarchy.

## Installazione

```bash
omarchy plugin add https://github.com/GiuseppeSolla/omarchy-server-monitor.git --enable
```

Il widget viene messo nella sezione destra della barra. Per spostarlo:

```bash
omarchy bar move mcp64.server-monitor --section left   # oppure center
```

### Installazione manuale

```bash
git clone https://github.com/GiuseppeSolla/omarchy-server-monitor.git \
  ~/.config/omarchy/plugins/mcp64.server-monitor
omarchy-shell shell rescanPlugins
omarchy plugin enable mcp64.server-monitor
```

## Utilizzo

- **Clic sinistro** sull'icona: apre o chiude la finestra.
- **Clic centrale**: ricontrolla subito tutti i server.
- **Aggiungi server**: inserisci nome, IP o hostname e, se vuoi, una porta, poi premi Invio o "Aggiungi".
- 󰏫 **Modifica**: carica il server nel modulo in basso; "Salva" lo aggiorna, 󰅖 o Esc annullano.
- 󰁝 / 󰁅 **Riordina**: sposta il server su o giù nella lista.
- 󰆴 **Rimuovi**: toglie il server dalla lista.
- 󰑐 nell'intestazione: controlla subito tutti i server.

## Configurazione

La lista dei server è salvata in `~/.config/omarchy/server-monitor.json`:

```json
[
  { "name": "Cloudflare DNS", "host": "1.1.1.1", "port": 0 },
  { "name": "Sito web", "host": "example.com", "port": 443 }
]
```

`port: 0` indica il ping ICMP. Il file si può modificare anche a mano: la finestra si aggiorna da sola.

Opzioni del widget (in `~/.config/omarchy/shell.json`, nella voce del widget):

| Chiave        | Default | Descrizione                                    |
|---------------|---------|------------------------------------------------|
| `intervalSec` | `60`    | Intervallo tra un controllo e l'altro, in secondi (10–3600) |
| `notify`      | `true`  | Notifica quando un server cambia stato         |

Esempio:

```json
{ "id": "mcp64.server-monitor", "intervalSec": 30, "notify": false }
```

## Rimozione

```bash
omarchy plugin remove mcp64.server-monitor
```

La lista dei server in `~/.config/omarchy/server-monitor.json` non viene cancellata.

## Limiti

- Il ping attende al massimo 2 secondi, la connessione TCP al massimo 3.
- Un server che risponde solo su IPv6 va inserito con l'indirizzo IPv6; i controlli usano `ping` e `/dev/tcp` di bash, quindi seguono la configurazione di rete del sistema.

## Licenza

MIT. Vedi [LICENSE](LICENSE).
