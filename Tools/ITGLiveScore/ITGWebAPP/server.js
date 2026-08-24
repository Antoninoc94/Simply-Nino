const express = require('express');
const WebSocket = require('ws');
const fs = require('fs');
const bodyParser = require('body-parser');
const path = require('path');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;
const WS_PORT = process.env.WS_PORT || 8081;
// Punta alla cartella Save/ della tua installazione di ITGmania.
// Sovrascrivibile con la variabile d'ambiente ITGMANIA_SAVE_DIR.
const directory = process.env.ITGMANIA_SAVE_DIR || 'C:\\Games\\ITGmania\\Save';
const fileName = 'RealTimeResults.json';
const historyFileName = 'RealTimeResultsHistory.json';
const detailDirName = 'RealTimeScoreDetails';
// Written by this server (not the theme) into the same Save/ dir, so the theme's Lua side --
// which has no way to read an absolute OS path or the machine's LAN IP itself -- can read it
// back and show a "is the server reachable, and at what address" status in its own menu.
const statusFileName = 'ITGLiveScoreServerStatus.json';
// The theme builds ids from a "YYYY-MM-DD_HH_MM_SS" timestamp; only accept that shape.
const idPattern = /^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}$/;
// Middleware per leggere JSON
app.use(bodyParser.json());
app.use(express.static('public')); // Cartella per frontend

// Indirizzi IPv4 della rete locale (non loopback, non virtuali), per sapere
// quale URL usare da un altro dispositivo sulla stessa rete (es. OBS su un altro PC).
function getLanAddresses() {
  const addresses = [];
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        addresses.push(iface.address);
      }
    }
  }
  return addresses;
}

// Dove sta guardando il server, se ci trova i file del tema, e come raggiungerlo. Condiviso
// tra l'endpoint /info e il file di stato scritto per il tema (vedi statusFileName sopra).
function buildStatus() {
  return {
    saveDir: directory,
    saveDirFound: fs.existsSync(directory),
    liveFileFound: fs.existsSync(path.join(directory, fileName)),
    port: PORT,
    wsPort: WS_PORT,
    lanAddresses: getLanAddresses(),
    updatedAt: new Date().toISOString(),
  };
}

// Piccolo endpoint diagnostico: utile per verificare a colpo d'occhio che ITGMANIA_SAVE_DIR
// sia impostato bene, anche da un altro dispositivo.
app.get('/info', (req, res) => {
  res.json(buildStatus());
});

// Scrive lo stato in Save/ una volta all'avvio, cosi' il menu "Simply Nino Options" nel tema
// puo' leggerlo e mostrare se il server e' raggiungibile e a quale indirizzo, senza che il
// tema debba sapere nulla su percorsi assoluti o IP di rete (cosa che Lua non puo' fare).
function writeStatusFile() {
  if (!fs.existsSync(directory)) return; // niente da scrivere se la cartella Save non esiste

  try {
    fs.writeFileSync(path.join(directory, statusFileName), JSON.stringify(buildStatus()));
  } catch (err) {
    console.error('Errore scrittura status file:', err.message);
  }
}

// Lo storico lo scrive il tema (Modules/ITGLiveScore.lua) direttamente in Save/;
// qui ci limitiamo a rileggerlo e servirlo alla pagina quando apre il tab History.
app.get('/history', (req, res) => {
  const jsonPath = path.join(directory, historyFileName);
  fs.readFile(jsonPath, 'utf8', (err, data) => {
    if (err) {
      if (err.code === 'ENOENT') return res.json([]);
      console.error('Errore lettura history JSON:', err.message);
      return res.status(500).json([]);
    }
    try {
      res.json(JSON.parse(data));
    } catch (parseErr) {
      console.error('History JSON non valido:', parseErr.message);
      res.status(500).json([]);
    }
  });
});

// Dettaglio di una singola play (offset per nota + curva vita), anche questo scritto dal
// tema. Il pattern sull'id blocca path traversal dato che finisce in un path su disco.
app.get('/history/:id', (req, res) => {
  if (!idPattern.test(req.params.id)) {
    return res.status(400).json({ error: 'id non valido' });
  }
  const jsonPath = path.join(directory, detailDirName, `${req.params.id}.json`);
  fs.readFile(jsonPath, 'utf8', (err, data) => {
    if (err) {
      if (err.code === 'ENOENT') return res.status(404).json({ error: 'non trovato' });
      console.error('Errore lettura dettaglio JSON:', err.message);
      return res.status(500).json({ error: 'errore lettura' });
    }
    try {
      res.json(JSON.parse(data));
    } catch (parseErr) {
      console.error('Dettaglio JSON non valido:', parseErr.message);
      res.status(500).json({ error: 'json non valido' });
    }
  });
});

// Avvio del server HTTP
app.listen(PORT, () => {
  console.log(`Web server in esecuzione su http://localhost:${PORT}`);

  console.log(`Save dir: ${directory}${fs.existsSync(directory) ? '' : '  (NON TROVATA! controlla ITGMANIA_SAVE_DIR)'}`);

  const lanAddresses = getLanAddresses();
  if (lanAddresses.length === 0) {
    console.log('Nessun indirizzo di rete locale rilevato (solo accesso da questo PC via localhost).');
  } else {
    console.log('Raggiungibile da altri dispositivi sulla stessa rete su:');
    for (const address of lanAddresses) {
      console.log(`  http://${address}:${PORT}`);
    }
  }
  console.log('(dettagli anche su /info, es. http://localhost:' + PORT + '/info)');

  writeStatusFile();
  if (!fs.existsSync(directory)) {
    console.log(`Non ho potuto scrivere ${statusFileName} in Save/ (la cartella non esiste), quindi il menu "Simply Nino Options" nel tema non trovera' lo stato del server.`);
  }
});

// WebSocket per realtime
const wss = new WebSocket.Server({ port: WS_PORT });
wss.on('connection', (ws) => {
  console.log('WebSocket client connesso');
});

// Lettura RealTimeResults.json ogni 500ms. Se il file manca in modo persistente (path
// sbagliato, o il tema non ha ancora scritto nulla) logghiamo i primi tentativi come al
// solito, poi un unico avviso riassuntivo, poi continuiamo a controllare in silenzio
// finche' non ricompare -- niente spam infinito, ma il server (e /info) restano attivi.
const MAX_LOGGED_FAILURES = 5;
let consecutiveFailures = 0;
let warnedAboutFailures = false;

setInterval(() => {
  try {
    // const jsonPath = path.join(__dirname, 'public', 'RealTimeResults.json');
    const jsonPath = path.join(directory, fileName);
    const data = fs.readFileSync(jsonPath, 'utf8');

    if (warnedAboutFailures) {
      console.log('File live ritrovato, riprendo a trasmettere normalmente.');
      warnedAboutFailures = false;
    }
    consecutiveFailures = 0;

    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  } catch (err) {
    consecutiveFailures++;

    if (consecutiveFailures <= MAX_LOGGED_FAILURES) {
      console.error('Errore lettura realtime JSON:', err.message);
    }
    if (consecutiveFailures === MAX_LOGGED_FAILURES) {
      console.error(`Il file live manca da ${MAX_LOGGED_FAILURES} tentativi: controlla ITGMANIA_SAVE_DIR (vedi /info). Continuo a controllare in silenzio finche' non ricompare.`);
      warnedAboutFailures = true;
    }
  }
}, 500);
