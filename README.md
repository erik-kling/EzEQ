# EzEQ

Easy to use, low profile Equaliser for Linux, Mac and Windows.

## Download EzEQ

- **Windows 11 (Intel or AMD, x64)** — Bundled installer pending native testing. <!-- download:windows -->
- **macOS 14.2+ (Apple Silicon or Intel)** — Download pending native testing and notarization. <!-- download:macos -->
- **Linux Mint 22 and compatible PipeWire desktops** — [Build the Debian package](#linux).

Use the link for your operating system when it appears. The **Source code** archives on GitHub are for developers.

### Windows 11

Run the EzEQ installer. It includes VB-CABLE by VB-Audio, so there’s no separate download. Choose **Install Driver** if VB-CABLE Setup opens, and restart if prompted. VB-CABLE is donationware. [Support VB-Audio](https://vb-audio.com/Cable/)

Open **EzEQ** from the Start menu. Click **Open Windows Sound settings** and set the system output to **CABLE Input**. In EzEQ, choose your headphones, speakers, or DAC and click **Start audio**. Before stopping or closing EzEQ, switch Windows back to your physical output to hear audio directly.

### macOS

Open the disk image and drag **EzEQ** into Applications. Start audio in EzEQ and allow system audio capture when prompted. Choose speakers, headphones, or a DAC in **System Settings → Sound**. EzEQ uses Core Audio for routing. Click **Stop audio** or quit to return to direct playback.

### Linux

On Linux Mint 22 or a compatible Debian-based desktop with PipeWire 1.0 or newer, build and install the Debian package from the source checkout.

```sh
./build-deb
sudo apt install ./dist/EzEQ_1.1.0_all.deb
```

Open **EzEQ** from the application menu. It restores your settings at login and keeps applying them when you close the window.

## Presets and controls

Use **Save preset** to store the six bands and volume in one of five slots. Click a slot to apply it, or double-click its name to edit it. **Reset** returns all controls to 0 dB. **Previous** restores the settings from before the last reset or preset change in the open window.

## Developers

See [desktop build and release instructions](desktop/RELEASE.md) for local builds, native acceptance checks, and signing.
