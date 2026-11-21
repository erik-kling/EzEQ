#pragma once
#include <CoreAudio/CoreAudio.h>
#include "DSP.h"

OSStatus ezeq_audio_io(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *,
                        const AudioTimeStamp *, AudioBufferList *, const AudioTimeStamp *, void *);
