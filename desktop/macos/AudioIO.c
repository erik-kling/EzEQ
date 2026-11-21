#include "AudioIO.h"
#include <string.h>

typedef struct {
    Float32 *data;
    UInt32 stride;
    UInt32 frames;
} Channel;

static Channel channel_at(const AudioBufferList *list, UInt32 index) {
    for (UInt32 i = 0; i < list->mNumberBuffers; ++i) {
        const AudioBuffer *buffer = &list->mBuffers[i];
        if (index < buffer->mNumberChannels) {
            if (!buffer->mData) return (Channel){0};
            const UInt32 stride = buffer->mNumberChannels;
            return (Channel){(Float32 *)buffer->mData + index, stride,
                             buffer->mDataByteSize / sizeof(Float32) / stride};
        }
        index -= buffer->mNumberChannels;
    }
    return (Channel){0};
}

OSStatus ezeq_audio_io(AudioObjectID device, const AudioTimeStamp *now,
                       const AudioBufferList *input, const AudioTimeStamp *input_time,
                       AudioBufferList *output, const AudioTimeStamp *output_time, void *context) {
    (void)device; (void)now; (void)input_time; (void)output_time;
    EzEQDSP *dsp = context;
    if (!dsp) return noErr;
    UInt32 input_channels = 0;
    for (UInt32 i = 0; i < input->mNumberBuffers; ++i)
        input_channels += input->mBuffers[i].mNumberChannels;
    for (UInt32 i = 0; i < output->mNumberBuffers; ++i) {
        AudioBuffer *buffer = &output->mBuffers[i];
        if (buffer->mData) memset(buffer->mData, 0, buffer->mDataByteSize);
    }
    if (input_channels < 2 || !ezeq_dsp_input_ready(dsp, input_channels)) return noErr;
    // A tap contributes stereo channels after the aggregate subdevice channels.
    const Channel left_in = channel_at(input, input_channels - 2);
    const Channel right_in = channel_at(input, input_channels - 1);
    const Channel left_out = channel_at(output, 0);
    const Channel right_out = channel_at(output, 1);
    if (!left_in.data || !right_in.data || !left_out.data || !right_out.data) return noErr;
    UInt32 frames = left_in.frames;
    if (frames > right_in.frames) frames = right_in.frames;
    if (frames > left_out.frames) frames = left_out.frames;
    if (frames > right_out.frames) frames = right_out.frames;
    if (!frames) return noErr;
    ezeq_dsp_begin(dsp);
    for (UInt32 i = 0; i < frames; ++i) {
        Float32 left = left_in.data[i * left_in.stride];
        Float32 right = right_in.data[i * right_in.stride];
        ezeq_dsp_frame(dsp, &left, &right);
        left_out.data[i * left_out.stride] = left;
        right_out.data[i * right_out.stride] = right;
    }
    return noErr;
}
