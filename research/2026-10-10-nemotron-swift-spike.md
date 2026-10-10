# Nemotron 3.5 ASR Streaming 0.6B INT8 in Swift + MLX without Xcode (spike, 2026-10-10)

Apple M5 Pro, macOS 26, Swift 6.3.3, Command Line Tools only (no `xcrun metal`). Spike code lived in
a throwaway scratch directory (not kept). Reference: an earlier private ASR benchmark of the same model.

## Verdict
Works without Xcode. SwiftPM + CLT builds the Swift code and MLX's C++ core (mlx-swift builds kernels in JIT mode);
the only missing piece, the base Metal library, comes prebuilt from the PyPI `mlx-metal` wheel matching the vendored core.

## Build recipe
| Component | Version | Commit |
|---|---|---|
| speech-swift (`exact: "0.0.28"`, product `NemotronStreamingASR`) | 0.0.28 | `231f8eb9f0971fee335fef49f42d2975e4fbf8bc` |
| mlx-swift (resolved) | 0.31.6 | `0bb916c67f4b9e5c682cbe02a42c701c93ab5021` |
| Vendored MLX core (`Source/Cmlx/mlx/.../version.h`) | 0.31.1 | `ce45c52505c8158ea48d2a54e8caae05efd86bfe` |

- `swift build -c release`: ~97 s cold. No unsafe flags/resources needed. Output is one statically linked executable.
- Without a metallib: `MLX error: Failed to load the default metallib. library not found ... stream.cpp:115`.
- Metallib: `unzip -p mlx_metal-0.31.1-py3-none-macosx_26_0_arm64.whl mlx/lib/mlx.metallib` (131,041,909 B,
  sha256 `198488eb61359e953580a9c4530400feee1a06dd2f28a930a6ffa58aec66a597`). The wheel version MUST equal the vendored core version; recheck on every mlx-swift bump.
- Placement (search order in `device.cpp`): `<exe dir>/mlx.metallib`, `<exe dir>/Resources/mlx.metallib`,
  `mlx-swift_Cmlx.bundle/default.metallib` under `Bundle.main`/all bundles, … Recommended for the app:
  `BotRecord.app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib` (verified with codesign --strict).
- First launch of a new binary: `warmUp()` ≈ 2.3 s (Metal shader cache), then ≈ 0.02 s. Call it off the main thread.

## Model bundle
`aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit` @ `5339193d26b1eda4461358c6210f5039e97af213`
(`https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit/resolve/<rev>/<file>`). Needed files only:
`model.safetensors` 767,629,118 B · `config.json` 1,718 · `vocab.json` 103,278 · `languages.json` 2,020 (verify against `checksums.json`).
Language: use **`es-US`** (slot 3, same as Python `"es"`). `es-ES`/`auto` returned empty on one clip. Unknown tags silently fall back to `auto`; validate with `model.languages.promptDictionary[tag] != nil`.

## API (speech-swift 0.0.28)
```swift
import NemotronStreamingASR
let model = try await NemotronStreamingASRMLXModel.fromDirectory(dirURL, modelId: "aufklarer/...MLX-8bit@5339193", progressHandler: nil)
try model.warmUp()
let session = try model.createSession(language: "es-US")
_ = try session.pushAudio([Float](repeating: 0, count: 5_120))   // 320 ms pre-roll (workaround 1)
for chunk in audio16kMono { for p in try session.pushAudio(chunk) { show(p.text) } }
_ = try session.pushAudio([Float](repeating: 0, count: 10_240))  // 640 ms flush (workaround 2)
let final = try session.finalize().last                           // nil when nothing decoded
```
- `PartialTranscript`: `text` (cumulative), `isFinal`, `confidence`, `words: [TimedWord]` (start/end s, 80 ms resolution).
- `pushAudio` takes any chunk size, buffers, runs one step per 5,120 samples, returns synchronously. New session after `finalize()`.
- Lookahead fixed at 320 ms (no 560/1120 ms in Swift). `fromPretrained` defaults to int5: use `fromDirectory`.
- Threading: model is `@unchecked Sendable` with one lock across sessions; a session is non-Sendable → own it from one actor/serial queue.

## Runtime issues (speech-swift, not the build)
1. Leading words dropped at stream start → push 320 ms silence first (or keep one session for the whole recording).
2. `finalize()` cuts the tail → push 640 ms of zeros before finalizing.
3. `es-ES`/`auto` empty on clip 009 → use `es-US`.

## Results (13 real rioplatense clips, 44.67 s)
| Setup | Agreement vs Python (1120 ms) | WER vs Python |
|---|---|---|
| Raw API | 70.5% | 29.0% |
| **Primed (320 ms pre + 640 ms post)** | **85.0%** | **18.0%** |

Load 0.06–0.20 s · RTF 0.053 (Python 0.029) · 14 ms per 320 ms chunk (p95 18 ms) · first partial median 0.99 s ·
final 20–50 ms after end · MLX peak 759 MB · max RSS 840 MB.
