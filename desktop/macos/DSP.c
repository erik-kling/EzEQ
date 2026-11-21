#include "DSP.h"
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    double b0, b1, b2, a1, a2;
    bool active;
} Filter;

typedef struct {
    Filter bands[EzEQBandCount];
    double level;
} Settings;

struct EzEQDSP {
    pthread_mutex_t lock;
    double sample_rate;
    Settings pending, current;
    double state[EzEQBandCount][2][2];
    unsigned input_channels;
    atomic_bool received_audio;
};

EzEQDSP *ezeq_dsp_create(double sample_rate) {
    EzEQDSP *dsp = calloc(1, sizeof(*dsp));
    if (!dsp) return NULL;
    if (pthread_mutex_init(&dsp->lock, NULL) != 0) {
        free(dsp);
        return NULL;
    }
    dsp->sample_rate = sample_rate;
    atomic_init(&dsp->received_audio, false);
    dsp->pending.level = dsp->current.level = 1;
    return dsp;
}

void ezeq_dsp_set_input_channels(EzEQDSP *dsp, unsigned channels) {
    dsp->input_channels = channels;
}

bool ezeq_dsp_input_ready(EzEQDSP *dsp, unsigned channels) {
    return channels == dsp->input_channels;
}

bool ezeq_dsp_take_audio_activity(EzEQDSP *dsp) {
    return atomic_exchange_explicit(&dsp->received_audio, false, memory_order_relaxed);
}

void ezeq_dsp_destroy(EzEQDSP *dsp) {
    if (!dsp) return;
    pthread_mutex_destroy(&dsp->lock);
    free(dsp);
}

void ezeq_dsp_update(EzEQDSP *dsp, const double gains[EzEQBandCount], double volume) {
    static const double frequencies[] = {60, 150, 400, 1000, 2400, 15000};
    Settings settings = {0};
    settings.level = volume <= -61 ? 0 : pow(10, volume / 20);
    for (size_t i = 0; i < EzEQBandCount; ++i) {
        if (!gains[i] || frequencies[i] >= dsp->sample_rate / 2) continue;
        const double a = pow(10, gains[i] / 40);
        const double w = 6.283185307179586 * frequencies[i] / dsp->sample_rate;
        const double alpha = sin(w) / 2;
        const double a0 = 1 + alpha / a;
        const double middle = -2 * cos(w) / a0;
        settings.bands[i] = (Filter){
            (1 + alpha * a) / a0, middle, (1 - alpha * a) / a0,
            middle, (1 - alpha / a) / a0, true
        };
    }
    pthread_mutex_lock(&dsp->lock);
    dsp->pending = settings;
    pthread_mutex_unlock(&dsp->lock);
}

void ezeq_dsp_begin(EzEQDSP *dsp) {
    atomic_store_explicit(&dsp->received_audio, true, memory_order_relaxed);
    if (pthread_mutex_trylock(&dsp->lock) != 0) return;
    for (size_t i = 0; i < EzEQBandCount; ++i) {
        if (dsp->current.bands[i].active != dsp->pending.bands[i].active)
            memset(dsp->state[i], 0, sizeof dsp->state[i]);
    }
    dsp->current = dsp->pending;
    pthread_mutex_unlock(&dsp->lock);
}

void ezeq_dsp_frame(EzEQDSP *dsp, float *left, float *right) {
    double samples[2] = {*left, *right};
    for (size_t i = 0; i < EzEQBandCount; ++i) {
        const Filter *f = &dsp->current.bands[i];
        if (!f->active) continue;
        for (size_t channel = 0; channel < 2; ++channel) {
            double *state = dsp->state[i][channel];
            const double input = samples[channel];
            const double output = f->b0 * input + state[0];
            state[0] = f->b1 * input - f->a1 * output + state[1];
            state[1] = f->b2 * input - f->a2 * output;
            samples[channel] = output;
        }
    }
    *left = (float)fmax(-1, fmin(1, samples[0] * dsp->current.level));
    *right = (float)fmax(-1, fmin(1, samples[1] * dsp->current.level));
}
