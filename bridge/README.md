# Ableton Bridge Server

This folder contains the Node.js bridge server that connects the Flutter app to Ableton Live via WebSocket.

## How it works

```
Flutter App  <──WebSocket──>  Bridge Server  <──MIDI Remote Scripts──>  Ableton Live
```

## Quick Start

### 1. Install the MIDI Remote Scripts in Ableton

Copy the `AbletonJS` MIDI Remote Script into Ableton's MIDI Remote Scripts folder:

- **macOS**: `~/Library/Preferences/Ableton/Live x.x.x/User Remote Scripts/`
- **Windows**: `%APPDATA%\Ableton\Live x.x.x\Preferences\User Remote Scripts\`

Download AbletonJS from: https://github.com/leolabs/ableton-js

### 2. Enable the script in Ableton

1. Open Ableton Live → Preferences → Link/Tempo/MIDI
2. Under **Control Surface**, select `AbletonJS`
3. Set Input and Output to your MIDI device (or virtual MIDI port)

### 3. Set up the bridge server

```bash
cd bridge
npm install
node server.js
```

The server starts on port **9000** by default.

To use a different port:
```bash
node server.js --port 8080
```

## Protocol

The bridge server speaks JSON over WebSocket.

### Server → App (inbound)

```json
// Transport state update
{ "type": "state", "data": {
    "playing": true,
    "recording": false,
    "bpm": 128.0,
    "current_beat": 2.75,
    "current_bar": 5,
    "current_measure": 5,
    "loop_enabled": false,
    "loop_start": 0,
    "loop_end": 8,
    "current_locator": "Song 1"
}}

// Locators list
{ "type": "locators", "data": [
    { "name": "Intro", "position": 0.0, "bar": 1 },
    { "name": "Verse 1", "position": 8.0, "bar": 9 }
]}

// Error
{ "type": "error", "message": "Could not connect to Ableton" }

// Ping response
{ "type": "pong" }
```

### App → Server (outbound)

```json
{ "type": "play" }
{ "type": "stop" }
{ "type": "record" }
{ "type": "jump_to_bar", "bar": 9 }
{ "type": "jump_to_locator", "name": "Verse 1" }
{ "type": "set_bpm", "bpm": 120.0 }
{ "type": "enable_loop" }
{ "type": "disable_loop" }
{ "type": "get_state" }
{ "type": "get_locators" }
{ "type": "ping" }
```

## Alternative: Manual Bridge (ableton-js)

If you prefer to write your own bridge using the `ableton-js` npm package:

```bash
npm install ableton-js
```

```js
const { Ableton } = require('ableton-js');
const WebSocket = require('ws');

const ab = new Ableton({ logger: console });
const wss = new WebSocket.Server({ port: 9000 });

ab.start();

wss.on('connection', (ws) => {
  // Send state on connect
  const sendState = async () => {
    const [playing, bpm, pos] = await Promise.all([
      ab.song.get('is_playing'),
      ab.song.get('tempo'),
      ab.song.get('current_song_time'),
    ]);
    ws.send(JSON.stringify({
      type: 'state',
      data: { playing, bpm, current_beat: pos, current_bar: Math.floor(pos / 4) + 1 }
    }));
  };

  ws.on('message', async (raw) => {
    const msg = JSON.parse(raw);
    if (msg.type === 'play') await ab.song.startPlaying();
    if (msg.type === 'stop') await ab.song.stopPlaying();
    if (msg.type === 'set_bpm') await ab.song.set('tempo', msg.bpm);
    if (msg.type === 'get_state') await sendState();
    if (msg.type === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
  });
});
```

## Firewall

Make sure port 9000 (or your chosen port) is open in your firewall for connections from your phone/tablet's IP address.
