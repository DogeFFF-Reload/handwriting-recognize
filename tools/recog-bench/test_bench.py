import tempfile
import unittest
from pathlib import Path

from bench import Attempt, EngineReport, choose, load_samples, score
from inkcore import chat_body, extract_latex, load_recognition_prompt
from normalize import equivalent, normalize


class InkCoreParityTests(unittest.TestCase):
    def test_reads_the_prompt_from_recognizers_swift(self):
        prompt = load_recognition_prompt()
        self.assertTrue(prompt.startswith("你是手写数学识别器，只负责逐字照抄"))
        self.assertIn('{"latex": "这行的 LaTeX"}', prompt)
        self.assertFalse(prompt.endswith("\n"), "结尾的 \"\"\" 前面那个换行不属于字符串")

    def test_swift_multiline_literal_rules(self):
        swift = 'x\n    public let recognitionPrompt = """\n    第一行\n      缩进 \\"引号\\" \\\\ 反斜杠\n    """\n'
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "R.swift"
            path.write_text(swift, encoding="utf-8")
            self.assertEqual(load_recognition_prompt(path), '第一行\n  缩进 "引号" \\ 反斜杠')

    def test_request_body_matches_dashscope_chat(self):
        body = chat_body("qwen3.8-flash", "AAA", "提示")
        self.assertEqual(body["max_tokens"], 200)
        self.assertEqual(body["temperature"], 0)
        self.assertIs(body["enable_thinking"], False)
        content = body["messages"][0]["content"]
        self.assertEqual(content[0]["image_url"]["url"], "data:image/png;base64,AAA")
        self.assertEqual(content[1], {"type": "text", "text": "提示"})
        self.assertNotIn("enable_thinking", chat_body("qwen3-vl-plus", "AAA", "提示"), "只有 qwen3.8 才关推理")

    def test_extract_latex_like_the_app(self):
        self.assertEqual(extract_latex('{"latex": "f(x)=x^3-3x"}'), "f(x)=x^3-3x")
        self.assertEqual(extract_latex('好的：\n```json\n{"latex": " 3x^2-3x "}\n```'), "3x^2-3x")
        self.assertEqual(extract_latex('{"latex": ""}'), "")
        for bad in ["f(x)=x^3", "{not json}", '{"text": "x"}']:
            with self.assertRaises(ValueError):
                extract_latex(bad)


class NormalizeTests(unittest.TestCase):
    def test_four_rules_from_the_report(self):
        self.assertTrue(equivalent("f(x) = x^3 - 3x", "f(x)=x^3-3x"))
        self.assertTrue(equivalent("3x^2\\cdot 2", "3x^2\\times2"))
        self.assertTrue(equivalent("3x^2\\cdot 2", "3x^2 2"))
        self.assertTrue(equivalent("3x^{2}-3", "3x^2-3"))
        self.assertTrue(equivalent("x^3−3x", "x^3-3x"))
        self.assertTrue(equivalent("x^3－3x", "x^3-3x"))
        self.assertTrue(equivalent("\\int x^2\\,dx", "\\int x^2 dx"))
        self.assertFalse(equivalent("x^{12}", "x^12"))
        self.assertFalse(equivalent("3x^2-3x", "3x^2-3"))

    def test_normalize_output(self):
        self.assertEqual(normalize("f'(x) = 3x^{2} − 3"), "f'(x)=3x^2-3")


class ScoringTests(unittest.TestCase):
    def setUp(self):
        self.samples = load_samples()

    def perfect(self, name, ms):
        report = EngineReport(name)
        for s in self.samples:
            for rep in range(1, (3 if s.golden else 1) + 1):
                report.add(Attempt(s.id, rep, s.latex, ms))
        return report

    def test_samples_file_has_twenty_rows_and_six_golden(self):
        self.assertEqual(len(self.samples), 20)
        self.assertEqual([s.id for s in self.samples if s.golden], ["S01", "S02", "S03", "S04", "S05", "S06"])

    def test_perfect_engine_passes(self):
        s = score(self.perfect("qwen3.8-flash", 800), self.samples, 2000)
        self.assertTrue(s.passes)
        self.assertEqual(s.correct_samples, 20)

    def test_one_golden_miss_fails_even_with_high_accuracy(self):
        report = self.perfect("qwen3.8-flash", 800)
        # 模型把写错的 3x^2-3x「改对」了，就算错。
        report.attempts["S03"][1] = Attempt("S03", 2, "f'(x)=3x^2-3", 800)
        s = score(report, self.samples, 2000)
        self.assertFalse(s.golden_ok)
        self.assertFalse(s.passes)

    def test_slow_engine_fails(self):
        self.assertFalse(score(self.perfect("qwen3.8-flash", 2500), self.samples, 2000).passes)

    def test_network_failures_count_as_wrong_but_not_as_latency(self):
        report = self.perfect("qwen3.8-flash", 800)
        report.attempts["S20"] = [Attempt("S20", 1, "", None, error="请求失败")]
        s = score(report, self.samples, 2000)
        self.assertEqual(s.correct_samples, 19)
        self.assertEqual(s.p90, 800)

    def test_selection_rule(self):
        good = score(self.perfect("x", 300), self.samples, 500)
        slow = score(self.perfect("x", 2500), self.samples, 2000)
        self.assertEqual(choose(good, slow), "MyScript")
        self.assertTrue(choose(slow, good).startswith("Qwen"))
        self.assertTrue(choose(slow, slow).startswith("回放"))
        self.assertTrue(choose(None, None).startswith("回放"))


if __name__ == "__main__":
    unittest.main()
