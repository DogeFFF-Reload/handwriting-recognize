"""和 App 用同一套识别调用：提示词直接从 InkCore 的 Swift 源码里读，请求体和回复解析照抄
Packages/InkCore/Sources/InkCore/{Recognizers,NetworkRecognizers}.swift。那边改了，这里跟着改。"""

import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RECOGNIZERS_SWIFT = REPO / "Packages/InkCore/Sources/InkCore/Recognizers.swift"

# DashScope.beijing
BEIJING_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
# DashScopeRecognizer 的默认模型顺序：先 flash，失败换 vl-plus。实测时一次只测一个。
APP_MODELS = ["qwen3.8-flash", "qwen3-vl-plus"]

_SWIFT_ESCAPES = {"\\": "\\", '"': '"', "'": "'", "n": "\n", "t": "\t", "r": "\r", "0": "\0"}


def load_recognition_prompt(path: Path = RECOGNIZERS_SWIFT) -> str:
    """读出 `public let recognitionPrompt = \"\"\" ... \"\"\"` 的值（Swift 多行字符串字面量）。"""
    lines = path.read_text(encoding="utf-8").split("\n")
    try:
        start = next(i for i, line in enumerate(lines) if re.match(r'\s*public let recognitionPrompt\s*=\s*"""\s*$', line))
        end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == '"""')
    except StopIteration:
        raise RuntimeError(f"{path} 里找不到 recognitionPrompt 的多行字符串") from None
    indent = lines[end][: len(lines[end]) - len(lines[end].lstrip())]
    body = [line[len(indent):] if line.startswith(indent) else line.lstrip() for line in lines[start + 1:end]]
    text = "\n".join(body)
    if "\\(" in text:
        raise RuntimeError("recognitionPrompt 里有字符串插值，脚本没法照抄")
    return re.sub(r"\\(.)", lambda m: _SWIFT_ESCAPES.get(m.group(1), m.group(0)), text)


def chat_body(model: str, image_png_base64: str, prompt: str) -> dict:
    """DashScope.chat(model:imagePNG:prompt:maxTokens: 200, temperature: 0) 发出的请求体。"""
    body = {
        "model": model,
        "messages": [{"role": "user", "content": [
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + image_png_base64}},
            {"type": "text", "text": prompt},
        ]}],
        "max_tokens": 200,
        "temperature": 0,
    }
    if model.startswith("qwen3.8"):
        body["enable_thinking"] = False
    return body


def reply_text(response: dict) -> str:
    return response["choices"][0]["message"]["content"]


def extract_latex(reply: str) -> str:
    """extractLatex(fromModelReply:)：取第一个 { 到最后一个 } 之间的 JSON，读 latex。取不到就抛错。"""
    start, end = reply.find("{"), reply.rfind("}")
    if start < 0 or end <= start:
        raise ValueError(f"回复里没有 JSON：{reply[:120]}")
    try:
        obj = json.loads(reply[start:end + 1])
    except json.JSONDecodeError as e:
        raise ValueError(f"回复里的 JSON 解析失败：{reply[:120]}") from e
    if not isinstance(obj, dict) or not isinstance(obj.get("latex"), str):
        raise ValueError(f"回复里没有 latex 字段：{reply[:120]}")
    return obj["latex"].strip()
