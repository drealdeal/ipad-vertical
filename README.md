

https://github.com/user-attachments/assets/79cc7887-cd7d-42dc-bb95-8ab96cd36d4b

# iPad Vertical

A tiny open-source Mac menu bar app that turns an iPad into a **vertical (portrait)** second screen over Sidecar - something macOS does not offer. One click switches between vertical and horizontal.

Free, no license, about 350 lines of Swift.

## Demo

https://github.com/user-attachments/assets/5888037d-4b46-45cc-a5e2-24e5a0afda43

## Use

Build it (see below), then open `iPad Vertical.app`. It lives only in the menu bar: click the iPad icon at the top of the screen.

- **Vertical** - portrait screen shown on the iPad
- **Horizontal** - normal landscape Sidecar screen
- **Rotate 180** - turns the vertical picture upside down / back (remembered)
- **Vertical Resolution** - Larger Text (656x944), Default (820x1180), More Space (1024x1474), Most Space (1230x1770); remembered
- **Disconnect iPad**, **Quit**
- **Ctrl+Option+V** - switches between Vertical and Horizontal without opening the menu

The icon shows an upright iPad in vertical mode and a sideways one otherwise. The grey line in the menu shows the last status or error.

On the iPad, keep **Rotation Lock on**, set while the iPad is held horizontally. Without it the iPad rotates and shrinks the picture itself. The Mac cannot detect which way the iPad is held, so switching is a click or key press, not automatic.

## How it works

Sidecar only does landscape and macOS has no rotation option for it. The app:

1. Connects the iPad through Sidecar (private SidecarCore framework).
2. Creates a portrait virtual display (private CGVirtualDisplay API).
3. Captures that display with ScreenCaptureKit and draws it, rotated, in a full-screen window on the iPad's display.
4. Parks the hidden landscape Sidecar desktop corner-to-corner so the cursor does not wander into it.

## Build

```bash
./app/build.sh
```

Needs only the Xcode Command Line Tools. Source is `app/main.swift` and `app/Bridge.h`.

The app is ad-hoc signed, so after every rebuild macOS forgets its Screen Recording permission. To re-grant:

```bash
tccutil reset ScreenCapture local.doruk.ipadvertical
```

Then open the app, click Open System Settings in the prompt, turn on iPad Vertical, and reopen the app.

## Requirements

- iPad plugged in via USB, unlocked, trusted, same Apple Account as the Mac.
- Screen Recording permission for iPad Vertical (System Settings > Privacy & Security > Screen & System Audio Recording).

## Notes and limits

- Built and tested on one setup: MacBook Pro M4, macOS 27.0.1, iPad 10th gen over USB. The portrait sizes are tuned for that iPad (1180x820 Sidecar surface); other iPads work best after adjusting `resolutions` and `capturePixels` in `app/main.swift`.
- It uses private Apple APIs (CGVirtualDisplay, SidecarCore). They can change or break with any macOS update, and they rule out the Mac App Store.
- Touch and Apple Pencil input in vertical mode are untested.

## License

MIT
