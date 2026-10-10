# Encoder benchmark (2026-10-10, MacBook Pro M5 Pro, ffmpeg 9.0.2, SVT-AV1 4.2.0)

Source: 22 s, 1728×1080 @ 60 fps screen content (UI screens, 10 s scroll, cursor), lossless FFV1.
Speed = whole-CPU encode fps. VMAF = libvmaf mean vs source (n_subsample=3).

## Hard clip (scroll + 800×450 animated video playing inside the screen)

| Config | Speed | Size | Bitrate | VMAF |
|---|---|---|---|---|
| hevc_videotoolbox q60 (MP4) | 289 fps | 10.33 MB | 3757 kbps | 94.06 |
| h264_videotoolbox 5M (MP4) | 301 fps | 12.41 MB | 4512 kbps | 94.12 |
| SVT-AV1 p10 crf38 (WebM) | 658 fps | 6.30 MB | 2292 kbps | 98.26 |
| SVT-AV1 p10 crf34 | 633 fps | 8.50 MB | 3092 kbps | 98.43 |
| SVT-AV1 p10 crf38 keyint=600 | 631 fps | 6.20 MB | 2254 kbps | 98.19 |
| SVT-AV1 p8 crf38 scm=1 | 325 fps | 5.42 MB | 1972 kbps | 98.49 |
| SVT-AV1 rtc=1 p10 crf38 | 306 fps | 7.79 MB | 2834 kbps | 98.00 |
| libvpx-vp9 realtime cpu-used 8 crf36 | 482 fps | 9.46 MB | 3438 kbps | 97.74 |

## Easy clip (static UI + scroll + cursor)

| Config | Speed | Size | VMAF |
|---|---|---|---|
| hevc_videotoolbox q60 | 288 fps | 3.29 MB | 94.51 |
| h264_videotoolbox 5M | 299 fps | 11.90 MB | 96.58 |
| SVT-AV1 p10 crf38 | 714 fps | 0.76 MB | 98.33 |
| SVT-AV1 p8 crf38 | 389 fps | 0.70 MB | 98.48 |
| libvpx-vp9 good cpu-used 5 | 59 fps | 0.93 MB | 97.87 |

## Platform facts verified on this Mac
- VideoToolbox HW encoders: H.264, HEVC, ProRes only. No AV1/VP9 hardware encode on M5 Pro. AV1 hardware decode: yes.
- AVFoundation: WebM not playable, no thumbnail. AV1 in MP4: playable + thumbnail (hardware decode). Quick Look hung on WebM.
- SVT-AV1 warns: screen-content tools disabled at preset >= 9 (RA); "non-RTC M10+ meant for automation, artifacts may occur".
