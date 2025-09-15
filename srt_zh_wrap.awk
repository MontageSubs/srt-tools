#!/usr/bin/awk -f
# ============================================================================
# Name: srt_zh_wrap.awk
# Version: 1.2
# Organization: MontageSubs (蒙太奇字幕组)
# Contributors: Meow P (小p)
# License: MIT License
# Source: https://github.com/MontageSubs/
#
# Description / 描述:
#   This AWK script performs intelligent line wrapping for Chinese subtitles
#   in SubRip (.srt) files.
#   本 AWK 脚本用于处理 SubRip (.srt) 文件，对中文字幕进行智能换行。
#
# Features:
#   - Detects valid SRT cues (cue number + timecode line).
#   - Splits dialogue lines with multiple speakers marked by "-" into separate lines.
#   - Attempts to split long single-line Chinese text at natural breakpoints
#     (spaces, punctuation) while avoiding bad splits (e.g., punctuation-only lines).
#   - Respects alignment tags such as "{\an2}"; tags stay on the first line and
#     are not counted towards the splitting threshold.
#   - Preserves original line ending style (LF or CRLF) and handles UTF-8 BOM.
#   - If input is not a valid SRT file, the script exits with an error.
#
# 功能:
#   - 能识别有效的 SRT 字幕块（字幕编号 + 时间轴行）。
#   - 将多说话人对话（使用 "-" 标记）拆分为独立行。
#   - 对超长中文单行文本，按自然断点（空格、标点）智能换行，
#     避免生成仅含标点或错误断句的行。
#   - 保留对齐标签（如 "{\an2}"），并确保其只在首行出现，不计入换行阈值。
#   - 保持原始换行符风格（LF 或 CRLF），并能自动处理 UTF-8 BOM。
#   - 如果输入不是有效的 SRT 文件，脚本会报错并退出。
#
# Usage / 用法:
#   awk -v SPLIT_THRESHOLD=5 -f srt_zh_wrap.awk chs_only_example.srt > new1.srt
#
# Parameter / 参数:
#   SPLIT_THRESHOLD : threshold for line splitting; if a line exceeds this length,
#                     attempt to split. Default = 20 (can override via -v).
#                     （换行阈值，默认为 20，可用 -v 覆盖，例如 -v SPLIT_THRESHOLD=15）
# ============================================================================

#############################
#   Configuration / 配置
#############################
BEGIN {
    # If SPLIT_THRESHOLD not set via -v, default to 20
    # 如果没有通过 -v 设置 SPLIT_THRESHOLD，则默认为 20
    if (SPLIT_THRESHOLD == "") SPLIT_THRESHOLD = 20

    useCRLF = 0            # 0 = LF, 1 = CRLF / 0 表示 LF，1 表示 CRLF
    validSRT = 0           # becomes 1 if valid cue detected / 检测到有效字幕块时为 1
    firstLine = 1          # flag for first line (to remove BOM) / 第一行标记（用于 BOM 去除）
}

#############################
#   Utility Functions / 工具函数
#############################

