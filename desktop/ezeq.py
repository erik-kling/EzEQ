"""EzEQ for macOS and Windows."""

import json
import os
import sys
import tempfile
import tkinter as tk
from pathlib import Path
from queue import Empty, SimpleQueue
from tkinter import messagebox, ttk

from audio import Audio, devices
from dsp import FLAT, MUTE

LABELS = ("60 Hz", "150 Hz", "400 Hz", "1 kHz", "2.4 kHz", "15 kHz")
CONFIG_DIR = (Path(os.getenv("APPDATA") or Path.home() / "AppData/Roaming") if sys.platform == "win32"
              else Path.home() / "Library/Application Support") / "EzEQ"
CONFIG_FILE = CONFIG_DIR / "settings.json"


def values(data):
    if isinstance(data, dict):
        gains, volume = data.get("bands"), data.get("volume")
        if isinstance(gains, list) and len(gains) == len(FLAT) and all(
            type(gain) in (int, float) and -12 <= gain <= 12 for gain in gains
        ) and type(volume) in (int, float) and MUTE <= volume <= 6:
            return tuple(gains), volume
    return FLAT, 0.0


def load():
    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


class Window:
    def __init__(self, root):
        self.root = root
        root.title("EzEQ")
        root.minsize(650, 430)
        self.audio = Audio()
        self.events = SimpleQueue()
        self.previous = None
        self.click = None
        self.editing = None
        self.autosave = None
        self.changing = False
        config = load()
        gains, volume = values(config)
        self.gains = [tk.DoubleVar(value=gain) for gain in gains]
        self.volume = tk.DoubleVar(value=volume)
        self.input = tk.StringVar(value=config.get("input", ""))
        self.output = tk.StringVar(value=config.get("output", ""))
        self.status = tk.StringVar()
        saved = config.get("presets")
        self.presets = [{"name": f"Preset {i + 1}"} for i in range(5)]
        for slot, data in zip(self.presets, saved if isinstance(saved, list) else []):
            if isinstance(data, dict) and isinstance(data.get("name"), str):
                slot["name"] = data["name"][:40] or slot["name"]
                if "bands" in data:
                    slot["bands"], slot["volume"] = values(data)
        frame = ttk.Frame(root, padding=12)
        frame.pack(fill="both", expand=True)
        routes = ttk.Frame(frame)
        routes.pack(fill="x", pady=(0, 10))
        self.inputs = ttk.Combobox(routes, textvariable=self.input, state="readonly", width=24)
        self.outputs = ttk.Combobox(routes, textvariable=self.output, state="readonly", width=24)
        for widget, label in ((self.inputs, "Virtual input"), (self.outputs, "Headphones / DAC")):
            ttk.Label(routes, text=label).pack(side="top", anchor="w")
            widget.pack(side="top", fill="x")
        controls = ttk.Frame(routes)
        controls.pack(fill="x", pady=(6, 0))
        ttk.Button(controls, text="Refresh devices", command=self.refresh).pack(side="left")
        self.start_button = ttk.Button(controls, text="Start audio", command=self.toggle)
        self.start_button.pack(side="right")
        self.input.trace_add("write", self.changed)
        self.output.trace_add("write", self.changed)

        presets = ttk.Frame(frame)
        presets.pack(fill="x")
        self.entries = []
        for index in range(5):
            slot = ttk.Entry(presets, width=10, state="readonly", takefocus=True)
            slot.pack(side="left", expand=True, fill="x", padx=(0, 4))
            slot.bind("<Button-1>", lambda _, i=index: self.schedule_preset(i))
            slot.bind("<Double-Button-1>", lambda _, i=index: self.rename_preset(i))
            slot.bind("<Return>", lambda _, i=index: self.submit_preset(i))
            slot.bind("<F2>", lambda _, i=index: self.rename_preset(i))
            slot.bind("<FocusOut>", lambda _, i=index: self.finish_rename(i))
            self.entries.append(slot)
        save = ttk.Menubutton(presets, text="Save preset")
        self.save_menu = tk.Menu(save, tearoff=False)
        save.configure(menu=self.save_menu)
        save.pack(side="right")
        self.refresh_presets()

        self.graph = tk.Canvas(frame, height=64, highlightthickness=0)
        self.graph.pack(fill="x", pady=(8, 0))
        self.graph.bind("<Configure>", lambda _: self.draw())
        bands = ttk.Frame(frame)
        bands.pack(fill="both", expand=True)
        self.readouts = []
        for label, variable in zip(LABELS, self.gains):
            column = ttk.Frame(bands)
            column.pack(side="left", fill="both", expand=True)
            readout = ttk.Label(column)
            readout.pack()
            self.readouts.append(readout)
            ttk.Scale(column, from_=12, to=-12, variable=variable, orient="vertical").pack(expand=True, fill="y")
            ttk.Label(column, text=label).pack()
            variable.trace_add("write", self.changed)
        footer = ttk.Frame(frame)
        footer.pack(fill="x", pady=(8, 0))
        ttk.Label(footer, text="Volume").pack(side="left")
        ttk.Scale(footer, from_=MUTE, to=6, variable=self.volume).pack(side="left", fill="x", expand=True)
        self.volume_label = ttk.Label(footer, width=9)
        self.volume_label.pack(side="left", padx=6)
        ttk.Button(footer, text="Reset", command=lambda: self.replace((FLAT, 0))).pack(side="right")
        self.previous_button = ttk.Button(footer, text="Previous", command=self.restore_previous, state="disabled")
        self.previous_button.pack(side="right", padx=4)
        ttk.Label(frame, textvariable=self.status, wraplength=590).pack(anchor="w", pady=(6, 0))
        self.volume.trace_add("write", self.changed)
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.refresh()
        self.changed()
        root.after(50, self.poll)

    def refresh(self):
        if self.audio.thread is not None:
            return
        try:
            self.sources, self.destinations = devices()
        except (OSError, RuntimeError) as error:
            self.sources, self.destinations = {}, {}
            self.status.set(str(error))
        self.inputs.configure(values=list(self.sources))
        self.outputs.configure(values=list(self.destinations))
        if self.input.get() not in self.sources:
            self.input.set(next(iter(self.sources), ""))
        if self.output.get() not in self.destinations:
            self.output.set("")
        if not self.sources:
            self.status.set("Install and enable the virtual audio device, then reopen EzEQ.")

    def current(self):
        return tuple(round(v.get(), 1) for v in self.gains), round(self.volume.get(), 1)

    def changed(self, *_):
        if self.changing:
            return
        self.audio.settings = self.current()
        self.draw()
        if self.autosave is not None:
            self.root.after_cancel(self.autosave)
        self.autosave = self.root.after(200, self.save)

    def draw(self):
        gains, volume = self.current()
        for label, gain in zip(self.readouts, gains):
            label.configure(text=f"{gain:+.1f} dB")
        self.volume_label.configure(text="Mute" if volume == MUTE else f"{volume:+.1f} dB")
        width, height = self.graph.winfo_width(), self.graph.winfo_height()
        points = []
        margin = 8
        for i, gain in enumerate(gains):
            points.extend((width * (i + 0.5) / 6, height / 2 - gain * (height / 2 - margin) / 12))
        self.graph.delete("curve")
        self.graph.create_line(*points, smooth=True, fill="#366ca9", width=2, tags="curve")

    def replace(self, profile):
        if profile == self.current():
            return
        self.previous = self.current()
        self.previous_button.configure(state="normal")
        gains, volume = profile
        self.changing = True
        for variable, gain in zip(self.gains, gains):
            variable.set(gain)
        self.volume.set(volume)
        self.changing = False
        self.changed()

    def restore_previous(self):
        if self.previous is not None:
            self.replace(self.previous)

    def refresh_presets(self):
        self.save_menu.delete(0, "end")
        for i, (entry, slot) in enumerate(zip(self.entries, self.presets)):
            entry.configure(state="normal")
            entry.delete(0, "end")
            entry.insert(0, slot["name"])
            entry.configure(state="readonly")
            self.save_menu.add_command(label=f"{i + 1}. {slot['name']}", command=lambda i=i: self.save_preset(i))

    def schedule_preset(self, index):
        if self.editing == index:
            return
        if self.click is not None:
            self.root.after_cancel(self.click)
        self.click = self.root.after(550, lambda: self.use_preset(index))

    def use_preset(self, index):
        self.click = None
        slot = self.presets[index]
        if "bands" in slot:
            self.replace((tuple(slot["bands"]), slot["volume"]))

    def rename_preset(self, index):
        if self.click is not None:
            self.root.after_cancel(self.click)
            self.click = None
        entry = self.entries[index]
        entry.focus_set()
        self.editing = index
        entry.configure(state="normal")
        entry.selection_range(0, "end")
        return "break"

    def submit_preset(self, index):
        if self.editing == index:
            self.finish_rename(index)
        else:
            self.use_preset(index)
        return "break"

    def finish_rename(self, index):
        if self.editing != index:
            return
        self.editing = None
        name = self.entries[index].get().strip()[:40]
        if name:
            self.presets[index]["name"] = name
            self.save()
        self.refresh_presets()

    def save_preset(self, index):
        self.presets[index]["bands"], self.presets[index]["volume"] = self.current()
        self.save()

    def save(self):
        if self.autosave is not None:
            self.root.after_cancel(self.autosave)
            self.autosave = None
        gains, volume = self.current()
        data = dict(bands=gains, volume=volume, presets=self.presets,
                    input=self.input.get(), output=self.output.get())
        try:
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=CONFIG_DIR, delete=False) as file:
                temp = Path(file.name)
                try:
                    json.dump(data, file)
                except Exception:
                    file.close()
                    temp.unlink(missing_ok=True)
                    raise
            try:
                temp.replace(CONFIG_FILE)
            finally:
                temp.unlink(missing_ok=True)
        except OSError as error:
            self.status.set(f"Could not save settings. {error}")

    def toggle(self):
        if self.audio.thread is not None:
            self.audio.stop.set()
            self.start_button.configure(state="disabled")
            return
        source = self.sources.get(self.input.get())
        destination = self.destinations.get(self.output.get())
        if source is None or destination is None:
            messagebox.showinfo("EzEQ", "Choose the virtual input and your physical output first.")
            return
        self.inputs.configure(state="disabled")
        self.outputs.configure(state="disabled")
        self.start_button.configure(text="Stop audio")
        self.status.set("Starting audio…")
        self.audio.start(source, destination, self.current(), self.events)

    def poll(self):
        try:
            while True:
                event = self.events.get_nowait()
                if event is None:
                    self.audio.thread = None
                    self.start_button.configure(text="Start audio", state="normal")
                    self.inputs.configure(state="readonly")
                    self.outputs.configure(state="readonly")
                    if self.status.get() == "Audio running.":
                        self.status.set("Audio stopped.")
                else:
                    self.status.set(event)
        except Empty:
            pass
        self.root.after(50, self.poll)

    def close(self):
        if self.editing is not None:
            self.finish_rename(self.editing)
        self.save()
        self.audio.stop.set()
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    Window(root)
    root.mainloop()
