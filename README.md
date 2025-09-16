# SRT Tools

**中文 | [English](./README.en.md)**

SRT Tools 是由 蒙太奇字幕组 (MontageSubs) 开发的 SRT 字幕处理工具集合。

本仓库提供独立脚本，用于常见的字幕处理任务（中英行颠倒、提取纯中文字幕、中文字幕智能换行）。

该仓库也可作为其他字幕处理项目的 CI 自动化组件。


## 文件结构

```
srt-tools/
├── scripts/
│   └── awk/                 # AWK 脚本
│       ├── srt_zh_en_swap.awk
│       ├── srt_zh_only.awk
│       └── srt_zh_wrap.awk
└── examples/                # 示例字幕
    ├── srt_zh_en_swap/
    │   └── output_sorry_baby_swapped.srt
    ├── srt_zh_only/
    │   └── output_sorry_baby_chs.srt
    └── srt_zh_wrap/
        └── output_sorry_baby_wrapped.srt
```



## 脚本说明

### [`srt_zh_en_swap.awk`](scripts/awk/srt_zh_en_swap.awk)

#### 功能
交换中英文字幕行顺序，将「中上英下」调整为「英上中下」。
- 如果字幕块只有一行或多于两行，则保持原样不变。
- 保留样式标签（如 `<i>`、`{\anX}`）、换行符格式。

#### 用法
```bash
$ awk -f srt_zh_en_swap.awk input.srt > output.srt
```


### [`srt_zh_only.awk`](scripts/awk/srt_zh_only.awk)

#### 功能
删除字幕中的英文行，仅保留中文字幕。
- 如果某个字幕块完全没有中文，该字幕块会被自动移除。
- 输出时会对所有字幕块重新编号。
- 保留时间轴、样式标签（如 `<i>`、`{\anX}`）、换行符格式。

#### 用法
```bash
$ awk -f srt_zh_only.awk input.srt > output.srt
```


### [`srt_zh_wrap.awk`](scripts/awk/srt_zh_wrap.awk)

#### 功能
对过长的单行中文字幕进行智能换行：
- 优先在对话符（`-`）、空格或标点处拆分；
- 考虑括号/引号范围，以减少破坏语义；
- 拆分后遵循“金字塔式排版”（上短下长），以优化阅读节奏。
- 保留样式标签（如 `<i>`、`{\anX}`）、换行符格式。

#### 说明
脚本不使用词典或分词器，在某些情况下可能会把词语错误拆开。
引入词典会显著增加实现复杂度，因此暂未纳入。
如遇不合适的断行，请手动修正。

#### 参数
- `SPLIT_THRESHOLD`：换行阈值（按“汉字”计数，默认值 `20`）。
- `BRACKET_FACTOR`：括号内长度容忍倍数（默认值 `2`）。

#### 用法示例
```bash
# 使用默认参数（SPLIT_THRESHOLD=20, BRACKET_FACTOR=2）
$ awk -f srt_zh_wrap.awk input.srt > output.srt

# 将换行阈值设为 15
$ awk -v SPLIT_THRESHOLD=15 -f srt_zh_wrap.awk input.srt > output.srt

# 自定义阈值与括号因子
$ awk -v SPLIT_THRESHOLD=15 -v BRACKET_FACTOR=1 -f srt_zh_wrap.awk input.srt > output.srt
```


## 示例

本仓库提供了 [`examples`](./examples/) 目录，可直接查看示例输出结果。



## 许可协议

本仓库的源代码与文档（除另有说明部分外）遵循 [MIT License](./LICENSE) 授权，由 **蒙太奇字幕组 (MontageSubs)** 维护。

位于 `examples` 目录下的示例文件及子目录不适用 MIT 许可，另行采用 [CC BY-NC-SA 4.0](./examples/LICENSE) 协议发布。

除 `examples` 目录另行声明的部分外，其余文件一律适用 MIT 许可协议。



## 社群

欢迎加入我们的交流群，交流字幕处理问题、电影相关话题，反馈本项目意见，或参与字幕制作：

- **Telegram**：[蒙太奇字幕组电报群](https://t.me/+HCWwtDjbTBNlM2M5)
- **IRC**：[#MontageSubs](https://web.libera.chat/#MontageSubs) （与 Telegram 互联）


---

<div align="center">

**蒙太奇字幕组 (MontageSubs)**

“用爱发电 ❤️ Powered by love”

</div>
