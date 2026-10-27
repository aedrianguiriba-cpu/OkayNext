# OkayNext - Ableton Live MIDI Remote Script
# Starts a WebSocket server on port 9000 so the Flutter SetlistManager app
# can connect directly without any separate bridge process.
#
# Install path (copy the whole OkayNext folder there):
#   Live 11+ Windows : C:/Users/<You>/Documents/Ableton/User Library/Remote Scripts/
#   Live 10  Windows : C:/Users/<You>/AppData/Roaming/Ableton/Live x.x.x/Preferences/User Remote Scripts/
#   Live 11+ macOS   : ~/Music/Ableton/User Library/Remote Scripts/
#   Live 10  macOS   : ~/Library/Preferences/Ableton/Live x.x.x/User Remote Scripts/
#
# Then in Ableton: Preferences > Link/Tempo/MIDI > Control Surface > OkayNext
# Output can be "None". Input MUST be set to your MIDI device for MIDI learn/mapping to work.

# ---------------------------------------------------------------------------
# Inline WebSocket server (stdlib only, no extra packages)
# ---------------------------------------------------------------------------
import base64
import hashlib
import json
import queue
import socket
import struct
import os
import threading

_WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
_PORT = 9000
_BEACON_PORT = 19001   # UDP port the Flutter app listens on for discovery
_BEACON_INTERVAL = 3   # seconds between broadcasts

_MIDI_NOTE_ON = 144
_MIDI_NOTE_OFF = 128
_MIDI_CC = 176
_MIDI_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'midi_mappings.json')
_LOG_FILE  = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'midi_debug.log')


def _log(msg):
    try:
        with open(_LOG_FILE, 'a') as f:
            f.write(msg + '\n')
    except Exception:
        pass


def _get_local_ips():
    """Return all non-loopback IPv4 addresses on this machine."""
    ips = []
    # Most reliable: dummy UDP connect reveals the outbound interface IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            if not ip.startswith('127.') and ip not in ips:
                ips.append(ip)
        finally:
            s.close()
    except Exception:
        pass
    # Hostname fallback catches multi-NIC machines
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith('127.') and ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    return ips


def _try_open_firewall():
    """Best-effort: add Windows Firewall inbound rules for OkayNext ports.
    Silently does nothing if not running as Administrator or on non-Windows."""
    try:
        import subprocess, sys
        if sys.platform != 'win32':
            return
        _NO_WIN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
        for name, proto, port in [
            ('OkayNext_TCP_9000', 'TCP', '9000'),
            ('OkayNext_UDP_19001', 'UDP', '19001'),
        ]:
            subprocess.Popen(
                ['netsh', 'advfirewall', 'firewall', 'add', 'rule',
                 'name={}'.format(name),
                 'dir=in', 'action=allow',
                 'protocol={}'.format(proto),
                 'localport={}'.format(port),
                 'enable=yes'],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=_NO_WIN,
            )
    except Exception:
        pass


_SEND_TIMEOUT_S = 2


def _set_send_timeout(conn, seconds=_SEND_TIMEOUT_S):
    """Make sends time out without affecting reads (SO_SNDTIMEO)."""
    try:
        import sys
        if sys.platform == "win32":
            val = struct.pack("I", int(seconds * 1000))      # DWORD, ms
        else:
            val = struct.pack("ll", int(seconds), 0)         # struct timeval
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, val)
    except Exception:
        pass


class _WSClient:
    def __init__(self, conn):
        self.conn = conn
        self._lock = threading.Lock()
        self._dead = False

    def send(self, text):
        if self._dead:
            return
        data = text.encode("utf-8") if isinstance(text, str) else text
        n = len(data)
        if n <= 125:
            hdr = bytes([0x81, n])
        elif n <= 65535:
            hdr = struct.pack(">BBH", 0x81, 126, n)
        else:
            hdr = struct.pack(">BBQ", 0x81, 127, n)
        with self._lock:
            try:
                self.conn.sendall(hdr + data)
            except OSError:
                # Timed out or broken. A half-written frame can't be repaired,
                # so drop this client; the reader thread then cleans it up.
                self._dead = True
                try:
                    self.conn.close()
                except OSError:
                    pass

    def close(self):
        try:
            self.conn.close()
        except OSError:
            pass


