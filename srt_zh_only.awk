#!/usr/bin/awk -f
# ============================================================================
# Name: srt_zh_only.awk
# Version: 1.2
# Organization: MontageSubs (蒙太奇字幕组)
# Contributors: Meow P (小p), novaeye
# License: MIT License
# Source: https://github.com/MontageSubs/
#
# Description / 描述:
#   This AWK script processes SubRip (.srt) subtitle files and removes
#   English lines while preserving Chinese lines. If a cue contains only
#   English lines, the entire cue will be removed. After deletions, cues
#   are automatically renumbered sequentially.
#
#   本 AWK 脚本用于处理 SubRip (.srt) 字幕文件，删除英文，仅保留中文。
#   如果一个字幕块只有英文，则整块删除。删除后字幕块会自动重新编号。
#
# Features:
#   - Detects valid SRT cues (cue index + timecode line).
#   - Keeps Chinese lines and removes English lines.
#   - Removes entire cue if no Chinese line exists.
#   - Automatically renumbers cues after deletions.
#   - Preserves UTF-8 BOM handling.
#   - Supports both LF and CRLF line endings.
#   - Accepts flexible spacing in timecode lines.
#   - Preserves HTML-style tags (<i>, </i>) and music symbols.
#   - If no valid SRT structure is detected, exits with an error.
#
# 功能:
#   - 能识别有效的 SRT 字幕块（编号 + 时间轴行）。
#   - 保留中文行，删除英文行。
#   - 如果字幕块没有中文，整块删除。
#   - 删除后自动重新编号。
#   - 自动处理 UTF-8 BOM。
#   - 支持 LF 和 CRLF 换行。
#   - 时间轴行中的空格可灵活识别。
#   - 保留 HTML 风格的样式标签和音乐符号。
#   - 如果未检测到有效 SRT，脚本会报错并退出。
#
# Usage / 用法:
#   awk -f srt_zh_only.awk input.srt > output.srt
#
# Example / 示例:
#   Input cue / 输入字幕块:
#     15
#     00:01:20,000 --> 00:01:23,000
#     看来我错了
#     My mistake.
#
#   Output cue / 输出字幕块:
#     15
#     00:01:20,000 --> 00:01:23,000
#     看来我错了
# ============================================================================
################################
#   Utility Functions
#   工具函数
################################

