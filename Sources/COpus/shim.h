#include <opus/opus.h>

// opus_encoder_ctl is variadic, which Swift can't call; expose the one control BotRecord needs.
static inline int rec_opus_set_bitrate(OpusEncoder *encoder, opus_int32 bitsPerSecond) {
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitsPerSecond));
}
