#!/usr/bin/awk -f
# ============================================================================
# Name: srt_zh_wrap.awk
# Version: 1.5.1
# Organization: MontageSubs (蒙太奇字幕组)
# Contributors: Meow P (小p), novaeye
# License: MIT License
# Source: https://github.com/MontageSubs/
#
# Description / 描述:
#   This AWK script performs intelligent line wrapping for Chinese subtitles
#   in SubRip (.srt) files. It reads standard SRT cues (index + timecode +
#   text) and only attempts to reflow single-line cue text that is judged to
#   be too long according to a configurable threshold. The script is
#   punctuation- and bracket-aware to avoid producing awkward breaks.
#
#   本脚本用于对 SubRip (.srt) 字幕文件中的单行中文字幕进行智能换行。
#   它识别 SRT 的字幕块（编号 + 时间码 + 文本），仅对单行且超过阈值的
#   文本尝试拆分。拆分时会考虑标点、引括号等上下文，尽量避免产生不
#   合理或孤立的标点行。
#
# Decision logic (how the script decides to split)
#   1) Read SRT cue blocks: detect cue index line, then read timecode and body.
#   2) Only operate on cues with a single text line. Multi-line cues are
#      preserved unchanged (to avoid reflowing already wrapped cues).
#   3) If a single-line text is short by "meaningful character" count
#      (non-punctuation, configurable by SPLIT_THRESHOLD), it is not split.
#   4) Prefer dialogue splits marked by a leading '-' (dialogue marker).
#   5) Otherwise, perform bracket-aware intelligent split: prefer spaces,
#      then high-priority punctuation, then other punctuation; if none found,
#      fall back to a midpoint (by meaningful chars).
#   6) Avoid splits that produce very short or punctuation-only lines,
#      or that split inside small bracketed phrases.
#   7) Preserve alignment tags (e.g., {\an2}) by keeping them attached to
#      the first (left) output line and not counting them toward length.
#
# 判断逻辑（拆分决策流程）
#   1) 读取字幕块：先识别编号行，再读取时间码与正文。
#   2) 仅对正文为单行的字幕进行尝试，已有多行的字幕保持原样。
#   3) 非标点字符数（中文与字母数字）小于阈值则不拆分。
#   4) 如果行中包含合规的 '-' 对话标记，优先按 '-' 拆分（保持说话人清晰）。
#   5) 拆分优先级：空格 → 高优先级标点（如问/感叹）→ 其他标点 → 以非标点字符数的中点为兜底。
#   6) 避免产生 <=2 的超短侧、仅含标点的行，或在小范围括号内拆分导致破坏语义。
#   7) 保留对齐标签（{\anX}）并把它们放在左侧行，不计入拆分长度判断。
#
# Features
#   - Detects valid SRT cues (cue number + timecode line).
#   - Splits dialogue lines with multiple speakers marked by "-" into
#     separate lines, preserving the speaker marker.
#   - Attempts to split long single-line Chinese text at natural
#     breakpoints (spaces, punctuation) while avoiding bad splits
#     (e.g., punctuation-only lines, orphaned openers).
#   - Respects alignment tags such as "{\an2}"; tags stay on the first
#     line and are not counted towards the splitting threshold.
#   - Bracket-aware: avoids splitting inside small parenthetical/quoted
#     ranges unless the inner content is long enough.
#   - Preserves original line ending style (LF or CRLF) and handles UTF-8
#     BOM.
#   - If input is not a valid SRT file, the script exits with an error.
#
# 功能
#   - 能识别有效的 SRT 字幕块（编号 + 时间码）。
#   - 将以 "-" 标记的多说话人对话拆为多行，保留对话符号。
#   - 在自然断点（空格、标点）处智能换行，避免产生错误断句或孤立标点。
#   - 保持对齐标签在左侧行，并且不把标签长度计入拆分阈值计算。
#   - 支持括号/引号感知：若括号内内容较短则避免在其中拆分。
#   - 保持原始换行风格（LF/CRLF），自动处理 UTF-8 BOM。
#   - 如果输入不是有效的 SRT 文件，脚本会输出错误并退出。
#
# Usage / 用法:
#   awk -v SPLIT_THRESHOLD=15 -v BRACKET_FACTOR=2 -f srt_zh_wrap.awk input.srt > output.srt
#
# Parameters / 参数:
#   SPLIT_THRESHOLD : threshold for line splitting (non-punctuation chars);
#                     default = 20 (can override via -v).
#                     换行阈值（按非标点字符计数），默认为 20，可用 -v 覆盖。
#   BRACKET_FACTOR  : multiplier applied to bracket-inner-length threshold;
#                     default = 2 (can override via -v).
#                     括号内长度容忍倍数，默认为 2，可用 -v 覆盖。
# ============================================================================