# Detect whether line is a valid SRT timecode.
# Format is relaxed: allows flexible spacing.
# 检测是否为合法的 SRT 时间码行（格式较宽松，允许多余空格）。
function is_timecode(line) {
    return (line ~ /^[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*-->[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*$/)
}

# Print line preserving CRLF if input used CRLF.
# 按输入文件的换行风格输出（LF 或 CRLF）。
function out(text) {
    if (useCRLF) printf "%s\r\n", text
    else print text
}

# Trim leading and trailing whitespace.
# 去除首尾空格或制表符。
function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

# Return character length of string (used for split threshold).
# 返回字符串长度（按字符计，用于阈值判断）。
function clen(s) { return length(s) }

# Detect if string contains CJK characters.
# 检查字符串是否包含中日韩文字。
function has_cjk(s) { return (s ~ /[一-龥]/) }

# Detect if string contains alphanumeric characters (ASCII letters/numbers).
# 检查字符串是否包含字母或数字。
function has_alnum(s) { return (s ~ /[[:alnum:]]/) }

# Return 1 if string (after trimming) is only punctuation or symbols.
# 如果字符串仅由标点或符号组成，返回 1。
function is_punct_only(s,    t) {
    t = trim(s)
    if (t == "") return 1
    if (has_cjk(t)) return 0
    if (has_alnum(t)) return 0
    return 1
}

# Check whether line starts with an allowed prefix:
#   - "-" (dialogue marker)
#   - music symbols (♪♫♩♬)
#   - <i> tag
# 判断行首是否为允许的前缀符号。
function starts_with_allowed_prefix(s,    fc,pre3) {
    if (s == "") return 0
    fc = substr(s,1,1)
    if (fc == "-") return 1
    if (index("♪♫♩♬", fc) > 0) return 1
    pre3 = substr(s,1,3)
    if (pre3 == "<i>") return 1
    return 0
}

# Return 1 if character is considered punctuation that cannot start a line.
# 判断某字符是否属于“不可行首”的标点。
function is_punct_char(c) {
    return (index(".,?!;:'\"、，。！？；：…·)]}—–”’》〉", c) > 0)
    # return (index(".,?!;:'\"、，。！？；：…·()[]{}—–“”‘’《》〈〉", c) > 0)
}

#############################
#   Hyphen Detection / "-" 标记检测
#############################

# Find valid positions of '-' used as dialogue markers.
# Rules:
#   - If '-' is at position 1, always valid.
#   - If '-' appears inside, it’s valid only if preceded by whitespace.
# 将合法 "-" 的位置存入全局数组 hypos[] 并返回数量。
function find_hyphens_positions(s,    i,ch,count) {
    delete hypos
    count = 0
    for (i = 1; i <= length(s); i++) {
        ch = substr(s,i,1)
        if (ch == "-") {
            if (i == 1 || substr(s,i-1,1) ~ /[[:space:]]/) {
                count++
                hypos[count] = i
            }
        }
    }
    return count
}

#############################
#   Long-line Splitting / 长句拆分
#############################

# Try splitting a long line into two parts using priority rules:
#   1) space
#   2) ？ or ！
#   3) 、 
#   4) ， or 。
#   5) fallback: midpoint (improved: prefer uneven split for even length)
#
# Conditions:
#   - Avoid producing one very short side (<=2 chars).
#   - Right side must not be punctuation-only.
#   - If right side starts with forbidden punctuation, move it to left side.
#
# On success:
#   - Sets globals SL_L and SL_R.
#   - Returns 1.
# On failure: returns 0.
#
# 尝试按优先级拆分长行，遵循约束条件。
# 成功时在 SL_L/SL_R 返回结果并返回 1，失败返回 0。
function split_line(line,    tmp,len,mid,i,ch,ll,rr,diff,bestPos,bestDiff,left,right,prefix,pch,pos) {
    tmp = line
    sub(/^\{\\an[0-9]+\}/, "", tmp)   # ignore {\anX} at start for length calc / 忽略开头的对齐标签
    len = clen(tmp)
    if (len <= SPLIT_THRESHOLD) return 0

    mid = int(len/2)
    bestPos = 0
    bestDiff = len

    # Priority 1: split at space / 优先级 1：空格
    for (i = 1; i <= len; i++) {
        ch = substr(tmp,i,1)
        if (ch == " ") {
            ll = i; rr = len - i
            if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
            diff = ll - rr; if (diff < 0) diff = -diff
            if (diff < bestDiff) { bestDiff = diff; bestPos = i }
        }
    }

    # Priority 2: split at ？ or ！ / 优先级 2：问号或感叹号
    if (bestPos == 0) {
        for (i = 1; i <= len; i++) {
            ch = substr(tmp,i,1)
            if (ch == "？" || ch == "！") {
                ll = i; rr = len - i
                if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
                diff = ll - rr; if (diff < 0) diff = -diff
                if (diff < bestDiff) { bestDiff = diff; bestPos = i }
            }
        }
    }

    # Priority 3: split at 、 / 优先级 3：顿号
    if (bestPos == 0) {
        for (i = 1; i <= len; i++) {
            ch = substr(tmp,i,1)
            if (ch == "、") {
                ll = i; rr = len - i
                if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
                diff = ll - rr; if (diff < 0) diff = -diff
                if (diff < bestDiff) { bestDiff = diff; bestPos = i }
            }
        }
    }

    # Priority 4: split at ， or 。 / 优先级 4：逗号或句号
    if (bestPos == 0) {
        for (i = 1; i <= len; i++) {
            ch = substr(tmp,i,1)
            if (ch == "，" || ch == "。") {
                ll = i; rr = len - i
                if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
                diff = ll - rr; if (diff < 0) diff = -diff
                if (diff < bestDiff) { bestDiff = diff; bestPos = i }
            }
        }
    }

    # Fallback: midpoint / 兜底策略：中点切分（改进：偶数长度时优先不对称拆分）
    if (bestPos == 0) {
        if (len % 2 == 0) {
            pos = mid - 1
            if (pos < 1) pos = mid
        } else {
            pos = mid
        }
        ll = pos; rr = len - pos
        if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) return 0
        bestPos = pos
    }

    SL_L = trim(substr(line,1,bestPos))
    SL_R = trim(substr(line,bestPos+1))

    # Reject if right side is punctuation-only / 右半边仅为标点 → 取消
    if (is_punct_only(SL_R)) return 0

    # If right side starts with allowed prefix (e.g., "-", music, <i>) → OK
    # 右半边以允许的前缀开头 → 合法
    if (starts_with_allowed_prefix(SL_R)) return 1

    # If right side starts with forbidden punctuation, move it back to left
    # 右半边以禁止标点开头 → 移动到左边
    pch = substr(SL_R,1,1)
    if (is_punct_char(pch)) {
        prefix = ""
        while (length(SL_R) > 0) {
            pch = substr(SL_R,1,1)
            if (!is_punct_char(pch)) break
            prefix = prefix pch
            SL_R = substr(SL_R,2)
        }
        SL_R = trim(SL_R)
        if (SL_R == "") return 0
        SL_L = trim(SL_L prefix)
        SL_R = trim(SL_R)
    }

    return 1
}

#############################
#   Main Processing / 主流程
#############################

{
    # Detect CRLF endings and strip \r
    # 检测 CRLF，并去掉行尾 \r
    if ($0 ~ /\r$/) useCRLF = 1
    sub(/\r$/, "", $0)

    # Remove BOM if first line
    # 如果是第一行，去掉 BOM
    if (firstLine) {
        sub(/^\xEF\xBB\xBF/, "", $0)
        firstLine = 0
    }
}

# Case: line is cue index (number)
# 情况：行是字幕编号
$0 ~ /^[0-9]+$/ {
    cueIndex = $0
    if ((getline cueTimecode) > 0) {
        if (cueTimecode ~ /\r$/) useCRLF = 1
        sub(/\r$/, "", cueTimecode)
        if (is_timecode(cueTimecode)) {
            # Confirmed valid cue
            # 确认是有效字幕块
            validSRT = 1
            out(cueIndex)
            out(cueTimecode)

            # Read cue body until blank line or EOF
            # 读取字幕正文，直到空行或 EOF
            n = 0; delete L
            while ((getline aline) > 0) {
                if (aline ~ /\r$/) useCRLF = 1
                sub(/\r$/, "", aline)
                if (aline == "") break
                L[++n] = aline
            }

            # Case A: empty body
            # 情况 A: 空字幕块
            if (n == 0) { out(""); next }

            # Case B: multiple lines → output as-is
            # 情况 B: 多行 → 保持原样
            if (n > 1) { for (i = 1; i <= n; i++) out(L[i]); out(""); next }

            # Case C: single line → attempt splitting
            # 情况 C: 单行 → 尝试拆分
            raw = trim(L[1])

            # Extract {\anX} tag if present
            # 如果存在对齐标签，提取
            alignTag = ""
            if (match(raw, /^\{\\an[0-9]+\}/)) {
                alignTag = substr(raw, RSTART, RLENGTH)
                raw = substr(raw, RSTART + RLENGTH)
                raw = trim(raw)
            }

            # Step 1: try hyphen-based dialogue splitting
            # 第一步：尝试按 "-" 对话拆分
            hyc = find_hyphens_positions(raw)
            if (hyc >= 2) {
                splitPos = hypos[2]          # use second valid "-" / 使用第二个合法 "-"
                a_raw = substr(raw, 1, splitPos-1)
                b_orig = substr(raw, splitPos)

                # Check if "-" followed by space
                # 判断 "-" 后是否有空格
                if (substr(raw, splitPos+1, 1) ~ /[[:space:]]/) sep = "- "
                else sep = "-"

                # Extract rest after hyphen
                # 提取 "-" 后的内容
                rest = b_orig
                sub(/^-+/, "", rest)
                sub(/^[ \t]+/, "", rest)
                rest = trim(rest)

                # If rest empty or punctuation-only → cancel hyphen split
                # 如果右半边为空或仅为标点 → 取消拆分
                if (rest == "" || is_punct_only(rest)) {
                    # fall back to long-line splitting / 退回到长句拆分
                } else {
                    bnorm = sep rest
                    a = trim(a_raw)
                    if (alignTag != "") a = alignTag a
                    out(a)
                    out(bnorm)
                    out("")
                    next
                }
            }

            # Step 2: try long-line splitting
            # 第二步：尝试长句拆分
            if (split_line(raw)) {
                left = SL_L; right = SL_R
                if (alignTag != "") left = alignTag left
                out(left); out(right); out(""); next
            }

            # Step 3: no split → output original
            # 第三步：无法拆分 → 原样输出
            if (alignTag != "") out(alignTag raw)
            else out(raw)
            out("")
            next
        } else {
            # Not a timecode → output as-is
            # 非时间码 → 原样输出
            out(cueIndex); out(cueTimecode); next
        }
    } else {
        # Index followed by EOF → output index
        # 编号后直接 EOF → 输出编号
        out(cueIndex); next
    }
}

# Default case: passthrough
# 默认情况：按原样输出
{ out($0) }

END {
    if (!validSRT) {
        print "Error: input is not a valid SRT file" > "/dev/stderr"
        exit 1
    }
}
