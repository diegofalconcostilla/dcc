# Android build

_2026-09-25._ Floor Survivors runs on Android phones (landscape, arm64, `gl_compatibility` renderer).

## Build and install

```powershell
python tools/build_android.py --send     # builds build/floor-survivors.apk and sends it to your Telegram
```

On the phone, tap the APK in Telegram, then install it. Android asks once to allow "install unknown apps" for
Telegram. The package is `com.diegogames.floorsurvivors`, so each new build replaces the last one and keeps your settings.

The build reuses the toolchain under `C:\Android` (SDK, JDK 17, debug keystore, Godot 4.7.2 export templates) set up
for `game-idea-pipeline`. The debug keystore is fine for your own phone, not for the Play Store.

## Touch controls

| Thumb | Gesture | Does |
|---|---|---|
| Left | touch and drag anywhere on the left side | move (analog joystick) |
| Right | press and hold on a spot | the laser keeps firing from Carl toward your finger; slide to follow a target |
| Right | double-tap a spot | bomb lands there |
| Either | pause button, top of the screen | Esc menu (settings, restart, quit) |

On the run-over card, tap to try again. (The first version used a drag-to-aim stick for the laser; it was hard to use on a phone, so it became point-and-hold.) There is no auto-aim and no passive attack: every hit is one you fire
(on PC too: hold right-click to keep firing the laser). Level-up and loot bonuses that fed the old auto-attack
(damage, cooldown, range, crit) now power the laser, whose base cooldown dropped from 0.5 s to 0.35 s to make up for it.

Test touch mode on the PC with `DCC_TOUCH=1` (the overlay shows; the mouse still aims the PC way).

## The System AI on the phone (optional, one-time PC setup)

The phone has no Ollama. The APK has this PC's Wi-Fi address baked in (`ollama_host.txt`, currently `10.0.0.130`),
so at home the System AI, achievements and loot use the PC's model. Away from home, or with the PC off, every call
falls back to the game's built-in content after its timeout, the same as Ollama being off.

To let the phone reach the PC's Ollama (run once; the second command needs an admin PowerShell):

```powershell
setx OLLAMA_HOST 0.0.0.0     # Ollama listens on the LAN, not just this PC; then quit and restart the Ollama app
New-NetFirewallRule -DisplayName "Ollama (LAN)" -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow -Profile Private
```

This exposes Ollama to your home network (Private profile only). Undo it with `setx OLLAMA_HOST ""` and
`Remove-NetFirewallRule -DisplayName "Ollama (LAN)"`. If the PC's IP changes, rebuild the APK
(or pass `--host <ip>`; `--host none` builds without it).

## Not verified yet

The APK was built and its contents checked, and touch mode ran error-free on the PC. It has **not** run on a real
phone: touch feel, joystick sizes, performance with a big crowd, and the LAN Ollama link are untested.