class _WSServer:
    def __init__(self, port, on_connect, on_message, on_disconnect):
        self.port = port
        self._on_connect = on_connect
        self._on_message = on_message
        self._on_disconnect = on_disconnect
        self._sock = None
        self._running = False
        self._clients = []
        self._lock = threading.Lock()

    def start(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("0.0.0.0", self.port))
        self._sock.listen(8)
        self._sock.settimeout(1.0)
        self._running = True
        threading.Thread(target=self._accept, daemon=True).start()

    def stop(self):
        self._running = False
        with self._lock:
            for c in list(self._clients):
                c.close()
            self._clients.clear()
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass

    def broadcast(self, text):
        with self._lock:
            for c in list(self._clients):
                c.send(text)

    def send(self, client, text):
        client.send(text)

    def _accept(self):
        while self._running:
            try:
                conn, _ = self._sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn):
        client = _WSClient(conn)
        try:
            # Read HTTP upgrade request
            raw = b""
            conn.settimeout(5.0)
            while b"\r\n\r\n" not in raw:
                chunk = conn.recv(2048)
                if not chunk:
                    return
                raw += chunk

            key = None
            for line in raw.decode("utf-8", errors="ignore").splitlines():
                if line.lower().startswith("sec-websocket-key:"):
                    key = line.split(":", 1)[1].strip()
                    break
            if not key:
                return

            accept = base64.b64encode(
                hashlib.sha1((key + _WS_MAGIC).encode()).digest()
            ).decode()
            conn.sendall((
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "Sec-WebSocket-Accept: {}\r\n\r\n"
            ).format(accept).encode())
            conn.settimeout(None)
            _set_send_timeout(conn)

            with self._lock:
                self._clients.append(client)
            self._on_connect(client)

            # Frame loop
            while self._running:
                msg = self._read_frame(conn)
                if msg is None:
                    break
                self._on_message(client, msg)

        except Exception:
            pass
        finally:
            with self._lock:
                if client in self._clients:
                    self._clients.remove(client)
            try:
                self._on_disconnect(client)
            except Exception:
                pass
            client.close()

    @staticmethod
    def _recv_exact(conn, n):
        buf = b""
        while len(buf) < n:
            chunk = conn.recv(n - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf

    def _read_frame(self, conn):
        hdr = self._recv_exact(conn, 2)
        if hdr is None:
            return None
        b0, b1 = hdr[0], hdr[1]
        opcode = b0 & 0x0F
        if opcode == 8:
            return None
        masked = bool(b1 & 0x80)
        length = b1 & 0x7F
        if length == 126:
            ext = self._recv_exact(conn, 2)
            length = struct.unpack(">H", ext)[0] if ext else 0
        elif length == 127:
            ext = self._recv_exact(conn, 8)
            length = struct.unpack(">Q", ext)[0] if ext else 0
        mask = self._recv_exact(conn, 4) if masked else None
        payload = self._recv_exact(conn, length)
        if payload is None:
            return None
        if masked and mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode in (1, 2):
            return payload.decode("utf-8", errors="ignore")
        return None


# ---------------------------------------------------------------------------
# UDP beacon â€“ broadcasts OkayNext presence so the app can auto-discover
# ---------------------------------------------------------------------------
class _Beacon:
    """Sends a UDP broadcast every _BEACON_INTERVAL seconds so the Flutter app
    can find Ableton automatically without manual IP entry."""

    def __init__(self, ws_port):
        self._ws_port = ws_port
        self._running = False
        self._thread = None
        self._sock = None

    def start(self):
        try:
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self._running = True
            self._thread = threading.Thread(target=self._loop, daemon=True)
            self._thread.start()
        except Exception:
            pass

    def stop(self):
        self._running = False
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass

    def _loop(self):
        while self._running:
            try:
                ips = _get_local_ips()
                payload = json.dumps({
                    "service": "OkayNext",
                    "port": self._ws_port,
                    "ips": ips,
                }).encode("utf-8")
                # Limited broadcast â€” reaches all devices on the local segment
                try:
                    self._sock.sendto(payload, ("255.255.255.255", _BEACON_PORT))
                except OSError:
                    pass
                # Directed subnet broadcasts â€” more reliable with AP-isolation routers
                for ip in ips:
                    try:
                        parts = ip.split('.')
                        if len(parts) == 4:
                            broadcast = '.'.join(parts[:3]) + '.255'
                            self._sock.sendto(payload, (broadcast, _BEACON_PORT))
                    except OSError:
                        pass
            except Exception:
                pass
            # Sleep in short chunks so stop() is responsive
            for _ in range(_BEACON_INTERVAL * 10):
                if not self._running:
                    return
                threading.Event().wait(0.1)


# ---------------------------------------------------------------------------
# MIDI device discovery (best-effort, cross-platform)
# ---------------------------------------------------------------------------
_MIDI_CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'midi_config.json')


def _load_midi_config():
    try:
        with open(_MIDI_CONFIG, 'r') as f:
            return json.load(f)
    except Exception:
        return {}


def _save_midi_config(data):
    try:
        with open(_MIDI_CONFIG, 'w') as f:
            json.dump(data, f)
    except Exception:
        pass


def _get_midi_devices_indexed():
    """Return list of (index, name) for all MIDI input devices visible to the OS."""
    indexed = []

    # â”€â”€ Windows: ctypes â†’ winmm.dll â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    try:
        import ctypes, sys
        if sys.platform == 'win32':
            class _MIDIINCAPS(ctypes.Structure):
                _fields_ = [
                    ('wMid',           ctypes.c_ushort),
                    ('wPid',           ctypes.c_ushort),
                    ('vDriverVersion', ctypes.c_uint),
                    ('szPname',        ctypes.c_char * 32),
                    ('dwSupport',      ctypes.c_uint),
                ]
            winmm = ctypes.windll.winmm
            winmm.midiInGetNumDevs.restype  = ctypes.c_uint
            winmm.midiInGetNumDevs.argtypes = []
            winmm.midiInGetDevCapsA.restype  = ctypes.c_uint
            winmm.midiInGetDevCapsA.argtypes = [
                ctypes.c_uint,
                ctypes.POINTER(_MIDIINCAPS),
                ctypes.c_uint,
            ]
            n = winmm.midiInGetNumDevs()
            for i in range(n):
                caps = _MIDIINCAPS()
                if winmm.midiInGetDevCapsA(i, ctypes.byref(caps), ctypes.sizeof(caps)) == 0:
                    name = caps.szPname.decode('mbcs', errors='replace').rstrip('\x00').strip()
                    if name:
                        indexed.append((i, name))
    except Exception:
        pass
    return indexed


def _get_midi_devices():
    """Return a list of MIDI input device names visible to the OS."""
    indexed = _get_midi_devices_indexed()
    if indexed:
        return [name for _, name in indexed]

    devices = []

    # â”€â”€ Windows fallback: spawn system Python for enumeration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if not devices:
        try:
            import subprocess, sys
            if sys.platform == 'win32':
                _SCRIPT = (
                    "import ctypes\n"
                    "class C(ctypes.Structure):\n"
                    "    _fields_=[('a',ctypes.c_ushort),('b',ctypes.c_ushort),"
                    "('c',ctypes.c_uint),('d',ctypes.c_char*32),('e',ctypes.c_uint)]\n"
                    "w=ctypes.windll.winmm\n"
                    "w.midiInGetDevCapsA.argtypes=["
                    "ctypes.c_uint,ctypes.POINTER(C),ctypes.c_uint]\n"
                    "n=w.midiInGetNumDevs()\n"
                    "for i in range(n):\n"
                    "    c=C()\n"
                    "    if w.midiInGetDevCapsA(i,ctypes.byref(c),ctypes.sizeof(c))==0:\n"
                    "        nm=c.d.decode('mbcs','replace').rstrip(chr(0)).strip()\n"
                    "        if nm: print(nm)\n"
                )
                _NO_WIN = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
                for _exe in ('python', 'python3', 'py'):
                    try:
                        _out = subprocess.check_output(
                            [_exe, '-c', _SCRIPT],
                            timeout=3,
                            stderr=subprocess.DEVNULL,
                            creationflags=_NO_WIN,
                        ).decode('utf-8', errors='replace').strip()
                        for _line in _out.splitlines():
                            _nm = _line.strip()
                            if _nm and _nm not in devices:
                                devices.append(_nm)
                        if devices:
                            break
                    except Exception:
                        continue
        except Exception:
            pass

    # â”€â”€ macOS: system_profiler â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if not devices:
        try:
            import subprocess, sys
            if sys.platform == 'darwin':
                raw = subprocess.check_output(
                    ['system_profiler', 'SPMIDIDataType', '-json'], timeout=3
                ).decode('utf-8', errors='ignore')
                data = json.loads(raw)
                for item in data.get('SPMIDIDataType', []):
                    name = item.get('_name', '').strip()
                    if name:
                        devices.append(name)
        except Exception:
            pass

    return devices