###############################  Configuration / 配置  ##############################
BEGIN {
    # Initialize runtime options and defaults.
    # 初始化运行时选项与默认值：可通过 awk -v 覆盖 SPLIT_THRESHOLD 和 BRACKET_FACTOR。
    if (SPLIT_THRESHOLD == "") SPLIT_THRESHOLD = 20
    if (BRACKET_FACTOR == "") BRACKET_FACTOR = 2
    useCRLF = 0            # 0 = LF, 1 = CRLF / 0 表示 LF，1 表示 CRLF
    validSRT = 0           # becomes 1 if valid cue detected / 检测到有效字幕块时置 1
    firstLine = 1          # flag for first line (used to strip BOM) / 第一行标记用于去 BOM
}

###############################  Utility Functions / 工具函数  ###############################
# is_timecode(line)
#   Return 1 if the given line matches a relaxed SRT timecode pattern
#   ("hh:mm:ss,ms --> hh:mm:ss,ms"). Accepts flexible spacing around -->.
#   如果该行匹配 SRT 时间码模式（宽松匹配），则返回 1。
function is_timecode(line) {
    return (line ~ /^[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*-->[ \t]*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}[ \t]*$/)
}

# out(t)
#   Print a line using the original file's line-ending style (LF or CRLF).
#   根据输入文件的换行风格（useCRLF），打印一行（保留 CRLF 或 LF）。
function out(t) {
    if (useCRLF) printf "%s\r\n", t
    else print t
}

# trim(s)
#   Remove leading and trailing spaces and tabs.
#   去除字符串首尾的空格和制表符。
function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

# clen_np(s)
#   Count "meaningful" characters in s: CJK unified ideographs or
#   ASCII letters/digits. This count ignores punctuation and is used to
#   decide whether a line is long enough to consider splitting.
#   统计字符串中“有意义字符”的数量：中文（汉字）或 ASCII 的字母/数字，
#   忽略标点。用于判断是否超过拆分阈值。
function clen_np(s,    i,ch,c) {
    c = 0
    for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch ~ /[一-龥]/ || ch ~ /[[:alnum:]]/) c++
    }
    return c
}

# has_cjk(s)
#   Return 1 if s contains any CJK character.
#   如果字符串包含中文等 CJK 字符，返回 1。
function has_cjk(s) { return (s ~ /[一-龥]/) }

# has_alnum(s)
#   Return 1 if s contains ASCII alphanumeric characters.
#   如果包含字母或数字，返回 1。
function has_alnum(s) { return (s ~ /[[:alnum:]]/) }

# is_punct_only(s)
#   Trim s and return 1 if it is empty or contains only punctuation/symbols
#   (no CJK or alnum). Used to avoid creating punctuation-only lines.
#   去除首尾空白后，如果字符串为空或仅由标点/符号组成则返回 1。
function is_punct_only(s,    t) {
    t = trim(s)
    if (t == "") return 1
    if (has_cjk(t)) return 0
    if (has_alnum(t)) return 0
    return 1
}

# starts_with_allowed_prefix(s)
#   Some tokens are legal at the beginning of a subtitle line: "-" for
#   dialogue, common music symbols, or an <i> italic tag. If the right-hand
#   part begins with these, we allow the split.
#   某些前缀在行首是合法的（例如对话的 "-"、乐符、<i> 标签）。若右半段以这些
#   前缀开始，则认为拆分合法。
function starts_with_allowed_prefix(s,    fc,pre3) {
    if (s == "") return 0
    fc = substr(s,1,1)
    if (fc == "-") return 1
    if (index("♪♫♩♬", fc) > 0) return 1
    pre3 = substr(s,1,3)
    if (pre3 == "<i>") return 1
    return 0
}

# is_punct_char(c)
#   Return 1 if c is a punctuation character that generally should NOT
#   appear as the first printable character of a split-right line.
#   判断字符是否属于“不可作为行首”的标点，当右侧以这些字符开头时需要处理。
function is_punct_char(c) {
    return (index(".,?!;:'\"、，。！？；：…·)]}）】」』》〉”’", c) > 0)
}

