# ITGLiveScore

Overlay/scoreboard live per lo streaming. È un tool **esterno** al tema: gira come processo Node.js separato sullo stesso PC su cui gira ITGmania, non fa parte del bundle Lua caricato dal gioco.

## Come funziona

1. Il tema (`Modules/ITGLiveScore.lua`, opzione `Enable Live Score Export` in `Options2`) scrive lo stato live della partita in `Save/RealTimeResults.json` ogni mezzo secondo mentre si gioca `ScreenGameplay`. Quando la canzone finisce (`ScreenEvaluationStage`) appende il risultato finale a `Save/RealTimeResultsHistory.json` (ultimi 50, FIFO) e scrive un file di dettaglio per player in `Save/RealTimeScoreDetails/<Id>.json`, riusando i dati che il motore/tema già tracciano per il proprio grafico a fine canzone (`sequential_offsets` da `JudgmentOffsetTracking.lua`, `GetLifeRecord()` per la curva vita) — nessun tracking nuovo lato Lua.
2. `ITGWebAPP/server.js` legge `RealTimeResults.json` ogni 500ms e lo ritrasmette via WebSocket (porta 8081) a tutti i client connessi; espone anche `GET /history` (rilegge `RealTimeResultsHistory.json`), `GET /history/:id` (rilegge il dettaglio corrispondente in `RealTimeScoreDetails/`) e `GET /info` (diagnostica — vedi sotto).
3. `ITGWebAPP/public/index.html` è la pagina overlay: tab LIVE via WebSocket, tab HISTORY via `/history`; cliccando su un punteggio in history si apre una modale con Judgments, Radar Data e un Timing Chart (scatter offset per nota + curva vita, via Chart.js) caricata da `/history/:id`.

## Avvio

```
cd ITGWebAPP
npm install
node server.js
```

Il server HTTP parte su `http://localhost:3000` (pagina overlay su `/index.html`), il WebSocket su `ws://localhost:8081`.

Variabili d'ambiente opzionali:

- `ITGMANIA_SAVE_DIR` — path della cartella `Save/` della tua installazione ITGmania (default `C:\Games\ITGmania\Save`)
- `PORT` — porta HTTP (default `3000`)
- `WS_PORT` — porta WebSocket (default `8081`)

## Diagnostica

All'avvio il server stampa in console dove sta guardando e come raggiungerlo:

```
Web server in esecuzione su http://localhost:3000
Save dir: C:\Games\ITGmania\Save
Raggiungibile da altri dispositivi sulla stessa rete su:
  http://192.168.1.50:3000
(dettagli anche su /info, es. http://localhost:3000/info)
```

Se `ITGMANIA_SAVE_DIR` punta a una cartella inesistente lo dice subito (`Save dir: ... (NON TROVATA! controlla ITGMANIA_SAVE_DIR)`) — utile per beccare al volo un path sbagliato invece di scoprirlo solo quando l'overlay resta vuoto.

`GET /info` espone le stesse informazioni in JSON, per un controllo rapido da browser (anche da un altro dispositivo):

```json
{
  "saveDir": "C:\\Games\\ITGmania\\Save",
  "saveDirFound": true,
  "liveFileFound": true,
  "port": 3000,
  "wsPort": 8081,
  "lanAddresses": ["192.168.1.50"]
}
```

Se `RealTimeResults.json` manca in modo persistente (path sbagliato, o il tema non ha ancora scritto nulla perché `EnableLiveScoreExport` è spento o non hai ancora giocato una canzone), il server logga i primi 5 tentativi falliti come errori, poi un unico avviso riassuntivo, e da quel punto controlla in silenzio finché il file non ricompare — niente spam di log all'infinito, e il server (HTTP/WebSocket/`/info`) resta comunque attivo, non si spegne. Non appena il file torna a esistere, stampa una riga di conferma e riprende a trasmettere normalmente.

### Stato visibile anche dal tema (`ITGLiveScoreServerStatus.json`)

