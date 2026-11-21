#pragma once
#include <CoreAudio/CoreAudio.h>
#include "DSP.h"

OSStatus ezeq_audio_io(AudioObjectID, const AudioTimeStamp * _Nonnull,
                       const AudioBufferList * _Nonnull, const AudioTimeStamp * _Nonnull,
                       AudioBufferList * _Nonnull, const AudioTimeStamp * _Nonnull,
                       void * _Nullable);