# is_open_char(c)
#   Return 1 if c is an opening bracket/quote that should not be left
#   dangling at the end of the left-side after a split (e.g. "(" or "《").
#   判断字符是否为开括号/左引号，左边不应以此类字符结尾以免产生孤立的开符号。
function is_open_char(c) {
    return (index("([{（【《「『〈“‘, c) > 0)
}

###############################  Hyphen Detection / "-" 标记检测  ###############################
# find_hyphens_positions(s)
#   Collect positions of hyphens that look like dialogue markers:
#   - a hyphen at position 1 is always considered a dialogue marker;
#   - an interior hyphen is considered a marker only if preceded by whitespace.
#   The function stores valid positions in global array hypos[] and
#   returns the count.
#   收集可能用作对话标记的 "-" 位置：若出现在首位视为对话标记，若在中间则须
#   前一位为空白才视为合法。结果位置写入全局数组 hypos[] 并返回数量。
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

###############################  Bracket/Quote Ranges Detection / 括号/引号配对检测  ###############################
# find_bracket_ranges(s)
#   Scan the string and attempt to pair common opening and closing
#   bracket/quote characters. For each matched pair we record the left and
#   right indices and the count of meaningful (non-punctuation) characters
#   inside the pair. Results are returned in BR_L[], BR_R[], BR_NP[] and
#   BR_COUNT.
#   扫描字符串并配对常见的成对符号（括号、书名号、引号等）。对每一对记录左右
#   索引以及内部的有意义字符数（用于判断括号是否足够“大”以允许在内拆分）。
function find_bracket_ranges(s,    i,ch,stackTop,stackChar,stackPos,rCount,left,openMap,closeMap,inner) {
    delete BR_L; delete BR_R; delete BR_NP
    rCount = 0
    stackTop = 0
    # Opening symbols map
    openMap["("]=1; openMap["["]=1; openMap["{"]=1
    openMap["（"]=1; openMap["【"]=1; openMap["《"]=1
    openMap["「"]=1; openMap["『"]=1; openMap["〈"]=1
    openMap["“"]=1; openMap["‘"]=1
    # Closing -> opening mapping
    closeMap[")"]="("; closeMap["]"]="["; closeMap["}"]="{"
    closeMap["）"]="（"; closeMap["】"]="【"; closeMap["》"]="《"
    closeMap["」"]="「"; closeMap["』"]="『"; closeMap["〉"]="〈"
    closeMap["”"]="“"; closeMap["’"]="‘"

    for (i = 1; i <= length(s); i++) {
        ch = substr(s,i,1)
        if (ch in openMap) {
            stackTop++; stackChar[stackTop] = ch; stackPos[stackTop] = i
        } else if (ch in closeMap) {
            if (stackTop > 0 && stackChar[stackTop] == closeMap[ch]) {
                left = stackPos[stackTop]; stackTop--
                rCount++
                BR_L[rCount] = left
                BR_R[rCount] = i
                inner = substr(s, left+1, i-left-1)
                BR_NP[rCount] = clen_np(inner)
            }
        } else if (ch == "\"" || ch == "'") {
            # treat quotes as pairable same-char symbols
            # 把引号当作同字符可配对的符号
            if (stackTop > 0 && stackChar[stackTop] == ch) {
                left = stackPos[stackTop]; stackTop--
                rCount++
                BR_L[rCount] = left
                BR_R[rCount] = i
                inner = substr(s, left+1, i-left-1)
                BR_NP[rCount] = clen_np(inner)
            } else {
                stackTop++; stackChar[stackTop] = ch; stackPos[stackTop] = i
            }
        }
    }
    BR_COUNT = rCount
    return rCount
}

# in_bracket(pos)
#   Return the index (1..BR_COUNT) of the smallest bracket range that
#   strictly contains position pos (pos must be strictly inside, not on the
#   delimiters). If none, return 0.
#   返回包含 pos 的最小配对范围的索引（严格包含，即不包括边界），找不到返回 0。
function in_bracket(pos,    j,best_k,best_len,leni) {
    best_k = 0; best_len = 1e9
    for (j = 1; j <= BR_COUNT; j++) {
        if (pos > BR_L[j] && pos < BR_R[j]) {
            leni = BR_R[j] - BR_L[j]
            if (leni < best_len) { best_len = leni; best_k = j }
        }
    }
    return best_k
}

# find_nearest_outside(idx, orig_len)
#   Given an index that falls inside some bracket, search outward (left/right)
#   for the nearest index that is not inside any bracket. Returns that
#   index or 0 if none found.
#   如果一个索引落在括号内，向两边扩展搜索第一个不在任何配对内的位置，找不到返回 0。
function find_nearest_outside(idx, orig_len,    d,left,right) {
    for (d = 0; d <= orig_len; d++) {
        left = idx - d
        if (left >= 1) {
            if (in_bracket(left) == 0) return left
        }
        right = idx + d
        if (right <= orig_len) {
            if (in_bracket(right) == 0) return right
        }
    }
    return 0
}

# find_index_for_left_np(tmp, target)
#   Map a target "meaningful character" count back to a string index: find
#   the smallest position in tmp whose cumulative non-punctuation character
#   count >= target. Returns that string index, or 0 if not reachable.
#   将基于非标点字符计数的目标数映射回字符串的位置索引（第一个使得累计计数
#   >= target 的字符位置），找不到返回 0。
function find_index_for_left_np(tmp, target,    i,ch,cum) {
    cum = 0
    for (i = 1; i <= length(tmp); i++) {
        ch = substr(tmp,i,1)
        if (ch ~ /[一-龥]/ || ch ~ /[[:alnum:]]/) cum++
        if (cum >= target) return i
    }
    return 0
}

###############################  Long-line Splitting / 长句拆分（主逻辑） ###############################
# split_line(line)
#   Attempt to split a long single-line subtitle into two natural parts.
#   Uses the configured SPLIT_THRESHOLD and BRACKET_FACTOR to make
#   bracket-aware decisions. On success sets global SL_L and SL_R and
#   returns 1; on failure returns 0.
#
#   Strategy highlights:
#     - Count non-punctuation characters (np_len). If <= SPLIT_THRESHOLD,
#       don't split.
#     - Prefer splitting at spaces, then high-priority punctuation,
#       then before closing-like characters. If none, choose a midpoint by
#       non-punctuation count.
#     - Avoid very short sides, avoid splits inside small bracketed ranges
#       (use BRACKET_FACTOR to define "small").
#     - After picking a candidate position, perform sanity fixes: trim,
#       avoid punctuation-only right side, move forbidden leading punctuation
#       back to the left side, ensure left doesn't end with an opening char.
#
#   说明:
#     这个函数的目标是把单行且 "太长" 的字幕智能拆成两行，拆分位置尽量
#     符合语义断点并且不造成尴尬的断句或孤立标点。核心步骤为：
#       1) 统计该行中“有意义字符”（中文汉字与 ASCII 字母/数字）的累积数 np_len；
#       2) 若 np_len 不超过阈值（SPLIT_THRESHOLD），直接不拆分；
#       3) 否则按优先级搜索合适的断点（优先空格 → 高优先级标点 → 在闭合符号前），
#          并使用括号感知避免在较短的括号/引号内部拆分；
#       4) 如果没找到合适位置，则以有意义字符数的中点为兜底（并尽量避免对称平均
#          导致极短的一侧）；
#       5) 最后对候选拆分做若干“保洁处理”（去首尾空白、避免右侧仅为标点、把右侧
#          的前导禁止标点移回左侧、确保左侧不以开括号收尾等）。
#
#   变量说明（常见局部名词）:
#     tmp        - 去掉 {\anX} 对齐标签后的原始文本（用于计算长度）
#     orig_len   - tmp 的字符总长度（按字符，不是有意义字符数）
#     cum_np[i]  - 到字符串索引 i 为止的有意义字符累计数（用于把“第 N 个有意义字符”映射回索引）
#     np_len     - 总的有意义字符数（用于与 SPLIT_THRESHOLD 对比）
#     bal_abs    - 绝对容差（SPLIT_THRESHOLD 的半值），用于避免过度不平衡的拆分
#     bal_rel    - 相对容差（约占总有意义字符的 45%），用于避免过度不平衡的拆分
#     BR_* 系列 - 由 find_bracket_ranges 填充，记录各对括号/引号的左右索引与内部有意义字符数
#
#   决策要点（简短）:
#     - 不在小括号内部拆分（bracket 内部的有意义字符数 <= SPLIT_THRESHOLD * BRACKET_FACTOR 时视为“小”）
#     - 避免产生一边 <=2 个有意义字符且另一边比它多至少 5 个（太不平衡）
#     - 若右侧以允许的前缀（比如 "-"、乐符或 <i>）开头，则允许拆分
#
#   成功时：设置全局 SL_L（左侧文本）和 SL_R（右侧文本），并返回 1
#   失败时：不修改 SL_L/SL_R，返回 0
#   该函数会在成功时填充全局变量 SL_L（左侧）和 SL_R（右侧），并返回 1；失败返回 0。
function split_line(line,    tmp,orig_len,i,ch,np_len,cum_np,mid,bestPos,bestDiff,ll,rr,diff,brk,brnp,left_trim,lastc,pos_index,target,pos,absdiff,bal_abs,bal_rel) {
    tmp = line
    sub(/^\{\\an[0-9]+\}/, "", tmp)
    # ignore {\anX} at start for length calc — 对齐标签不计入长度（不参与阈值判断）
    orig_len = length(tmp)

    # build cumulative non-punct counts per index
    np_len = 0
    for (i = 1; i <= orig_len; i++) {
        ch = substr(tmp,i,1)
        if (ch ~ /[一-龥]/ || ch ~ /[[:alnum:]]/) np_len++
        cum_np[i] = np_len
    }

    # if not enough meaningful chars → no split
    # 如果有意义字符总数未超过阈值，则无需拆分
    if (np_len <= SPLIT_THRESHOLD) return 0

    # balance thresholds:
    # bal_abs: small absolute tolerance (half threshold)
    # bal_rel: relative tolerance (roughly 45% of total non-punct chars)
    # 平衡容差：
    #   bal_abs（绝对容差）防止因为阈值导致极小的偏差被判为有效拆分
    #   bal_rel（相对容差）防止在总体很长时出现过于不平衡的拆分
    bal_abs = (SPLIT_THRESHOLD < 2 ? 1 : int(SPLIT_THRESHOLD / 2))
    bal_rel = int(np_len * 0.45)

    # detect bracket ranges to consider bracket-aware splits
    # 先识别所有成对括号/引号范围，以便后续判断候选拆分是否落在小范围内
    find_bracket_ranges(tmp)

    mid = int(np_len / 2)
    bestPos = 0
    bestDiff = np_len

    # Priority A: split at spaces (prefer these)
    # 优先尝试在空格处拆分：空格通常是最自然的分割位置（特别是在中英文混排或有英文单词时）
    for (i = 1; i <= orig_len; i++) {
        ch = substr(tmp,i,1)
        if (ch == " ") {
            ll = cum_np[i]
            rr = np_len - ll
            # Avoid extremely unbalanced splits (e.g. left too short like 0/5 or 1/6)
            # 避免生成一边太短而另一边很长的情况（例如 0/5 或 1/6）
            if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
            absdiff = (ll > rr ? ll-rr : rr-ll)
            # Skip if balance tolerance not satisfied
            # 如果不满足平衡容差要求则跳过
            if (absdiff > bal_abs && absdiff > bal_rel) continue
            # If space lies inside a bracketed segment and that segment is too short, skip it
            # 若该空格位于某一配对括号内部，且该括号内部不够长（小于阈值乘 BRACKET_FACTOR），则跳过
            brk = in_bracket(i)
            if (brk > 0) {
                brnp = BR_NP[brk]
                if (brnp <= int(SPLIT_THRESHOLD * BRACKET_FACTOR)) continue
            }
            # Ensure left side doesn't end with an opening bracket/quote
            # 检查左侧修剪后最后一个字符，不能是开括号/左引号（避免留下孤立的开符号）
            left_trim = trim(substr(tmp,1,i))
            lastc = (length(left_trim) > 0 ? substr(left_trim, length(left_trim), 1) : "")
            if (is_open_char(lastc)) continue
            diff = (ll > rr ? ll-rr : rr-ll)
            if (diff < bestDiff) { bestDiff = diff; bestPos = i }
        }
    }

    # Priority B: split at higher-priority punctuation (？ ！ 、 ， 。 …)
    # 如果空格没有找到合适位置，则尝试一些高优先级的标点作为断点
    if (bestPos == 0) {
        for (i = 1; i <= orig_len; i++) {
            ch = substr(tmp,i,1)
            if (index("？！、，。：；—）】」』》〉”’", ch) > 0) {
                ll = cum_np[i]; rr = np_len - ll
                if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) continue
                absdiff = (ll > rr ? ll-rr : rr-ll)
                if (absdiff > bal_abs && absdiff > bal_rel) continue
                brk = in_bracket(i)
                if (brk > 0) {
                    brnp = BR_NP[brk]
                    if (brnp <= int(SPLIT_THRESHOLD * BRACKET_FACTOR)) continue
                }
                left_trim = trim(substr(tmp,1,i))
                lastc = (length(left_trim) > 0 ? substr(left_trim, length(left_trim), 1) : "")
                if (is_open_char(lastc)) continue
                diff = (ll > rr ? ll-rr : rr-ll)
                if (diff < bestDiff) { bestDiff = diff; bestPos = i }
            }
        }
    }

    # Priority C: split just before closing of open chars (e.g., before a closing bracket or quote)
    # 再次尝试：在接近闭合符号之前拆分（例如在某些引号或括号的闭合处），以保持语义完整
    if (bestPos == 0) {
        for (i = 1; i <= orig_len; i++) {
            ch = substr(tmp,i,1)
            if (is_open_char(ch) || ch == "\"" || ch == "'") {
                pos = i - 1
                if (pos < 1) continue
                ll = cum_np[pos]; rr = np_len - ll
                if (ll <= 2) continue
                absdiff = (ll > rr ? ll-rr : rr-ll)
                if (absdiff > bal_abs && absdiff > bal_rel) continue
                brk = in_bracket(i)
                if (brk > 0) {
                    brnp = BR_NP[brk]
                    if (brnp <= int(SPLIT_THRESHOLD * BRACKET_FACTOR)) continue
                }
                left_trim = trim(substr(tmp,1,pos))
                lastc = (length(left_trim) > 0 ? substr(left_trim, length(left_trim), 1) : "")
                if (is_open_char(lastc)) continue
                diff = (ll > rr ? ll-rr : rr-ll)
                if (diff < bestDiff) { bestDiff = diff; bestPos = pos }
            }
        }
    }

    # Fallback: pick midpoint by non-punct count (prefer slight left bias for even)
    # 兜底策略：按有意义字符的中点选择拆分位置（偶数时略向左偏以避免完全对称），
    # 同时对中点做括号外移处理，以免在小括号内拆分。
    if (bestPos == 0) {
        if (np_len % 2 == 0) target = mid - 1
        else target = mid
        if (target < 1) target = mid
        pos_index = find_index_for_left_np(tmp, target)
        if (pos_index == 0) return 0
        brk = in_bracket(pos_index)
        if (brk > 0 && BR_NP[brk] <= int(SPLIT_THRESHOLD * BRACKET_FACTOR)) {
            pos = find_nearest_outside(pos_index, orig_len)
            if (pos == 0) return 0
            bestPos = pos
        } else {
            bestPos = pos_index
        }
        left_trim = trim(substr(tmp,1,bestPos))
        lastc = (length(left_trim) > 0 ? substr(left_trim, length(left_trim), 1) : "")
        if (is_open_char(lastc)) {
            pos = find_nearest_outside(bestPos, orig_len)
            if (pos == 0) return 0
            bestPos = pos
        }
        ll = cum_np[bestPos]; rr = np_len - ll
        if ((ll <= 2 && rr - ll >= 5) || (rr <= 2 && ll - rr >= 5)) return 0
    }

    # Construct left/right and perform final sanity checks
    SL_L = trim(substr(line, 1, bestPos))
    SL_R = trim(substr(line, bestPos+1))

    # Reject if right side is punctuation-only
    # 右侧如果只含标点/符号，则放弃拆分
    if (is_punct_only(SL_R)) return 0

    # Allow if right starts with allowed prefix
    # 如果右侧以允许的前缀开头（如 "-"、乐符或 <i>），直接接受拆分结果
    if (starts_with_allowed_prefix(SL_R)) return 1

    # If right starts with forbidden punctuation, move leading punct to left
    # 如果右侧以不允许作为行首的标点开头，则把这些前导标点移动回左侧（常见于句号/逗号紧接断行）
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

    # Ensure left doesn't end with an open char
    # 最后确认：左侧不能以开括号或左引号结尾（避免产生孤立的开符号）
    lastc = (length(SL_L) > 0 ? substr(SL_L, length(SL_L), 1) : "")
    if (is_open_char(lastc)) return 0
    return 1
}

###############################  Main Processing / 主流程  ##############################
{
    # Detect CRLF endings and strip \r
    # If the input line ends with CR (\r) we record that the original file
    # used CRLF so that we can preserve it on output. We also strip the \r
    # so subsequent processing sees a clean line.
    # 检测 CRLF：若行尾带有 \r 则记录 useCRLF=1 以便输出时保持 CRLF，同时去掉 \r 便于处理。
    if ($0 ~ /\r$/) useCRLF = 1
    sub(/\r$/, "", $0)

    # Remove BOM if first line
    # 如果是第一行，尝试去掉 UTF-8 BOM
    if (firstLine) {
        sub(/^\xEF\xBB\xBF/, "", $0)
        firstLine = 0
    }
}

# Case: line is cue index (number)
# When a numeric line is found we treat it as the start of a cue: read the
# following timecode line and then the cue body up to the next blank line.
# 对于只包含数字的行，视为字幕块编号，随后读取时间码行与正文，直到空行为止。
$0 ~ /^[0-9]+$/ {
    cueIndex = $0
    if ((getline cueTimecode) > 0) {
        if (cueTimecode ~ /\r$/) useCRLF = 1
        sub(/\r$/, "", cueTimecode)
        if (is_timecode(cueTimecode)) {
            # Confirmed valid cue / 确认是有效字幕块
            validSRT = 1
            out(cueIndex)
            out(cueTimecode)

            # Read cue body until blank line or EOF / 读取正文直到空行或文件结束
            n = 0; delete L
            while ((getline aline) > 0) {
                if (aline ~ /\r$/) useCRLF = 1
                sub(/\r$/, "", aline)
                if (aline == "") break
                L[++n] = aline
            }

            # Case A: empty body → preserve empty cue / 情况 A：正文为空
            if (n == 0) { out(""); next }

            # Case B: multiple lines → output as-is (do not reflow) / 情况 B：正文多行 → 保持原样
            if (n > 1) { for (i = 1; i <= n; i++) out(L[i]); out(""); next }

            # Case C: single line → attempt splitting / 情况 C：正文单行 → 尝试拆分
            raw = trim(L[1])

            # Extract {\anX} alignment tag if present and keep it on the left line. / 提取 {\anX} 对齐标签
            alignTag = ""
            if (match(raw, /^\{\\an[0-9]+\}/)) {
                alignTag = substr(raw, RSTART, RLENGTH)
                raw = substr(raw, RSTART + RLENGTH)
                raw = trim(raw)
            }

            # Step 1: try hyphen-based dialogue splitting / 第一步：尝试 “-” 对话拆分
            hyc = find_hyphens_positions(raw)
            if (hyc >= 2) {
                splitPos = hypos[2] # use second valid "-" (common pattern: "A - B") / 使用第二个合法 “-” 位置
                a_raw = substr(raw, 1, splitPos-1)
                b_orig = substr(raw, splitPos)
                # Check if "-" followed by space / 判断 “-” 后是否跟空格
                if (substr(raw, splitPos+1, 1) ~ /[[:space:]]/) sep = "- "
                else sep = "-"
                # Extract rest after hyphen and normalize / 提取 “-” 之后的部分
                rest = b_orig
                sub(/^-+/, "", rest)
                sub(/^[ \t]+/, "", rest)
                rest = trim(rest)
                # If rest is empty or punctuation-only → cancel hyphen split
                # 如果右半部分为空或仅是标点 → 取消 “-” 拆分
                if (!(rest == "" || is_punct_only(rest))) {
                    bnorm = sep rest
                    a = trim(a_raw)
                    if (alignTag != "") a = alignTag a
                    out(a)
                    out(bnorm)
                    out("")
                    next
                }
                # else fall through to long-line splitting / 否则进入长句拆分
            }

            # Step 2: try long-line splitting (space / punct / bracket-aware / fallback) / 第二步：尝试长句智能拆分
            if (split_line(raw)) {
                left = SL_L; right = SL_R
                if (alignTag != "") left = alignTag left
                out(left); out(right); out(""); next
            }

            # Step 3: no split → output original (with alignment tag if present) / 第三步：无法拆分 → 原样输出
            if (alignTag != "") out(alignTag raw)
            else out(raw)
            out("")
            next
        } else {
            # Not a timecode → passthrough / 若非时间码 → 原样输出
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