# Why recordings look blurry on WhatsApp (2026-10-10)

Evidence: crop montages, numbers and scripts were produced in a throwaway scratch directory (not kept).

## Root causes (ranked)
1. **WhatsApp re-encodes every video to a fixed box.** A real send of `2026-10-10-17-59-57.mp4` (1948×1080, 5.09 Mb/s), read back from
   the WhatsApp Mac app's media folder (Desktop 26.40.20): Standard → 848×464 Baseline H.264 ≈ 1.1 Mb/s; HD → 1280×704 ≈ 2.5 Mb/s.
   Short edge rounded to a multiple of 16, all frames kept. On the Mac the untouched original plays, so it looks fine there.
2. **Double resampling.** The app scaled 3024 → 1728 (bilinear), then WhatsApp scaled again (bilinear). Text sharpness through a
   simulated WhatsApp HD re-encode: 0.59 (current) vs 0.69 with a single resample.
3. **Not the cause:** AV1 CRF (text SSIM 0.9910 at CRF 24 vs 0.9897 at CRF 36, file 3.0 → 1.3 MB), H.264 bitrate (12 vs 5.4 Mb/s
   identical after WhatsApp), 4:2:0 chroma (negligible). Exact 2:1 downscale (1512×944) is softer than 1728×1080.

Sources consistent with the measurement: [9to5Mac](https://9to5mac.com/2023/08/24/whatsapp-hd-videos/) (Standard ≈ 480p, HD ≈ 720p,
document keeps the original), [PhoneArena](https://www.phonearena.com/news/WhatsApps-latest-update-Now-you-can-send-videos-in-HD-quality_id150105)
(476×848 vs 718×1280), [WhatsApp blog](https://blog.whatsapp.com/reactions-2gb-file-sharing-512-groups) (files up to 2 GB).

## Fix applied
"Copy as MP4" companion fitted to WhatsApp's HD box: long edge 1280, short edge a multiple of 16, one Lanczos resize (vImage,
≈ 1.5 ms/frame), ≈ 4 Mb/s (floor 3). Through simulated WhatsApp HD: sidebar text sharpness 0.63 → 0.82, PSNR +3.7 dB, file 30% smaller.
Standard quality stays limited by WhatsApp's 848 px cap → the app tells the user to send as **HD** or as a **Document** (untouched).

## Open
Whether WhatsApp passes an in-box file through untouched, how WebM is handled (likely document-only), which copy the recipient sees.
