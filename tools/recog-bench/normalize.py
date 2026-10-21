"""识别结果和标准答案比对前的归一化（开发方向报告「识别实测」第 4 条）。"""

import re

_SPACES = ["\\,", "\\;", "\\:", "\\!", "\\ ", "\\quad", "\\qquad"]
_TIMES = ["\\cdot", "\\times", "*", "×", "·"]
_MINUS = ["−", "－", "–"]


def normalize(latex: str) -> str:
    """去掉空格；\\cdot、\\times 和省略乘号视为相同；^{2} 和 ^2 视为相同；全角的 − 和 - 视为相同。
    另外把 \\, 这类 LaTeX 间距命令也当空格去掉。"""
    # 矩阵换行 \\ 先保护起来：不然 "\\ 3" 里的 "\ " 会被当成间距删掉，只剩一个反斜杠
    s = latex.replace("\\\\", "\0")
    for sp in _SPACES:
        s = s.replace(sp, "")
    s = "".join(ch for ch in s if not ch.isspace()).replace("\0", "\\\\")
    for t in _TIMES:
        s = s.replace(t, "")
    for m in _MINUS:
        s = s.replace(m, "-")
    # 只拆单个字符的花括号：^{2} -> ^2，^{12} 保持原样
    return re.sub(r"\^\{(.)\}", r"^\1", s)


def equivalent(a: str, b: str) -> bool:
    return normalize(a) == normalize(b)
