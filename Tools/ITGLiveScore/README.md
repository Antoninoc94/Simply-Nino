# ITGLiveScore

Overlay/scoreboard live per lo streaming. È un tool **esterno** al tema: gira come processo Node.js separato sullo stesso PC su cui gira ITGmania, non fa parte del bundle Lua caricato dal gioco.

## Come funziona

1. Il tema (`Modules/ITGLiveScore.lua`, opzione `Enable Live Score Export` in `Options2`) scrive lo stato live della partita in `Save/RealTimeResults.json` ogni mezzo secondo mentre si gioca `ScreenGameplay`. Quando la canzone finisce (`ScreenEvaluationStage`) appende il risultato finale a `Save/RealTimeResultsHistory.json` (ultimi 50, FIFO) e scrive un file di dettaglio per player in `Save/RealTimeScoreDetails/<Id>.json`, riusando i dati che il motore/tema già tracciano per il proprio grafico a fine canzone (`sequential_offsets` da `JudgmentOffsetTracking.lua`, `GetLifeRecord()` per la curva vita) — nessun tracking nuovo lato Lua.
2. `ITGWebAPP/server.js` legge `RealTimeResults.json` ogni 500ms e lo ritrasmette via WebSocket (porta 8081) a tutti i client connessi; espone anche `GET /history` (rilegge `RealTimeResultsHistory.json`) e `GET /history/:id` (rilegge il dettaglio corrispondente in `RealTimeScoreDetails/`).
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

## Schema di `RealTimeResults.json`

Scritto dal tema, letto dal server Node:

```json
{
  "SongTitle": "Castle In The Sky",
  "SongArtist": "Dj Satomi",
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

`PunteggioITG` è la percentuale ITG (0-100), `Life` è la vita del LifeMeter normalizzata (0-1). `FAPlus` è già scorporato da `Fantastic` (non sommarli).

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
