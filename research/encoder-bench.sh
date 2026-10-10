#!/bin/bash
cd "$(dirname "$0")"
F="-hide_banner -loglevel error -y -i src.mkv -an"
run() { name=$1; ext=$2; shift 2
  s=$(python3 -c 'import time;print(time.time())')
  ffmpeg $F "$@" out_$name.$ext || { echo "$name FAILED"; return; }
  e=$(python3 -c 'import time;print(time.time())')
  sz=$(stat -f %z out_$name.$ext)
  vmaf=$(ffmpeg -hide_banner -loglevel error -i out_$name.$ext -i src.mkv -lavfi "[0][1]libvmaf=n_threads=12:n_subsample=3:log_fmt=json:log_path=v_$name.json" -f null - && python3 -c "import json;print(round(json.load(open('v_$name.json'))['pooled_metrics']['vmaf']['mean'],2))")
  python3 -c "t=$e-$s;print(f'$name|{1320/t:.0f} fps|{t:.1f}s|{$sz/1e6:.2f} MB|{$sz*8/22/1000:.0f} kbps|VMAF $vmaf')"
}
run hevc_vt_q60 mp4 -c:v hevc_videotoolbox -q:v 60 -tag:v hvc1
run h264_vt_5M mp4 -c:v h264_videotoolbox -b:v 5M
run av1_p10_c38 webm -c:v libsvtav1 -preset 10 -crf 38
run av1_p10_c34 webm -c:v libsvtav1 -preset 10 -crf 34
run av1_p10_c38_k10s webm -c:v libsvtav1 -preset 10 -crf 38 -svtav1-params keyint=600
run av1_p8_c38_scm webm -c:v libsvtav1 -preset 8 -crf 38 -svtav1-params scm=1
run av1_rtc_p10_c38 webm -c:v libsvtav1 -preset 10 -crf 38 -svtav1-params rtc=1:scm=1
run vp9_rt8_c36 webm -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -tile-columns 2 -crf 36 -b:v 0
