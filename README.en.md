# SRT Tools

**[中文说明](./README.md) | English**

SRT Tools is a set of utilities for processing SubRip (.srt) subtitle files.

Developed and maintained by MontageSubs (蒙太奇字幕组), This toolkit provides scripts for common editing workflows and can be integrated into automation pipelines.


## Scripts

### [`srt_zh_en_swap.awk`](scripts/awk/srt_zh_en_swap.awk)
Swap Chinese and English lines in bilingual subtitles.
- When a cue has exactly two lines (first Chinese, second English), their positions are exchanged.
- Preserves timing, style tags, alignment, BOM, and line endings.

Usage:
````bash
awk -f srt_zh_en_swap.awk input.srt > output.srt
````

### [`srt_zh_only.awk`](scripts/awk/srt_zh_only.awk)
Remove English lines and keep only Chinese subtitles.
- Cues without Chinese are removed automatically.
- Remaining cues are renumbered in sequence.
- Preserves timing, formatting tags, BOM, and line endings.

Usage:
````bash
awk -f srt_zh_only.awk input.srt > output.srt
````

### [`srt_zh_wrap.awk`](scripts/awk/srt_zh_wrap.awk)
Split long Chinese subtitle lines into two lines for better readability.
- Splits at dialogue markers, spaces, or punctuation where possible.
- Preserves timing, formatting tags, and alignment.
- Parameters:
  - `SPLIT_THRESHOLD` (default: 20 CJK characters)
  - `BRACKET_FACTOR` (default: 2)

Usage:
````bash
awk -v SPLIT_THRESHOLD=20 -v BRACKET_FACTOR=2 -f srt_zh_wrap.awk input.srt > output.srt
````


## License
- Source code and documentation: [MIT License](./LICENSE).
- Subtitle example files (if included): [CC BY-NC-SA 4.0](./examples/LICENSE).


---

<div align="center">

**MontageSubs (蒙太奇字幕组)**

"Powered by love ❤️ 用爱发电"

</div>
