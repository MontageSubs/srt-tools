#!/usr/bin/awk -f
# ============================================================================
# Name: srt_zh_en_swap.awk
# Version: 1.1
# Organization: MontageSubs (蒙太奇字幕组)
# Contributors: Meow P (小p), novaeye
# License: MIT License
# Source: https://github.com/MontageSubs/
#
# Description / 描述:
#   This AWK script processes SubRip (.srt) subtitle files and swaps
#   Chinese and English subtitle lines within each cue block.
#   本 AWK 脚本用于处理 SubRip (.srt) 字幕文件，将每个字幕块中的中文行和英文行交换。
#
# Features:
#   - Detects valid SRT cues (cue number + timecode line).
#   - If a cue contains both a Chinese line and an English line,
#     their order will be swapped.
#   - If a cue contains only one line (Chinese or English),
#     it will be kept unchanged.
#   - If a cue contains multiple lines beyond the standard bilingual
#     structure, the cue will be preserved as-is (no swapping).
#   - Subtitle alignment tags (e.g., "{\an8}") are preserved at the
#     beginning of the first line after swapping.
#   - Handles UTF-8 BOM automatically.
#   - Accepts flexible spacing in timecode lines.
#   - Preserves HTML-style tags (<i>, </i>) and music symbols.
#   - If no valid SRT structure is detected, the script exits with
#     an error message and produces no output.
#
# 功能:
#   - 能识别有效的 SRT 字幕块（字幕编号 + 时间轴行）。
#   - 如果一个字幕块包含中英文两行，会交换它们的顺序。
#   - 如果一个字幕块只有一行（仅中文或仅英文），保持不变。
#   - 如果字幕块包含多行，超出常见的双语结构，将保持原样不做交换。
#   - 字幕对齐标签（例如 "{\an8}"）在交换后仍会保留在第一行开头。
#   - 自动处理 UTF-8 BOM。
#   - 时间轴行中的空格格式可灵活识别。
#   - 保留 HTML 风格的样式标签（<i>, </i>）和音乐符号。
#   - 如果未检测到有效的 SRT 结构，脚本会报错并退出，不会生成输出。
#
# Usage / 用法:
#   awk -f srt_zh_en_swap.awk input.srt > output.srt
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
#     My mistake.
#     看来我错了
# ============================================================================

##############################
#   Utility Functions
#   工具函数
##############################

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

# Detect any non-ASCII character (likely CJK).
# 检测是否包含非 ASCII 字符（可能是中日韩文字）。
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

# Detect whether line consists only of style tags, punctuation, or music notes.
# 检测一行是否仅包含样式标签、标点或音乐符号。
function is_style_or_music_only(line,    tmp) {
    tmp = line
    gsub(/< *\/? *[ibuIBU] *>/, "", tmp)      # remove <i>, <b>, <u> / 移除样式标签
    gsub(/\\?{[^}]*}/, "", tmp)               # remove {\anX} or similar / 移除 {\anX} 等
    gsub(/[[:punct:][:space:]]/, "", tmp)     # remove punctuation/spaces / 移除标点和空格
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

# Extract {\anX} tag from beginning of line.
# Stores tag in global variable cueTag and returns the line without tag.
# 从行首提取 {\anX} 标签。
# 将标签保存到全局变量 cueTag，并返回去掉标签的行。
function extract_an_tag(line,    m) {
    cueTag = ""
    if (match(line, /^\{\\an[0-9]+\}/)) {
        cueTag = substr(line, RSTART, RLENGTH)
        return substr(line, RSTART + RLENGTH)
    }
    return line
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

##############################
#   Main Processing Logic
#   主处理逻辑
##############################

BEGIN {
    useCRLF = 0      # default line ending mode / 默认换行符模式
    validSRT = 0     # becomes 1 if at least one valid cue is detected / 检测到至少一个有效字幕块时为 1
    firstLine = 1    # true until first line processed (for BOM check) / 第一行时为真，用于 BOM 检测
}

{
    # Detect CRLF style: if line ends with \r, mark CRLF mode
    # 检测 CRLF 风格：如果行以 \r 结尾，则标记为 CRLF 模式
    if ($0 ~ /\r$/) useCRLF = 1
    sub(/\r$/, "", $0)   # strip trailing \r / 去掉行尾 \r

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

            # Output index and timecode
            # 输出编号和时间码
            output_line(cueIndex)
            output_line(cueTimecode)

            # Read cue body lines until empty line or EOF
            # 读取字幕内容，直到遇到空行或文件结束
            cueLineCount = 0
            delete cueLines
            while ((getline cueContent) > 0) {
                if (cueContent ~ /\r$/) useCRLF = 1
                sub(/\r$/, "", cueContent)
                if (cueContent == "") break
                cueLines[++cueLineCount] = cueContent
            }

            # Case A: empty cue (no text lines)
            # 情况 A: 空字幕块（没有台词行）
            if (cueLineCount == 0) {
                output_line("")
                next
            }

            # Extract {\anX} tag if present on first line
            # 如果第一行有 {\anX} 标签，提取
            cueTag = ""
            firstText = extract_an_tag(cueLines[1])

            # Case B: more than 2 text lines → leave as is
            # 情况 B: 多于 2 行 → 保持原样
            if (cueLineCount > 2) {
                output_line(cueTag firstText)
                for (i = 2; i <= cueLineCount; i++) output_line(cueLines[i])
                output_line("")
                next
            }

            # Case C: single text line → leave as is
            # 情况 C: 仅 1 行 → 保持原样
            if (cueLineCount == 1) {
                output_line(cueTag firstText)
                output_line("")
                next
            }

            # Case D: exactly 2 lines
            # 情况 D: 正好 2 行
            secondText = cueLines[2]

            # If second line incorrectly has {\anX} → leave as is
            # 如果第二行错误地包含 {\anX} → 保持原样
            if (secondText ~ /^\{\\an[0-9]+\}/) {
                output_line(cueTag firstText)
                output_line(secondText)
                output_line("")
                next
            }

            # Swap if first line is Chinese and second is English
            # 如果第一行是中文，第二行是英文 → 交换
            if (is_chinese_line(firstText) && is_ascii(secondText)) {
                output_line(cueTag secondText)
                output_line(firstText)
            } else {
                output_line(cueTag firstText)
                output_line(secondText)
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
