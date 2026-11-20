"""Stereo peaking EQ for interleaved float32 audio."""

import math
from array import array

FREQUENCIES = (60, 150, 400, 1000, 2400, 15000)
FLAT = (0.0,) * len(FREQUENCIES)
MUTE = -61.0


def peaking_coefficients(frequency, gain, rate):
    amplitude = 10 ** (gain / 40)
    angle = 2 * math.pi * frequency / rate
    alpha = math.sin(angle) / 2  # Q = 1
    a0 = 1 + alpha / amplitude
    b1 = -2 * math.cos(angle) / a0
    return ((1 + alpha * amplitude) / a0, b1, (1 - alpha * amplitude) / a0,
            b1, (1 - alpha / amplitude) / a0)


class Equalizer:
    def __init__(self, rate):
        self.rate = rate
        self.gains = None

    def process(self, data, gains, volume):
        samples = array("f")
        samples.frombytes(data)
        if gains != self.gains:
            self.gains = gains
            self.filters = [
                (peaking_coefficients(frequency, gain, self.rate), [0.0, 0.0], [0.0, 0.0])
                for frequency, gain in zip(FREQUENCIES, gains)
                if gain and frequency < self.rate / 2
            ]
        for (b0, b1, b2, a1, a2), z1, z2 in self.filters:
            for channel in range(2):
                first, second = z1[channel], z2[channel]
                for i in range(channel, len(samples), 2):
                    value = samples[i]
                    output = b0 * value + first
                    first = b1 * value - a1 * output + second
                    second = b2 * value - a2 * output
                    samples[i] = output
                z1[channel], z2[channel] = first, second
        level = 0.0 if volume == MUTE else 10 ** (volume / 20)
        for i, value in enumerate(samples):
            samples[i] = max(-1.0, min(1.0, value * level))
        return samples.tobytes()