# ---------------------------------------------------------------------------
# Direct MIDI reader â€” bypasses Ableton's control surface Input routing
# ---------------------------------------------------------------------------

class _MidiDirectReader:
    """Open a Windows MIDI input device directly via winmm.dll.
    The Windows callback only enqueues raw (status,data1,data2) tuples into
    a queue.Queue â€” all Python logic runs on the Ableton main thread."""

    _MIM_DATA    = 0x3C3        # wMsg for MIDI data
    _CALLBACK_FN = 0x00030000   # fdwOpen flag: callback function

    def __init__(self, midi_queue):
        # midi_queue: queue.Queue â€” shared with OkayNext.update_display
        self._queue     = midi_queue
        self._handle    = None
        self._proc      = None   # keep ctypes callback object alive
        self._proc_type = None   # keep ctypes function type alive
        self._name      = None
        try:
            import ctypes, sys
            if sys.platform == 'win32':
                self._ct    = ctypes
                self._winmm = ctypes.windll.winmm
                self._winmm.midiInOpen.restype  = ctypes.c_uint
                self._winmm.midiInStart.restype = ctypes.c_uint
                self._winmm.midiInStop.restype  = ctypes.c_uint
                self._winmm.midiInReset.restype = ctypes.c_uint
                self._winmm.midiInClose.restype = ctypes.c_uint
            else:
                self._winmm = None
        except Exception:
            self._winmm = None

    # ------------------------------------------------------------------
    def open(self, device_name):
        """Open device by name. Returns (ok:bool, msg:str)."""
        if self._winmm is None:
            return False, 'Windows MIDI API not available'
        self.close()
        indexed = _get_midi_devices_indexed()
        idx = None
        for i, name in indexed:
            if name == device_name:
                idx = i
                break
        if idx is None:
            for i, name in indexed:
                if name.lower().startswith(device_name[:10].lower()):
                    idx = i
                    break
        if idx is None:
            return False, 'Device not found: {}'.format(device_name)
        return self._open_index(idx, device_name)

    def _open_index(self, idx, name_hint):
        ct      = self._ct
        q       = self._queue
        MIM_DATA = self._MIM_DATA

        # Use WINFUNCTYPE (__stdcall) â€” correct calling convention for Win32 callbacks
        try:
            ProcType = ct.WINFUNCTYPE(
                None,
                ct.c_void_p,  # hMidiIn
                ct.c_uint,    # wMsg
                ct.c_size_t,  # dwInstance
                ct.c_size_t,  # dwParam1 (packed MIDI bytes)
                ct.c_size_t,  # dwParam2 (timestamp)
            )
        except AttributeError:
            # WINFUNCTYPE not available (non-Windows Python build)
            ProcType = ct.CFUNCTYPE(
                None, ct.c_void_p, ct.c_uint,
                ct.c_size_t, ct.c_size_t, ct.c_size_t,
            )

        # Callback does the absolute minimum: enqueue raw bytes.
        # All Python logic happens on the Ableton main thread.
        def _cb(hMidiIn, wMsg, dwInstance, dwParam1, dwParam2):
            if wMsg == MIM_DATA:
                v = int(dwParam1)
                try:
                    q.put_nowait((v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF))
                except Exception:
                    pass

        self._proc_type = ProcType
        self._proc      = ProcType(_cb)

        handle = ct.c_void_p(0)
        rc = self._winmm.midiInOpen(
            ct.byref(handle),
            ct.c_uint(idx),
            self._proc,
            ct.c_size_t(0),
            ct.c_uint(self._CALLBACK_FN),
        )
        if rc == 0:
            self._handle = handle
            self._name   = name_hint
            rc_start = self._winmm.midiInStart(handle)
            _log('MidiDirectReader opened idx={} name={} start_rc={}'.format(idx, name_hint, rc_start))
            return True, 'ok'
        if rc == 4:  # MMSYSERR_ALLOCATED â€” device exclusively locked
            return False, 'Device locked by Ableton. In Ableton Preferences â†’ Link/MIDI, set the device Track and Remote to OFF, then try again.'
        return False, 'midiInOpen failed rc={}'.format(rc)

    # ------------------------------------------------------------------
    def close(self):
        if self._handle is not None and self._winmm is not None:
            try:
                self._winmm.midiInStop(self._handle)
                self._winmm.midiInReset(self._handle)
                self._winmm.midiInClose(self._handle)
            except Exception:
                pass
        self._handle    = None
        self._name      = None
        self._proc      = None
        self._proc_type = None

    @property
    def active_device(self):
        return self._name

    @property
    def is_open(self):
        return self._handle is not None


# ---------------------------------------------------------------------------
# Ableton ControlSurface
# ---------------------------------------------------------------------------
# _Framework.ControlSurface has the traditional build_midi_map / receive_midi
# interface that all reliable community MIDI scripts use. ableton.v2 uses a
# component-element architecture that doesn't invoke these methods the same way.
try:
    from _Framework.ControlSurface import ControlSurface
except ImportError:
    from ableton.v2.control_surface import ControlSurface