# Detect whether a line is a valid SRT timecode.
# Format is relaxed: allows multiple spaces and trailing spaces.
# 检测一行是否是合法的 SRT 时间码。
# 格式较宽松：允许多个空格和行尾空格。
function is_timecode(line) {
    return (line ~ /^[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*-->[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*$/)
}

# Check if a line is ASCII-only (potential English).
# 检查一行是否为纯 ASCII（可能是英文）。
function is_ascii(line,    i,ch) {
    if (line == "") return 0
    for (i = 1; i <= length(line); i++) {
        ch = substr(line,i,1)
        if (!(ch >= " " && ch <= "~")) return 0
    }
    return 1
}

# Detect whether line contains any non-ASCII characters (likely CJK).
# 检测一行是否包含非 ASCII 字符（可能是中日韩文字）。
function has_nonascii(line,    i,ch) {
    for (i = 1; i <= length(line); i++) {
        ch = substr(line,i,1)
        if (!(ch >= " " && ch <= "~")) return 1
    }
    return 0
}

# Detect common CJK punctuation.
# 检测常见的中日韩标点。
function has_cjk_punct(line) {
    return (line ~ /[（），。！？：；《》「」『』“”【】、]/)
}

# Detect whether a line consists only of style tags, punctuation, or music notes.
# 检测一行是否仅包含样式标签、标点或音乐符号。
function is_style_or_music_only(line,    tmp) {
    tmp = line
    gsub(/< *\/? *[ibuIBU] *>/, "", tmp)      # remove <i>, <b>, <u> / 移除样式标签
    gsub(/\\?{[^}]*}/, "", tmp)               # remove {\anX} / 移除对齐标签
    gsub(/[[:punct:][:space:]]/, "", tmp)     # remove punctuation/spaces / 移除标点与空格
    gsub(/[♪♫♩♬]/, "", tmp)                  # remove music symbols / 移除音乐符号
    return (tmp == "")
}

# Determine whether a line should be treated as "Chinese".
# 判断一行是否应被视为“中文”。
function is_chinese_line(line) {
    if (!has_nonascii(line)) return 0
    if (has_cjk_punct(line)) return 1
    if (is_style_or_music_only(line)) return 0
    return 1
}

# Output a line with preserved line endings (LF or CRLF).
# 输出一行，保留原始换行符（LF 或 CRLF）。
function output_line(text) {
    if (useCRLF) {
        printf "%s\r\n", text
    } else {
        print text
    }
}

################################
#   Main Processing Logic
#   主处理逻辑
################################

BEGIN {
    useCRLF = 0          # default line ending mode / 默认换行符模式
    validSRT = 0         # becomes 1 if at least one valid cue is detected / 检测到有效字幕块时为 1
    firstLine = 1        # true until first line processed (for BOM check) / 第一行时为真，用于 BOM 检测
    newCueIndex = 0      # new numbering for cues / 新字幕编号计数器
}

{
    # Detect CRLF style: if line ends with \r, mark CRLF mode
    # 检测 CRLF 风格：如果行以 \r 结尾，则标记为 CRLF 模式
    if ($0 ~ /\r$/) useCRLF = 1
    sub(/\r$/, "", $0)

    # Remove UTF-8 BOM from very first line if present
    # 如果是第一行，去掉 UTF-8 BOM
    if (firstLine) {
        sub(/^\xEF\xBB\xBF/, "", $0)
        firstLine = 0
    }
}

# Case: current line is a number (potential cue index)
# 情况：当前行是数字（可能是字幕块编号）
$0 ~ /^[0-9]+$/ {
    cueIndex = $0
    if ((getline cueTimecode) > 0) {
        if (cueTimecode ~ /\r$/) useCRLF = 1
        sub(/\r$/, "", cueTimecode)
        if (is_timecode(cueTimecode)) {
            # Confirmed cue → mark as valid SRT
            # 确认是字幕块 → 标记为有效 SRT
            validSRT = 1

            # Read cue body lines until empty line or EOF
            # 读取字幕内容，直到遇到空行或文件结束
            cueLineCount = 0
            delete cueLines
            chineseFound = 0
            while ((getline cueContent) > 0) {
                if (cueContent ~ /\r$/) useCRLF = 1
                sub(/\r$/, "", cueContent)
                if (cueContent == "") break
                cueLines[++cueLineCount] = cueContent
                if (is_chinese_line(cueContent)) chineseFound = 1
            }

            # Case A: no Chinese line → skip entire cue
            # 情况 A: 没有中文行 → 跳过整个字幕块
            if (!chineseFound || cueLineCount == 0) {
                next
            }

            # Case B: has Chinese → renumber and output only Chinese lines
            # 情况 B: 有中文 → 重编号并仅输出中文行
            newCueIndex++
            output_line(newCueIndex)
            output_line(cueTimecode)

            # ---------------------------------------------
            # Preserve alignment tags {\anX}
            # 保留对齐标签 {\anX}
            #
            # If a non-Chinese line contains {\anX}, store it temporarily.
            # When the next Chinese line appears, prepend the tag to it.
            # 如果非中文行中包含 {\anX}，暂存下来。
            # 当下一条中文行出现时，把该标签拼接在中文行前。
            #
            # If the Chinese line itself already has {\anX}, use it directly.
            # 如果中文行本身已有 {\anX}，直接输出，不重复拼接。
            # ---------------------------------------------
            alignTag = ""
            for (i = 1; i <= cueLineCount; i++) {
                line = cueLines[i]

                # Extract inline alignment tag, e.g. {\an7}
                # 提取行内的对齐标签，例如 {\an7}
                tag = ""
                if (match(line, /\{\\?an[0-9]+\}/)) {
                    tag = substr(line, RSTART, RLENGTH)
                }

                if (is_chinese_line(line)) {
                    if (match(line, /\{\\?an[0-9]+\}/)) {
                        # Chinese line already has tag → output directly
                        # 中文行本身已有对齐标签 → 直接输出
                        output_line(line)
                        alignTag = ""
                    } else if (alignTag != "") {
                        # Use stored tag → prepend to Chinese line
                        # 使用缓存的对齐标签 → 拼接到中文行前
                        output_line(alignTag line)
                        alignTag = ""
                    } else {
                        # No tag involved → output as is
                        # 没有涉及对齐标签 → 原样输出
                        output_line(line)
                    }
                } else {
                    # Non-Chinese line with tag → store it
                    # 非中文行有对齐标签 → 暂存
                    if (tag != "") {
                        alignTag = tag
                    }
                    # Otherwise skip English or style-only lines
                    # 否则跳过英文或仅样式行
                }
            }

            output_line("")
            next
        } else {
            # Not a timecode → not a valid cue, output both lines as is
            # 如果不是时间码 → 非字幕块，按原样输出
            output_line(cueIndex)
            output_line(cueTimecode)
            next
        }
    } else {
        # Index followed by EOF → output index
        # 如果编号后直接 EOF → 输出编号
        output_line(cueIndex)
        next
    }
}

# Default case: ordinary line, not part of a cue
# 默认情况：普通行，不属于字幕块
{
    output_line($0)
}

END {
    if (!validSRT) {
        print "Error: input is not a valid SRT file" > "/dev/stderr"
        exit 1
    }
}
