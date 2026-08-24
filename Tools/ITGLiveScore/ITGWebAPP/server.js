const express = require('express');
const WebSocket = require('ws');
const fs = require('fs');
const bodyParser = require('body-parser');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const WS_PORT = process.env.WS_PORT || 8081;
// Punta alla cartella Save/ della tua installazione di ITGmania.
// Sovrascrivibile con la variabile d'ambiente ITGMANIA_SAVE_DIR.
const directory = process.env.ITGMANIA_SAVE_DIR || 'C:\\Games\\ITGmania\\Save';
const fileName = 'RealTimeResults.json';
const historyFileName = 'RealTimeResultsHistory.json';
const detailDirName = 'RealTimeScoreDetails';
// The theme builds ids from a "YYYY-MM-DD_HH_MM_SS" timestamp; only accept that shape.
const idPattern = /^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}$/;
// Middleware per leggere JSON
app.use(bodyParser.json());
app.use(express.static('public')); // Cartella per frontend

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
});

// WebSocket per realtime
const wss = new WebSocket.Server({ port: WS_PORT });
wss.on('connection', (ws) => {
  console.log('WebSocket client connesso');
});

// Lettura RealTimeResults.json ogni 500ms
setInterval(() => {
  try {
    // const jsonPath = path.join(__dirname, 'public', 'RealTimeResults.json');
    const jsonPath = path.join(directory, fileName);
    const data = fs.readFileSync(jsonPath, 'utf8');
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  } catch (err) {
    console.error('Errore lettura realtime JSON:', err.message);
  }
}, 500);