class OkayNext(ControlSurface):

    @staticmethod
    def _vol_normalize(param):
        """Map Ableton's internal volume range to 0.0-1.0."""
        try:
            lo, hi = param.min, param.max
            if hi <= lo:
                return 0.0
            return max(0.0, min(1.0, (param.value - lo) / (hi - lo)))
        except Exception:
            return 0.0

    @staticmethod
    def _vol_str(param):
        """Return Ableton's own formatted string for the current volume value."""
        try:
            return param.str_for_value(param.value)
        except Exception:
            return ""

    @staticmethod
    def _vol_denormalize(param, normalized):
        """Map 0.0-1.0 back to Ableton's internal volume range."""
        try:
            lo, hi = param.min, param.max
            return lo + max(0.0, min(1.0, normalized)) * (hi - lo)
        except Exception:
            return normalized

    def _song(self):
        # ableton.v2: self.song is a property (not callable)
        # _Framework:  self.song() is a method
        s = self.song
        return s() if callable(s) else s

    def __init__(self, c_instance):
        super(OkayNext, self).__init__(c_instance)
        _log('OkayNext init base={}'.format(ControlSurface.__module__))
        self._cmd_queue = queue.Queue()
        self._setlist = []       # ordered locator names sent by Flutter
        self._active_name = None # which song is currently "active" in the setlist
        self._advance_flag = False  # set by _position_changed, consumed by update_display
        self._midi_mappings = self._load_midi_mappings()
        self._midi_learn_active = False
        self._midi_learn_tick = 0      # timeout counter â€” see update_display
        self._midi_monitor = False
        self._midi_map_ok = False
        self._midi_map_count = 0
        self._midi_map_called = False
        self._midi_recv_count = 0      # diagnostic: counts receive_midi calls
        self._last_master_volume = None  # polled each update_display tick
        self._last_cue_volume = None    # polled each update_display tick
        self._direct_queue = queue.Queue()  # filled by _MidiDirectReader callback (Windows thread)
        self._midi_reader = _MidiDirectReader(self._direct_queue)
        self._ws = _WSServer(
            port=_PORT,
            on_connect=self._ws_connect,
            on_message=self._ws_message,
            on_disconnect=self._ws_disconnect,
        )
        self._beacon = _Beacon(ws_port=_PORT)
        _try_open_firewall()
        with self.component_guard():
            self._add_listeners()
        self._ws.start()
        self._beacon.start()
        # Auto-open MIDI device saved from last session
        try:
            cfg = _load_midi_config()
            saved = cfg.get('active_device')
            if saved:
                ok, msg = self._midi_reader.open(saved)
                _log('auto-open device={} ok={} msg={}'.format(saved, ok, msg))
        except Exception as e:
            _log('auto-open error: {}'.format(e))

    # ------------------------------------------------------------------ #
    # Ableton lifecycle
    # ------------------------------------------------------------------ #

    def _drain_direct_queue(self):
        """Called from update_display (main thread) to process direct MIDI input."""
        try:
            while True:
                midi_bytes = self._direct_queue.get_nowait()
                self._midi_recv_count += 1
                if self._midi_recv_count <= 5:
                    _log('direct_midi #{} bytes={}'.format(self._midi_recv_count, midi_bytes))
                    # Tell Flutter MIDI is alive on the first few messages
                    self._ws.broadcast(json.dumps({
                        'type': 'midi_status',
                        'map_called': self._midi_map_called,
                        'map_ok': self._midi_map_ok,
                        'map_count': self._midi_map_count,
                        'mappings': len(self._midi_mappings),
                        'recv_count': self._midi_recv_count,
                        'reader_open': self._midi_reader.is_open,
                        'reader_device': self._midi_reader.active_device,
                    }))
                self._dispatch_midi_bytes(midi_bytes)
        except queue.Empty:
            pass
        except Exception as e:
            _log('drain_direct_queue error: {}'.format(e))

    def disconnect(self):
        self._midi_reader.close()
        self._beacon.stop()
        self._ws.stop()
        self._remove_listeners()
        super(OkayNext, self).disconnect()

    def update_display(self):
        """Called ~100 ms by Ableton on the main thread."""
        # â”€â”€ Direct MIDI queue (from _MidiDirectReader Windows callback thread) â”€â”€
        self._drain_direct_queue()

        # â”€â”€ Auto-advance: follow the playhead when it crosses a locator boundary â”€
        # Only updates _active_name â€” never jumps the playhead.
        # The playhead is already where it should be; Flutter UI follows via
        # the `position` broadcasts from _position_changed.
        if self._advance_flag:
            self._advance_flag = False
            try:
                s = self._song()
                pos = float(s.current_song_time)
                current = self._current_locator_name(s, pos)
                if current is not None:
                    self._active_name = current
            except Exception:
                pass

        # â”€â”€ Volume polls (fallback in case value listeners aren't registered) â”€â”€
        try:
            s = self._song()
            mv = round(self._vol_normalize(s.master_track.mixer_device.volume), 4)
            if mv != self._last_master_volume:
                self._last_master_volume = mv
                param = s.master_track.mixer_device.volume
                self._ws.broadcast(json.dumps({
                    "type": "master_volume",
                    "value": mv,
                    "label": self._vol_str(param),
                }))
        except Exception:
            pass
        try:
            s = self._song()
            cv = round(self._vol_normalize(s.master_track.mixer_device.cue_volume), 4)
            if cv != self._last_cue_volume:
                self._last_cue_volume = cv
                param = s.master_track.mixer_device.cue_volume
                self._ws.broadcast(json.dumps({
                    "type": "cue_volume",
                    "value": cv,
                    "label": self._vol_str(param),
                }))
        except Exception:
            pass

        # â”€â”€ MIDI learn timeout â€” auto-cancel after ~20 s of no input â”€â”€â”€â”€â”€â”€
        if self._midi_learn_active:
            self._midi_learn_tick += 1
            if self._midi_learn_tick >= 200:   # 200 Ã— 100 ms = 20 s
                self._midi_learn_active = False
                self._midi_learn_tick = 0
                _log('learn timeout â€” auto-cancelled')
                try:
                    self.request_rebuild_midi_map()
                except Exception:
                    pass
        else:
            self._midi_learn_tick = 0

        # â”€â”€ Drain command queue â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        for _ in range(32):
            try:
                cmd = self._cmd_queue.get_nowait()
            except queue.Empty:
                break
            try:
                cmd()
            except Exception:
                pass

    # ------------------------------------------------------------------ #
    # Song listeners (all called on Ableton's main thread)
    # ------------------------------------------------------------------ #

    def _add_listeners(self):
        s = self._song()
        s.add_is_playing_listener(self._state_changed)
        s.add_tempo_listener(self._tempo_changed)
        s.add_record_mode_listener(self._state_changed)
        s.add_loop_listener(self._state_changed)
        s.add_signature_numerator_listener(self._state_changed)
        s.add_signature_denominator_listener(self._state_changed)
        s.add_current_song_time_listener(self._position_changed)
        s.add_cue_points_listener(self._cues_changed)
        try:
            s.master_track.mixer_device.volume.add_value_listener(self._master_volume_changed)
        except Exception:
            pass
        try:
            s.master_track.mixer_device.cue_volume.add_value_listener(self._cue_volume_changed)
        except Exception:
            pass
        self._attach_track_listeners(s)

    def _attach_track_listeners(self, s):
        for t in s.tracks:
            try:
                if not t.mute_has_listener(self._tracks_changed):
                    t.add_mute_listener(self._tracks_changed)
            except Exception:
                pass

    def _remove_listeners(self):
        try:
            s = self._song()
            s.remove_is_playing_listener(self._state_changed)
            s.remove_tempo_listener(self._tempo_changed)
            s.remove_record_mode_listener(self._state_changed)
            s.remove_loop_listener(self._state_changed)
            s.remove_signature_numerator_listener(self._state_changed)
            s.remove_signature_denominator_listener(self._state_changed)
            s.remove_current_song_time_listener(self._position_changed)
            s.remove_cue_points_listener(self._cues_changed)
            try:
                s.master_track.mixer_device.volume.remove_value_listener(self._master_volume_changed)
            except Exception:
                pass
            try:
                s.master_track.mixer_device.cue_volume.remove_value_listener(self._cue_volume_changed)
            except Exception:
                pass
            for t in s.tracks:
                try:
                    if t.mute_has_listener(self._tracks_changed):
                        t.remove_mute_listener(self._tracks_changed)
                except Exception:
                    pass
        except Exception:
            pass

    def _position_changed(self):
        """Lightweight tick on every beat. Sets advance flag if song boundary crossed."""
        try:
            s = self._song()
            pos = float(s.current_song_time)
            current = self._current_locator_name(s, pos)
            playing = bool(s.is_playing)
            # Flag an active-name update for update_display (safe main-thread context)
            if not self._advance_flag and playing and current != self._active_name:
                self._advance_flag = True
            self._ws.broadcast(json.dumps({
                "type": "position",
                "playing": playing,
                "locator": current,
                "beat": pos,
            }))
        except Exception:
            pass

    def _tempo_changed(self):
        try:
            self._ws.broadcast(json.dumps({
                "type": "bpm",
                "bpm": float(self._song().tempo),
            }))
        except Exception:
            pass

    def _state_changed(self):
        try:
            self._ws.broadcast(json.dumps(self._build_state()))
        except Exception:
            pass

    def _cues_changed(self):
        try:
            self._ws.broadcast(json.dumps(self._build_state()))
            self._ws.broadcast(json.dumps(self._build_locators()))
        except Exception:
            pass

    def _tracks_changed(self):
        self._ws.broadcast(json.dumps(self._build_tracks()))

    def _master_volume_changed(self):
        try:
            param = self._song().master_track.mixer_device.volume
            self._ws.broadcast(json.dumps({
                "type": "master_volume",
                "value": self._vol_normalize(param),
                "label": self._vol_str(param),
            }))
        except Exception:
            pass

    def _cue_volume_changed(self):
        try:
            param = self._song().master_track.mixer_device.cue_volume
            self._ws.broadcast(json.dumps({
                "type": "cue_volume",
                "value": self._vol_normalize(param),
                "label": self._vol_str(param),
            }))
        except Exception:
            pass

    # ------------------------------------------------------------------ #
    # WebSocket callbacks (run in background threads â†’ queue to main thread)
    # ------------------------------------------------------------------ #

    def _ws_connect(self, client):
        def _init():
            s = self._song()
            try:
                self._ws.send(client, json.dumps({
                    "type": "bpm",
                    "bpm": float(s.tempo),
                }))
            except Exception:
                pass
            try:
                self._ws.send(client, json.dumps(self._build_state()))
            except Exception:
                pass
            self._send_volumes(client)
            if self._setlist:
                try:
                    self._ws.send(client, json.dumps({
                        "type": "setlist", "names": self._setlist}))
                except Exception:
                    pass
            self._ws.send(client, json.dumps(self._build_locators()))
            self._ws.send(client, json.dumps({
                'type': 'midi_mappings',
                'data': self._midi_mappings,
            }))
            self._ws.send(client, json.dumps({
                'type': 'midi_devices',
                'data': _get_midi_devices(),
                'active': self._midi_reader.active_device,
            }))
            self._ws.send(client, json.dumps({
                'type': 'midi_status',
                'map_called': self._midi_map_called,
                'map_ok': self._midi_map_ok,
                'map_count': self._midi_map_count,
                'mappings': len(self._midi_mappings),
            }))
            self._ws.send(client, json.dumps(self._build_tracks()))
        self._cmd_queue.put(_init)

    def _ws_message(self, client, text):
        def _handle():
            self._dispatch(client, text)
        self._cmd_queue.put(_handle)

    def _ws_disconnect(self, client):
        pass

    # ------------------------------------------------------------------ #
    # Command dispatcher (runs on main thread via queue)
    # ------------------------------------------------------------------ #

    def _dispatch(self, client, text):
        try:
            msg = json.loads(text)
        except Exception:
            return
        t = msg.get("type", "")
        s = self._song()

        if t == "play":
            try:
                if self._active_name:
                    for cp in s.cue_points:
                        if cp.name == self._active_name:
                            cp.jump()
                            break
            except Exception:
                pass
            s.start_playing()
        elif t == "stop":
            s.stop_playing()
            try:
                if self._active_name:
                    for cp in s.cue_points:
                        if cp.name == self._active_name:
                            cp.jump()
                            break
            except Exception:
                pass
        elif t == "record":
            s.record_mode = not s.record_mode
        elif t == "set_bpm":
            s.tempo = float(msg.get("bpm", s.tempo))
        elif t == "set_setlist":
            self._setlist = list(msg.get("names", []))
            # Let read-only viewers (the phone/browser monitor) mirror it.
            try:
                self._ws.broadcast(json.dumps({
                    "type": "setlist", "names": self._setlist}))
            except Exception:
                pass
            # Bootstrap active name from current position if not already set
            if not self._active_name or self._active_name not in self._setlist:
                try:
                    pos = float(s.current_song_time)
                    self._active_name = self._current_locator_name(s, pos)
                except Exception:
                    pass
        elif t == "set_active_song":
            self._active_name = msg.get("name")
            self._advance_flag = False
        elif t == "enable_loop":
            try:
                if self._active_name:
                    cues = sorted(s.cue_points, key=lambda c: c.time)
                    active_time = None
                    next_time = None
                    for i, cp in enumerate(cues):
                        if cp.name == self._active_name:
                            active_time = float(cp.time)
                            if i + 1 < len(cues):
                                next_time = float(cues[i + 1].time)
                            break
                    if active_time is not None:
                        s.loop_start = active_time
                        if next_time is not None:
                            s.loop_length = next_time - active_time
            except Exception:
                pass
            s.loop = True
            try:
                self._ws.send(client, json.dumps(self._build_state()))
            except Exception:
                pass
        elif t == "disable_loop":
            s.loop = False
            try:
                self._ws.send(client, json.dumps(self._build_state()))
            except Exception:
                pass
        elif t == "jump_to_bar":
            bar = int(msg.get("bar", 1))
            s.current_song_time = float(max(0, (bar - 1) * s.signature_numerator))
        elif t == "jump_to_locator":
            name = msg.get("name", "")
            for cp in s.cue_points:
                if cp.name == name:
                    cp.jump()  # sets arrange position + play-start position (like Ableset 3)
                    self._active_name = name
                    self._advance_flag = False
                    break
        elif t == "get_state":
            try:
                self._ws.send(client, json.dumps({
                    "type": "bpm",
                    "bpm": float(s.tempo),
                }))
            except Exception:
                pass
            try:
                self._ws.send(client, json.dumps(self._build_state()))
            except Exception:
                pass
            self._send_volumes(client)
        elif t == "get_locators":
            self._ws.send(client, json.dumps(self._build_locators()))
        elif t == "get_tracks":
            self._ws.send(client, json.dumps(self._build_tracks()))
        elif t == "get_vol_label":
            idx = int(msg.get("index", -1))
            vol = float(msg.get("volume", 1.0))
            tracks = list(s.tracks)
            if 0 <= idx < len(tracks):
                param = tracks[idx].mixer_device.volume
                raw = self._vol_denormalize(param, vol)
                try:
                    label = param.str_for_value(raw)
                except Exception:
                    label = ""
                self._ws.send(client, json.dumps({
                    "type": "vol_label",
                    "index": idx,
                    "label": label,
                }))
        elif t == "mute_track":
            idx = int(msg.get("index", -1))
            tracks = list(s.tracks)
            if 0 <= idx < len(tracks):
                tracks[idx].mute = not tracks[idx].mute
                self._ws.broadcast(json.dumps(self._build_tracks()))
        elif t == "solo_track":
            idx = int(msg.get("index", -1))
            tracks = list(s.tracks)
            if 0 <= idx < len(tracks):
                tracks[idx].solo = not tracks[idx].solo
                self._ws.broadcast(json.dumps(self._build_tracks()))
        elif t == "set_master_volume":
            vol = float(msg.get("volume", 1.0))
            param = s.master_track.mixer_device.volume
            param.value = self._vol_denormalize(param, vol)
            try:
                self._ws.send(client, json.dumps({
                    "type": "master_vol_label",
                    "label": param.str_for_value(param.value),
                }))
            except Exception:
                pass
        elif t == "set_cue_volume":
            vol = float(msg.get("volume", 1.0))
            param = s.master_track.mixer_device.cue_volume
            param.value = self._vol_denormalize(param, vol)
            try:
                self._ws.send(client, json.dumps({
                    "type": "cue_vol_label",
                    "label": param.str_for_value(param.value),
                }))
            except Exception:
                pass
        elif t == "set_track_volume":
            idx = int(msg.get("index", -1))
            vol = float(msg.get("volume", 1.0))
            tracks = list(s.tracks)
            if 0 <= idx < len(tracks):
                param = tracks[idx].mixer_device.volume
                param.value = self._vol_denormalize(param, vol)
                try:
                    self._ws.send(client, json.dumps({
                        "type": "vol_label",
                        "index": idx,
                        "label": param.str_for_value(param.value),
                    }))
                except Exception:
                    pass
        elif t == "debug":
            try:
                cues = list(s.cue_points)
                cue_names = []
                for cp in cues:
                    try:
                        cue_names.append("{} @ {}".format(cp.name, round(cp.time, 2)))
                    except Exception:
                        cue_names.append("(error)")
                self._ws.send(client, json.dumps({
                    "type": "debug",
                    "project": getattr(s, 'name', None) or '',
                    "cue_count": len(cues),
                    "cue_names": cue_names,
                    "track_count": len(list(s.tracks)),
                    "is_playing": bool(s.is_playing),
                    "midi_map_ok": self._midi_map_ok,
                    "midi_map_count": self._midi_map_count,
                    "midi_mappings": len(self._midi_mappings),
                }))
            except Exception as e:
                self._ws.send(client, json.dumps({"type": "debug", "error": str(e)}))
        elif t == "ping":
            self._ws.send(client, json.dumps({"type": "pong"}))
        elif t == "get_midi_mappings":
            self._ws.send(client, json.dumps({
                'type': 'midi_mappings',
                'data': self._midi_mappings,
            }))
        elif t == "set_midi_mappings":
            self._midi_mappings = list(msg.get('data', []))
            self._save_midi_mappings()
            try:
                self.request_rebuild_midi_map()
            except Exception:
                pass
        elif t == "start_midi_learn":
            self._midi_learn_active = True
            self._midi_learn_tick = 0
            try:
                self.request_rebuild_midi_map()
            except Exception:
                pass
            self._ws.send(client, json.dumps({
                'type': 'midi_status',
                'map_called': self._midi_map_called,
                'map_ok': self._midi_map_ok,
                'map_count': self._midi_map_count,
                'mappings': len(self._midi_mappings),
            }))
        elif t == "stop_midi_learn":
            self._midi_learn_active = False
            try:
                self.request_rebuild_midi_map()
            except Exception:
                pass
        elif t == "get_midi_devices":
            self._ws.send(client, json.dumps({
                'type': 'midi_devices',
                'data': _get_midi_devices(),
                'active': self._midi_reader.active_device,
            }))
        elif t == "set_midi_device":
            name = msg.get('name', '')
            if name:
                ok, err = self._midi_reader.open(name)
                cfg = _load_midi_config()
                cfg['active_device'] = name if ok else cfg.get('active_device')
                _save_midi_config(cfg)
                _log('set_midi_device name={} ok={} err={}'.format(name, ok, err))
                self._ws.broadcast(json.dumps({
                    'type': 'midi_devices',
                    'data': _get_midi_devices(),
                    'active': self._midi_reader.active_device,
                    'error': None if ok else err,
                }))
            else:
                self._midi_reader.close()
                cfg = _load_midi_config()
                cfg['active_device'] = None
                _save_midi_config(cfg)
                self._ws.broadcast(json.dumps({
                    'type': 'midi_devices',
                    'data': _get_midi_devices(),
                    'active': None,
                }))
        elif t == "start_midi_monitor":
            self._midi_monitor = True
            try:
                self.request_rebuild_midi_map()
            except Exception:
                pass
        elif t == "stop_midi_monitor":
            self._midi_monitor = False
            try:
                self.request_rebuild_midi_map()
            except Exception:
                pass
        elif t == "get_midi_status":
            self._ws.send(client, json.dumps({
                'type': 'midi_status',
                'map_called': self._midi_map_called,
                'map_ok': self._midi_map_ok,
                'map_count': self._midi_map_count,
                'mappings': len(self._midi_mappings),
                'recv_count': self._midi_recv_count,
                'reader_open': self._midi_reader.is_open,
                'reader_device': self._midi_reader.active_device,
            }))
        elif t == "get_debug_log":
            try:
                with open(_LOG_FILE, 'r') as f:
                    lines = f.readlines()
                content = ''.join(lines[-60:])  # last 60 lines
            except Exception:
                content = '(no log yet)'
            self._ws.send(client, json.dumps({'type': 'debug_log', 'content': content}))
        elif t == "clear_debug_log":
            try:
                open(_LOG_FILE, 'w').close()
            except Exception:
                pass

    # ------------------------------------------------------------------ #
    # MIDI mappings
    # ------------------------------------------------------------------ #

    def _load_midi_mappings(self):
        try:
            _log('load mappings from: {}'.format(_MIDI_FILE))
            with open(_MIDI_FILE, 'r') as f:
                data = json.load(f)
            _log('load ok count={}'.format(len(data)))
            return data
        except Exception as e:
            _log('load mappings error: {}'.format(e))
            return []

    def _save_midi_mappings(self):
        try:
            _log('save mappings count={} to {}'.format(len(self._midi_mappings), _MIDI_FILE))
            with open(_MIDI_FILE, 'w') as f:
                json.dump(self._midi_mappings, f)
        except Exception as e:
            _log('save mappings error: {}'.format(e))

    def build_midi_map(self, midi_map_handle):
        self._midi_map_ok = False
        self._midi_map_count = 0
        self._midi_map_called = True
        self._midi_recv_count = 0  # reset diagnostic counter each time map is rebuilt
        _log('build_midi_map called learn={} monitor={} mappings={}'.format(
            self._midi_learn_active, self._midi_monitor, len(self._midi_mappings)))
        try:
            import Live
            handle = self._c_instance.handle()
        except Exception as e:
            _log('build_midi_map early exit: {}'.format(e))
            return

        if self._midi_learn_active or self._midi_monitor or not self._midi_mappings:
            # Learn / monitor mode: forward everything so any MIDI is received
            _first_err = None
            for ch in range(16):
                for n in range(128):
                    try:
                        Live.MidiMap.forward_midi_cc(handle, midi_map_handle, ch, n)
                        self._midi_map_count += 1
                    except Exception as e:
                        if _first_err is None:
                            _first_err = str(e)
                    try:
                        Live.MidiMap.forward_midi_note(handle, midi_map_handle, ch, n, True)
                        self._midi_map_count += 1
                    except Exception:
                        pass
            if _first_err is not None:
                _log('forward_midi_cc error (first): {}'.format(_first_err))
        else:
            # Normal mode: only forward the specific messages that are mapped
            for m in self._midi_mappings:
                ch = m.get('channel', 1) - 1
                n = m.get('number', 0)
                if m.get('msg_type') == 'cc':
                    try:
                        Live.MidiMap.forward_midi_cc(handle, midi_map_handle, ch, n)
                        self._midi_map_count += 1
                    except Exception:
                        pass
                else:
                    try:
                        Live.MidiMap.forward_midi_note(handle, midi_map_handle, ch, n, True)
                        self._midi_map_count += 1
                    except Exception:
                        pass

        self._midi_map_ok = self._midi_map_count > 0
        _log('build_midi_map done map_count={} map_ok={}'.format(self._midi_map_count, self._midi_map_ok))
        self._ws.broadcast(json.dumps({
            'type': 'midi_status',
            'map_called': self._midi_map_called,
            'map_ok': self._midi_map_ok,
            'map_count': self._midi_map_count,
            'mappings': len(self._midi_mappings),
        }))

    def receive_midi(self, midi_bytes):
        # Single-message path (older _Framework / _Framework fallback)
        self._midi_recv_count += 1
        if self._midi_recv_count <= 5:
            _log('receive_midi #{} bytes={}'.format(self._midi_recv_count, midi_bytes))
        self._dispatch_midi_bytes(midi_bytes)

    def receive_midi_chunk(self, midi_chunk):
        # Batched-message path used by _Framework in Live 10+/11
        try:
            items = list(midi_chunk)
        except Exception:
            items = [midi_chunk]
        if self._midi_recv_count == 0 and items:
            _log('receive_midi_chunk first call len={} item0={}'.format(len(items), items[0] if items else None))
        for midi_bytes in items:
            self._midi_recv_count += 1
            if self._midi_recv_count <= 5:
                _log('receive_midi_chunk #{} bytes={}'.format(self._midi_recv_count, midi_bytes))
            self._dispatch_midi_bytes(midi_bytes)

    def _dispatch_midi_bytes(self, midi_bytes):
        try:
            if len(midi_bytes) < 3:
                return
            status = midi_bytes[0] if isinstance(midi_bytes[0], int) else ord(midi_bytes[0])
            channel = status & 0x0F
            opcode  = status & 0xF0
            data1   = midi_bytes[1] if isinstance(midi_bytes[1], int) else ord(midi_bytes[1])
            data2   = midi_bytes[2] if isinstance(midi_bytes[2], int) else ord(midi_bytes[2])

            if self._midi_monitor:
                self._ws.broadcast(json.dumps({
                    'type': 'midi_activity',
                    'opcode': opcode,
                    'channel': channel + 1,
                    'data1': data1,
                    'data2': data2,
                    'msg_type': 'cc' if opcode == _MIDI_CC else ('note' if opcode == _MIDI_NOTE_ON else 'other'),
                }))

            if self._midi_learn_active:
                msg_type = None
                if opcode == _MIDI_CC:
                    msg_type = 'cc'
                elif opcode == _MIDI_NOTE_ON and data2 > 0:
                    msg_type = 'note'
                if msg_type:
                    self._midi_learn_active = False
                    try:
                        self.request_rebuild_midi_map()
                    except Exception:
                        pass
                    self._ws.broadcast(json.dumps({
                        'type': 'midi_learned',
                        'msg_type': msg_type,
                        'channel': channel + 1,
                        'number': data1,
                    }))
                return

            if self._midi_recv_count <= 5:
                _log('dispatch op={} ch={} d1={} d2={} mappings={}'.format(
                    opcode, channel, data1, data2, len(self._midi_mappings)))
                for m in self._midi_mappings:
                    _log('  map ch={} n={} type={} act={}'.format(
                        m.get('channel'), m.get('number'), m.get('msg_type'), m.get('action')))
            for m in self._midi_mappings:
                if m.get('msg_type') == 'cc' and opcode != _MIDI_CC:
                    continue
                if m.get('msg_type') == 'note' and not (opcode == _MIDI_NOTE_ON and data2 > 0):
                    continue
                if m.get('channel', 1) - 1 != channel:
                    continue
                if m.get('number', 0) != data1:
                    continue
                action = m.get('action', '')
                _log('MATCH action={} value={}'.format(action, data2))
                self._cmd_queue.put(lambda a=action, v=data2: self._execute_midi_action(a, v))
                break
        except Exception as e:
            _log('_dispatch_midi_bytes exception: {}'.format(e))

    def _execute_midi_action(self, action, value=0):
        try:
            s = self._song()
            if action == 'master_volume':
                param = s.master_track.mixer_device.volume
                param.value = self._vol_denormalize(param, value / 127.0)
                return
            elif action == 'cue_volume':
                param = s.master_track.mixer_device.cue_volume
                param.value = self._vol_denormalize(param, value / 127.0)
                return
            elif action.startswith('track_volume_'):
                try:
                    idx = int(action.split('_')[-1])
                    tracks = list(s.tracks)
                    if 0 <= idx < len(tracks):
                        param = tracks[idx].mixer_device.volume
                        param.value = self._vol_denormalize(param, value / 127.0)
                except (ValueError, IndexError):
                    pass
                return
            if action == 'play':
                try:
                    if self._active_name:
                        for cp in s.cue_points:
                            if cp.name == self._active_name:
                                cp.jump()
                                break
                except Exception:
                    pass
                s.start_playing()
            elif action == 'stop':
                s.stop_playing()
                try:
                    if self._active_name:
                        for cp in s.cue_points:
                            if cp.name == self._active_name:
                                cp.jump()
                                break
                except Exception:
                    pass
            elif action == 'next':
                if self._setlist and self._active_name:
                    try:
                        idx = self._setlist.index(self._active_name)
                        if idx + 1 < len(self._setlist):
                            next_name = self._setlist[idx + 1]
                            for cp in s.cue_points:
                                if cp.name == next_name:
                                    self._active_name = next_name
                                    self._advance_flag = False
                                    cp.jump()
                                    break
                            self._ws.broadcast(json.dumps({
                                'type': 'midi_nav',
                                'active': self._active_name,
                            }))
                    except Exception:
                        pass
            elif action == 'previous':
                if self._setlist and self._active_name:
                    try:
                        idx = self._setlist.index(self._active_name)
                        if idx > 0:
                            prev_name = self._setlist[idx - 1]
                            for cp in s.cue_points:
                                if cp.name == prev_name:
                                    self._active_name = prev_name
                                    self._advance_flag = False
                                    cp.jump()
                                    break
                            self._ws.broadcast(json.dumps({
                                'type': 'midi_nav',
                                'active': self._active_name,
                            }))
                    except Exception:
                        pass
        except Exception:
            pass

    # ------------------------------------------------------------------ #
    # Message builders
    # ------------------------------------------------------------------ #

    def _current_locator_name(self, s, pos):
        """Return the name of the locator whose region contains `pos`, or None."""
        try:
            cues = sorted(s.cue_points, key=lambda c: c.time)
            name = None
            for i, cp in enumerate(cues):
                if float(cp.time) <= pos + 0.01:
                    if i + 1 >= len(cues) or float(cues[i + 1].time) > pos + 0.01:
                        name = cp.name
            return name
        except Exception:
            return None

    def _build_state(self):
        s = self._song()

        def safe(fn, default=None):
            try:
                return fn()
            except Exception:
                return default

        pos = safe(lambda: s.current_song_time, 0.0)
        sig = max(1, safe(lambda: s.signature_numerator, 4))
        bar = int(pos / sig) + 1

        current_locator = safe(lambda: self._current_locator_name(s, pos))
        mixer = safe(lambda: s.master_track.mixer_device)

        return {
            "type": "state",
            "data": {
                "playing": bool(safe(lambda: s.is_playing, False)),
                "recording": bool(safe(lambda: s.record_mode, False)),
                "bpm": float(safe(lambda: s.tempo, 120.0)),
                "current_beat": float(pos),
                "current_bar": bar,
                "current_measure": bar,
                "loop_enabled": bool(safe(lambda: s.loop, False)),
                "loop_start": float(safe(lambda: s.loop_start, 0.0)),
                "loop_end": float(safe(lambda: s.loop_start + s.loop_length, 0.0)),
                "current_locator": current_locator,
                # Song.name doesn't exist in every Live version.
                "project_name": getattr(s, 'name', None) or '',
                "time_sig_numerator": int(safe(lambda: s.signature_numerator, 4)),
                "time_sig_denominator": int(safe(lambda: s.signature_denominator, 4)),
                "master_volume": safe(lambda: self._vol_normalize(mixer.volume), 0.85),
                "master_vol_str": safe(lambda: self._vol_str(mixer.volume), ''),
                "cue_volume": safe(lambda: self._vol_normalize(mixer.cue_volume), 0.85),
                "cue_vol_str": safe(lambda: self._vol_str(mixer.cue_volume), ''),
                "server_ips": safe(_get_local_ips, []),
            },
        }

    def _send_volumes(self, client):
        """Send master/cue volume as their own messages, so the app gets the
        real fader positions on connect even if the full state is missing."""
        try:
            mixer = self._song().master_track.mixer_device
            for kind, param in (("master_volume", mixer.volume),
                                ("cue_volume", mixer.cue_volume)):
                self._ws.send(client, json.dumps({
                    "type": kind,
                    "value": round(self._vol_normalize(param), 4),
                    "label": self._vol_str(param),
                }))
        except Exception:
            pass

    def _build_locators(self):
        s = self._song()
        sig = max(1, s.signature_numerator)
        result = []
        try:
            cues = sorted(s.cue_points, key=lambda c: c.time)
            for cp in cues:
                try:
                    result.append({
                        "name": cp.name,
                        "position": float(cp.time),
                        "bar": int(cp.time / sig) + 1,
                    })
                except Exception:
                    pass
        except Exception:
            pass
        return {"type": "locators", "data": result}

    def _build_tracks(self):
        s = self._song()
        result = []
        for i, t in enumerate(s.tracks):
            try:
                result.append({
                    "index": i,
                    "name": t.name,
                    "mute": bool(t.mute),
                    "solo": bool(t.solo),
                    "arm": bool(t.arm),
                    "is_group": bool(t.is_foldable),
                    "volume": self._vol_normalize(t.mixer_device.volume),
                    "vol_str": self._vol_str(t.mixer_device.volume),
                })
            except Exception:
                pass
        return {"type": "tracks", "data": result}


# ---------------------------------------------------------------------------
# Entry point Ableton calls
# ---------------------------------------------------------------------------
def create_instance(c_instance):
    return OkayNext(c_instance)

