#pragma once
#include <stddef.h>
#include <stdbool.h>

typedef struct EzEQDSP EzEQDSP;
enum { EzEQBandCount = 6 };

EzEQDSP *ezeq_dsp_create(double sample_rate);
void ezeq_dsp_destroy(EzEQDSP *dsp);
void ezeq_dsp_update(EzEQDSP *dsp, const double gains[EzEQBandCount], double volume);
void ezeq_dsp_begin(EzEQDSP *dsp);
void ezeq_dsp_frame(EzEQDSP *dsp, float *left, float *right);
void ezeq_dsp_set_input_channels(EzEQDSP *dsp, unsigned channels);
bool ezeq_dsp_input_ready(EzEQDSP *dsp, unsigned channels);
bool ezeq_dsp_take_audio_activity(EzEQDSP *dsp);
