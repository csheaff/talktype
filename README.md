# talktype

Push-to-talk speech-to-text for Linux. Press a hotkey to start recording, press
it again to transcribe and type the text wherever your cursor is. No GUI, no
app to keep running — just a keyboard shortcut.

- **Pluggable backends** — swap transcription models without changing anything else
- **Works everywhere** — GNOME, Sway, Hyprland, i3, X11 (or atleast, it's supposed to)
- **~160 lines of bash** — easy to read, easy to hack on

Ships with [faster-whisper](https://github.com/SYSTRAN/faster-whisper) by
default, plus an optional [Moonshine](https://huggingface.co/UsefulSensors/moonshine-base)
backend for CPU. Or bring your own — anything that reads a WAV and prints text works.

> **Note:** This project is in early development — expect rough edges. If you
> run into issues, please [open a bug](https://github.com/csheaff/talktype/issues).

## Requirements

- Linux (Wayland or X11)
- Audio recorder: [ffmpeg](https://ffmpeg.org/) (preferred) or PipeWire (`pw-record`)
- Typing tool (auto-detected, best available is used):
  - [wtype](https://github.com/atx/wtype) — Wayland (Sway, Hyprland; not GNOME)
  - [ydotool](https://github.com/ReimuNotMoe/ydotool) + `ydotoold` — Wayland & X11 (preferred with daemon)
  - [xdotool](https://github.com/jordansissel/xdotool) — X11 only (not Wayland)
  - ydotool without daemon — last resort, with warning
- [socat](https://linux.die.net/man/1/socat) (for server-backed transcription)

For the default backend (faster-whisper):
- NVIDIA GPU with CUDA (or use CPU mode — see Whisper backend options)

## Install

```bash
git clone https://github.com/csheaff/talktype.git
cd talktype
make install
```

This will:
1. Install system packages (`wtype`, `ydotool`, etc.)
2. Create a Python venv with `faster-whisper`
3. Symlink `talktype` into `~/.local/bin/`

### ydotool permissions

> **Note:** Only needed if you use ydotool. If you use wtype (Wayland) or xdotool (X11), skip this.

`ydotool` needs access to `/dev/uinput`. Add yourself to the `input` group:

```bash
sudo usermod -aG input $USER
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' | sudo tee /etc/udev/rules.d/80-uinput.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Then **reboot** for the group change to take effect.

### Pre-download model (optional)

```bash
make model
```

## Configuration

talktype reads `~/.config/talktype/config` on startup (follows `$XDG_CONFIG_HOME`).
This works everywhere — GNOME shortcuts, terminals, Sway, cron — no need to set
environment variables in each context.

```bash
mkdir -p ~/.config/talktype
cat > ~/.config/talktype/config << 'EOF'
TALKTYPE_CMD="/path/to/talktype/transcribe-server transcribe"
EOF
```

Any `TALKTYPE_*` variable can go in this file. Environment variables still work
and are applied after the config file, so they override it.

Set `TALKTYPE_TYPE_CMD` to control which typing tool is used (`auto`, `wtype`,
`ydotool`, `xdotool`, or any custom command). Default is `auto`, which picks
the best available tool: wtype (Wayland) → ydotool+daemon → xdotool (X11).

## Setup

Bind `talktype` to a keyboard shortcut:

**GNOME:** Settings → Keyboard → Keyboard Shortcuts → Custom Shortcuts
- Name: `TalkType`
- Command: `talktype` (or full path `~/.local/bin/talktype`)
- Shortcut: your choice (e.g. `Super+D`, `F11`, etc.)

**Sway / Hyprland:** Add to your config:
```
bindsym $mod+d exec talktype
```

## Usage

1. Press your shortcut → notification says "Listening..."
2. Speak
3. Press the shortcut again → transcribes and types the text at your cursor

**Cancel:** Double-press the shortcut (press twice within ~1.5 seconds) to cancel
without transcribing. You can also press the shortcut during transcription to cancel.

## Backends

Server backends auto-start on first use — the model loads once and stays in
memory for fast subsequent transcriptions.

### Whisper (default)

[faster-whisper](https://github.com/SYSTRAN/faster-whisper). Best with a GPU.
Works out of the box after `make install` with no config needed.

For faster repeated use, switch to server mode in your config:

```bash
# ~/.config/talktype/config
TALKTYPE_CMD="/path/to/talktype/transcribe-server transcribe"
```

| Variable | Default | Description |
|---|---|---|
| `WHISPER_MODEL` | `base` | `tiny`, `base`, `small`, `medium`, `large-v3-turbo` |
| `WHISPER_LANG` | `en` | Language code |
| `WHISPER_DEVICE` | `cuda` | `cuda` or `cpu` |
| `WHISPER_COMPUTE` | `float16` | `float16` (GPU), `int8` or `float32` (CPU) |

### Moonshine (CPU, lightweight)

[Moonshine](https://huggingface.co/UsefulSensors/moonshine-base) by Useful
Sensors. 61.5M params, purpose-built for CPU/edge inference.

```bash
make moonshine
```

```bash
# ~/.config/talktype/config
TALKTYPE_CMD="/path/to/talktype/backends/moonshine-server transcribe"
```

Set `MOONSHINE_MODEL=UsefulSensors/moonshine-tiny` for an even smaller 27M
param model.

### Server management

The server starts automatically on first transcription. You can also manage
it directly:

```bash
./transcribe-server start   # start manually
./transcribe-server stop    # stop the server
```

### Custom backends

Set `TALKTYPE_CMD` to any command that takes a WAV file path as its last
argument and prints text to stdout:

```bash
# ~/.config/talktype/config
TALKTYPE_CMD="/path/to/my-transcriber"
```

Your command will be called as: `$TALKTYPE_CMD /path/to/recording.wav`

It should print the transcribed text to stdout and exit. That's the only
contract — use whatever model, language, or runtime you want.

## How it works

```
[hotkey] → recording starts → [hotkey] → recording stops
                                            ↓
                                     $TALKTYPE_CMD audio.wav
                                            ↓
                                     type_text → text appears at cursor
```

The `talktype` script is ~160 lines of bash. Transcription backends are
swappable. Server mode uses Unix sockets to keep models in memory.

## License

MIT
