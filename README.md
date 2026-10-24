# Setlist Manager for Ableton Live

A Flutter app that manages setlists during live performances and connects directly to Ableton Live — similar to Ableset 3. No extra bridge software required.

---

## How it works

```
Phone / Tablet  ──── Wi-Fi ────  SetlistBridge (inside Ableton)
  Flutter App      WebSocket          MIDI Remote Script
```

The **SetlistBridge** is a Python MIDI Remote Script that runs a WebSocket server on port 9000 *inside* Ableton Live. The Flutter app connects to it over your local Wi-Fi network.

---

## Part 1 — Install the Ableton MIDI Remote Script

### Step 1 — Find your User Remote Scripts folder

| Ableton Version | Windows | macOS |
|---|---|---|
| **Live 11 / 12** | `C:\Users\<you>\Documents\Ableton\User Library\Remote Scripts\` | `~/Music/Ableton/User Library/Remote Scripts/` |
| **Live 10** | `C:\Users\<you>\AppData\Roaming\Ableton\Live 10.x.x\Preferences\User Remote Scripts\` | `~/Library/Preferences/Ableton/Live 10.x.x/User Remote Scripts/` |

> **Tip (Windows):** Press `Win + R`, paste the path, press Enter.

### Step 2 — Copy the SetlistBridge folder

Copy the entire **`SetlistBridge`** folder from this project:

```
setlistmanager/
  ableton_remote_script/
    SetlistBridge/        ← copy this whole folder
      __init__.py
```

Paste it into your Remote Scripts folder so it looks like:

```
Remote Scripts/
  SetlistBridge/
    __init__.py
```

### Step 3 — Restart Ableton Live

Ableton only scans for scripts at startup. **Quit and reopen** Ableton completely.

### Step 4 — Select SetlistBridge as a Control Surface

1. Open **Ableton Live**
2. Go to **Preferences** (`Ctrl+,` on Windows / `Cmd+,` on macOS)
3. Click the **Link / Tempo / MIDI** tab
4. Under **Control Surface**, open the first dropdown and choose **SetlistBridge**
5. Leave **Input** and **Output** as **None**
6. Close Preferences

Ableton will now run the WebSocket server on **port 9000** in the background.

---

## Part 2 — Install the Flutter App

### Option A — Run from source (development)

Requirements: [Flutter SDK](https://docs.flutter.dev/get-started/install)

```bash
cd setlistmanager
flutter pub get
flutter run                     # USB-connected phone
flutter run -d windows          # Windows desktop
```

### Option B — Build a release APK (Android)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
# Transfer to your Android phone and install
```

### Option C — Build for iOS

```bash
flutter build ipa
# Open the .ipa in Xcode or use Apple Configurator 2 to install
```

### Option D — Build for Windows

```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

---

## Part 3 — Connect the App to Ableton

### Step 1 — Make sure both devices are on the same Wi-Fi network

Your phone/tablet and your Ableton computer must be on the **same local network**.

### Step 2 — Find your Ableton computer's IP address

**Windows:**
1. Open Command Prompt and type `ipconfig`
2. Look for **IPv4 Address** under your Wi-Fi adapter — e.g. `192.168.1.42`

**macOS:**
1. Open System Settings → Wi-Fi → click your network → note the **IP Address**

### Step 3 — Enter the IP in the app

1. Open **Setlist Manager** on your phone
2. Tap the **Settings** icon (top right)
3. Enter the **IP address** from Step 2
4. Leave port as **9000**
5. Tap **Save & Connect**

The app will connect and show a green dot. It reconnects automatically every time you open it.

---

## Troubleshooting

### SetlistBridge not appearing in the Control Surface dropdown

- Make sure the folder is named exactly **`SetlistBridge`** (capital S and B, no spaces)
- The folder must contain **`__init__.py`** directly inside it — not in a subfolder
- **Restart Ableton completely** — it only loads scripts at startup
- Check Ableton's log file for Python errors:
  - Windows: `%APPDATA%\Ableton\Live x.x.x\Preferences\Log.txt`
  - macOS: `~/Library/Preferences/Ableton/Live x.x.x/Log.txt`
  - Search for `SetlistBridge` to see if it loaded or errored

### App says "Connecting…" but never connects

- Confirm Ableton is open and **SetlistBridge is selected** in Preferences
- Confirm both devices are on the **same Wi-Fi network** (not a guest network)
- Try pinging the IP from your computer to verify it's reachable
- Check your Windows Firewall — allow port **9000** for Ableton:
  1. Search "Windows Defender Firewall" → Advanced Settings
  2. Inbound Rules → New Rule → Port → TCP → 9000 → Allow

### App connects but no transport control / wrong BPM

- Click **refresh** in the app (Settings → status card)
- Make sure you have a Live Set open in Ableton (not just the empty default session)

---

## Ableton Locators → Song Mapping

To link a song in the app to an Ableton locator:

1. In Ableton, place a **locator** (Ctrl+click the arrangement ruler) at the start of each song
2. Name the locator the **same as the song name** in the app (or any name — you can match by name)
3. In the app, edit the song → set **Locator Name** to match exactly
4. Tapping that song will jump Ableton's playhead to that locator

Alternatively you can set a **bar number** instead of a locator name.

---

## File Overview

```
setlistmanager/
├── ableton_remote_script/
│   └── SetlistBridge/
│       └── __init__.py          ← MIDI Remote Script (copy this to Ableton)
├── lib/
│   ├── main.dart
│   ├── models/                  ← Setlist, Song, AbletonState
│   ├── providers/               ← State management (Provider)
│   ├── screens/                 ← Home, Setlist, Performance, Settings
│   ├── services/                ← WebSocket client, local storage
│   └── theme/                   ← Dark theme
└── README.md
```
