"""Connect a virtual stereo input to a physical stereo output."""

import sys
from threading import Event, Thread

import sounddevice as sd

from dsp import Equalizer

HOST_API = "Windows WASAPI" if sys.platform == "win32" else "Core Audio"


def devices():
    inputs, outputs = {}, {}
    host_apis = sd.query_hostapis()
    for index, device in enumerate(sd.query_devices()):
        if host_apis[device["hostapi"]]["name"] != HOST_API:
            continue
        name = device["name"]
        folded = name.casefold()
        virtual = "blackhole" in folded or "vb-audio" in folded or "cable input" in folded or "cable output" in folded
        if virtual and device["max_input_channels"] >= 2:
            inputs[f"{name} ({index})"] = index
        if not virtual and device["max_output_channels"] >= 2:
            outputs[f"{name} ({index})"] = index
    return inputs, outputs


class Audio:
    def __init__(self):
        self.thread = None
        self.stop = Event()
        self.settings = None
        self.events = None

    def start(self, source, destination, settings, events):
        self.stop.clear()
        self.settings = settings
        self.events = events
        self.thread = Thread(target=self.run, args=(source, destination), daemon=True)
        self.thread.start()

    def run(self, source, destination):
        try:
            stream = None
            for rate in (48000, 44100):
                try:
                    stream = sd.RawStream(device=(source, destination), channels=2,
                                          samplerate=rate, dtype="float32", blocksize=256)
                    break
                except sd.PortAudioError as error:
                    last_error = error
            if stream is None:
                raise last_error
            with stream:
                eq = Equalizer(rate)
                self.events.put("Audio running.")
                while not self.stop.is_set():
                    data, _ = stream.read(256)
                    gains, volume = self.settings
                    stream.write(eq.process(data, gains, volume))
        except (sd.PortAudioError, OSError) as error:
            self.events.put(f"Audio could not run. {error}")
        finally:
            self.events.put(None)