Il tema Lua non può leggere un percorso assoluto del sistema operativo né l'IP di rete della
macchina — è sandboxato su percorsi virtuali (`/Save/...`) e non ha API di rete per questo. Per
aggirare il problema, all'avvio il server scrive lo stesso contenuto di `/info` anche in
`Save/ITGLiveScoreServerStatus.json`, dentro la stessa cartella `Save/` che sta già usando. Il
menu operatore **Simply Nino Options** nel tema legge quel file e mostra una riga di sola lettura
tipo `✔ 192.168.1.50:3000` (o `❌ Server non attivo` se il file non c'è) — comodo per verificare
al volo, direttamente dalla cabina, se il server è su e a quale indirizzo puntare da un altro
dispositivo, senza dover guardare la console.

Il file viene scritto **una sola volta all'avvio**, non aggiornato periodicamente: se il processo
Node muore senza essere riavviato, quella riga nel tema continuerà a mostrare l'ultimo stato noto
finché il server non riparte.

## Schema di `RealTimeResults.json`

Scritto dal tema, letto dal server Node:

```json
{
  "SongTitle": "Castle In The Sky",
  "SongArtist": "Dj Satomi",
  "Active": true,
  "P1": {
    "PlayerName": "NTES",
    "PunteggioITG": 87.65,
    "Life": 0.83,
    "FAPlus": 76,
    "Fantastic": 120,
    "Excellent": 15,
    "Great": 4,
    "Decent": 1,
    "WayOff": 0,
    "Miss": 2
  },
  "P2": { "...": "stessa struttura, solo se il secondo player ha una side attiva" }
}
```

`PunteggioITG` è la percentuale ITG (0-100), `Life` è la vita del LifeMeter normalizzata (0-1). `FAPlus` è già scorporato da `Fantastic` (non sommarli). `Active` è `true` mentre `ScreenGameplay` sta scrivendo (partita in corso), `false` sull'ultima scrittura fatta a fine canzone (`ScreenEvaluationStage`) — il frontend lo usa per distinguere un punteggio live da uno ormai vecchio, senza doverlo cancellare.

## Schema di `RealTimeResultsHistory.json`

Un array di snapshot finali (stessi campi di sopra per player, meno `Life`, che a canzone finita non ha senso, più `Holds`/`HoldsTotal`, `Rolls`/`RollsTotal`, `Mines`/`MinesTotal`), con `DateTime` e `Id` (usato per recuperare il dettaglio), senza wrapper:

```json
[
  {
    "DateTime": "2026-08-19 21:04:12",
    "Id": "2026-08-19_21_04_12",
    "SongTitle": "Castle In The Sky",
    "SongArtist": "Dj Satomi",
    "P1": { "PlayerName": "NTES", "PunteggioITG": 87.65, "FAPlus": 76, "Fantastic": 120, "Excellent": 15, "Great": 4, "Decent": 1, "WayOff": 0, "Miss": 2, "Holds": 18, "HoldsTotal": 18, "Rolls": 8, "RollsTotal": 8, "Mines": 0, "MinesTotal": 0 }
  }
]
```

## Schema di `RealTimeScoreDetails/<Id>.json`

Uno per canzone (non per player), con una entry per ogni player che ha giocato. `Offsets` è uno per nota; `tns` è uno tra `FAPlus`/`Fantastic`/`Excellent`/`Great`/`Decent`/`WayOff`/`Miss` (i miss hanno `ms: null`). `Life` sono 100 campioni equispaziati sull'intera canzone. `Stats` è già calcolato lato Lua.

```json
{
  "P1": {
    "Offsets": [ { "t": 1.234, "ms": -8.2, "tns": "FAPlus" }, { "t": 1.9, "ms": null, "tns": "Miss" } ],
    "Life": [ { "t": 0, "life": 1.0 }, { "t": 1.21, "life": 0.98 } ],
    "Stats": { "MeanOffset": -0.99, "MeanAbsError": 7.83, "StdDev3": 29.39, "MaxError": 27.03 }
  }
}
```

`StdDev3` è 3 volte la deviazione standard (il "three-sigma": circa il 99.7% dei colpi rientra in quel range), non la deviazione standard al cubo.

## Note

- `npm install` genera `node_modules/` e `package-lock.json`, entrambi ignorati da git.
- I file in `Save/RealTimeResults.json`, `Save/RealTimeResultsHistory.json` e `Save/RealTimeScoreDetails/` sono generati a runtime dal tema: non sono versionati.
- I file di dettaglio non vengono ripuliti quando una entry esce dallo storico (nessuna API di cancellazione file lato tema): si accumulano lentamente in `Save/RealTimeScoreDetails/` (poche decine di KB l'uno), puoi svuotare la cartella manualmente ogni tanto se vuoi.
