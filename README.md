# EzEQ

Easy to use, low profile Equaliser for Linux, Mac and Windows.

A six-band stereo equalizer for Linux desktops using PipeWire, WirePlumber, and GTK 3. The curve follows your slider positions. Closing the window keeps the audio filter running.

## Install

On Linux Mint 22 or a compatible Debian-based desktop with PipeWire 1.0 or newer, download the Debian package and open it with your package installer. From a terminal in the download directory you can also run:

```sh
sudo apt install ./EzEQ_1.1.0_all.deb
```

Launch **EzEQ** from the application menu. EzEQ restores your saved settings and selects its virtual output in the background when you log in. Use **Reset** to return all six bands and output volume to 0 dB.

Use **Save preset** to store the current sliders in one of the five slots. Click a slot once to apply it. Double-click its name, type a new one, and press Enter or click outside the box to save it. **Previous** switches back to the settings from before your last reset or preset change in the open window.

## Build and share

Run `./build-deb` from the source checkout on a system with `dpkg-deb` installed. Send the resulting file from `dist/` as a document or attach it to a GitHub Release. The installer is for Linux computers.

## macOS and Windows 11

The desktop preview provides six EQ bands, output volume, Reset, Previous, and five named presets. The app processes stereo audio from a virtual device and sends it to the physical output you choose. Run EzEQ while you want the EQ applied.

### Route desktop audio

1. **macOS** — install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole). In System Settings under Sound, select **BlackHole 2ch** as the system output. If prompted, grant EzEQ permission to access the virtual audio input.
2. **Windows 11** — install [VB-CABLE](https://vb-audio.com/Cable/). In Windows sound settings select **CABLE Input** as the system output. In EzEQ select **CABLE Output** as the virtual input.
3. In EzEQ choose the virtual input and the physical output you want, such as headphones or a USB DAC. Turn down the physical output first, then click **Start audio**. If the stream fails, check that both devices support stereo at 48 kHz or 44.1 kHz. On macOS, check the formats in Audio MIDI Setup. On Windows, check the endpoint formats and microphone access for desktop apps.
4. To return to direct audio, set the system output back to your physical device. Closing EzEQ stops the desktop preview’s audio stream.

### Run or build the preview

Install Python 3.12 with Tk support on your Mac or Windows PC, then run these commands from the project directory:

```sh
cd desktop
python -m pip install -r requirements.txt
python ezeq.py
```

To build the app on the target platform:

```sh
python -m pip install "pyinstaller>=6,<7"
python -m PyInstaller --noconfirm EzEQ.spec
```

On Windows, keep the whole `desktop/dist/EzEQ` folder together and open `EzEQ.exe`. On macOS, open `desktop/dist/EzEQ.app`. These builds are unsigned for distribution. GitHub Actions can build downloadable archives for Windows x64, Apple Silicon, and Intel Macs. The virtual audio drivers are installed separately.
