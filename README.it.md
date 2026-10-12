# Omarchy Server Monitor

🇬🇧 [English](README.md) · 🇮🇹 Italiano

Widget per la barra di Omarchy 4.x che controlla se i tuoi server, siti web e domini sono raggiungibili e mostra lo stato di ognuno con un pallino verde (tutto ok) o rosso (problema).

![Server Monitor](preview.png)

## Funzioni

- Icona nella barra con il conteggio dei server online, ad esempio `󰒍 2/3`. Se almeno un server è offline l'icona prende il colore di avviso del tema.
- Finestra con la lista: pallino di stato, nome, indirizzo, tipo di controllo e risultato (latenza, codice HTTP o giorni alla scadenza).
- Aggiunta, modifica, riordino e rimozione direttamente dalla finestra.
- Le voci con lo stesso nome (senza distinguere maiuscole e minuscole) vengono raggruppate sotto un'unica intestazione, con un pallino riassuntivo: rosso se almeno un controllo del gruppo ha un problema, verde se sono tutti ok. Utile per tenere insieme un server, il suo sito e il suo dominio.
- Significato dei pallini:
  - **verde**: tutto ok (raggiungibile, HTTP 2xx/3xx, dominio non vicino alla scadenza);
  - **rosso**: problema (offline, errore HTTP, dominio in scadenza o scaduto);
  - **grigio**: stato sconosciuto (il registro non pubblica la scadenza del dominio); un pallino grigio che pulsa è in attesa del primo controllo.
- Quattro tipi di controllo:
  - **Ping**: ping ICMP verso un IP o un hostname;
  - **TCP**: connessione a una porta, utile per i server che bloccano il ping;
  - **Web**: richiesta HTTP/HTTPS a un indirizzo; verde se risponde con un codice 2xx o 3xx, con codice e tempo di risposta;
  - **Dominio**: giorni alla scadenza della registrazione del dominio, letti da RDAP con whois come riserva; rosso se mancano meno di 30 giorni (configurabile) o se il dominio è scaduto.
- Tutto viene controllato in parallelo, in automatico ogni 60 secondi (configurabile). La scadenza dei domini viene letta ogni 6 ore, oppure subito con un controllo manuale.
- Notifica desktop quando qualcosa va offline, torna online o un dominio si avvicina alla scadenza (disattivabile).
- Grafica e colori presi dal tema Omarchy attivo: il verde e il rosso dei pallini sono le chiavi `green` e `red` del `colors.toml` del tema e cambiano insieme al tema.

## Requisiti

- Omarchy 4.x con Omarchy Shell (Quickshell).
- `bash`, `ping` (iputils), `timeout` (coreutils), `curl`, `jq` e `notify-send` (libnotify), già presenti in Omarchy.
- Facoltativo: `whois`, usato per la scadenza dei domini quando il registro non ha un servizio RDAP (ad esempio `.it`). Se manca, installalo con `omarchy pkg add whois`.

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
- **Aggiungi server**: scegli il tipo di controllo (Ping, TCP, Web, Dominio), inserisci nome e indirizzo (IP o hostname, URL o dominio; per TCP anche la porta), poi premi Invio o "Aggiungi". Per aggiungere un controllo a un gruppo esistente usa lo stesso nome.
- 󰏫 **Modifica**: carica il server nel modulo in basso; "Salva" lo aggiorna, 󰅖 o Esc annullano.
- 󰁝 / 󰁅 **Riordina**: sposta la voce su o giù nella lista. Dentro un gruppo le frecce spostano il controllo all'interno del gruppo; quelle sull'intestazione spostano il gruppo intero.
- 󰆴 **Rimuovi**: toglie il server dalla lista.
- 󰑐 nell'intestazione: controlla subito tutti i server.

## Configurazione

La lista dei server è salvata in `~/.config/omarchy/server-monitor.json`:

```json
[
  { "name": "Cloudflare", "type": "ping", "host": "1.1.1.1", "port": 0 },
  { "name": "Cloudflare", "type": "tcp", "host": "1.1.1.1", "port": 443 },
  { "name": "example.com", "type": "http", "host": "https://example.com", "port": 0 },
  { "name": "example.com", "type": "domain", "host": "example.com", "port": 0 },
  { "name": "NAS", "type": "ping", "host": "192.168.1.250", "port": 0 }
]
```

Le voci con lo stesso `name` formano un gruppo: qui "Cloudflare" ed "example.com" hanno due controlli ciascuno, "NAS" è una voce singola. Quando modifichi la lista dalla finestra, il file viene salvato con le voci di ogni gruppo una accanto all'altra.

`type` vale `ping`, `tcp`, `http` o `domain`; `port` serve solo per `tcp`. Le voci senza `type`, scritte dalla versione 1.0, vengono lette come `tcp` se hanno una porta e come `ping` altrimenti. Il file si può modificare anche a mano: la finestra si aggiorna da sola.

Opzioni del widget (in `~/.config/omarchy/shell.json`, nella voce del widget):

| Chiave        | Default | Descrizione                                    |
|---------------|---------|------------------------------------------------|
| `intervalSec` | `60`    | Intervallo tra un controllo e l'altro, in secondi (10–3600) |
| `notify`      | `true`  | Notifica quando un server cambia stato         |
| `domainWarnDays` | `30` | Il dominio diventa rosso quando alla scadenza mancano meno di questi giorni (0–365) |

Esempio:

```json
{ "id": "mcp64.server-monitor", "intervalSec": 30, "notify": false, "domainWarnDays": 15 }
```

## Rimozione

```bash
omarchy plugin remove mcp64.server-monitor
```

La lista dei server in `~/.config/omarchy/server-monitor.json` non viene cancellata.

## Limiti

- Il ping attende al massimo 2 secondi, la connessione TCP al massimo 3, la richiesta web al massimo 10 (seguendo fino a 5 reindirizzamenti).
- Un indirizzo web senza `http://` o `https://` viene controllato in HTTPS.
- La scadenza dei domini usa il servizio pubblico RDAP `rdap.org` e, come riserva, `whois`: i nomi dei domini che controlli vengono quindi inviati a questi servizi. Alcuni registri (ad esempio `.de`) non pubblicano la data di scadenza: in quel caso il pallino resta grigio e compare "n/d". I sottodomini vengono ridotti al dominio registrato (`www.example.co.uk` → `example.co.uk`).
- Un server che risponde solo su IPv6 va inserito con l'indirizzo IPv6; i controlli usano `ping` e `/dev/tcp` di bash, quindi seguono la configurazione di rete del sistema.

## Licenza

MIT. Vedi [LICENSE](LICENSE).
