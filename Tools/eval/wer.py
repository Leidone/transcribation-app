"""Word error rate for the ASR spike (ru/en). Usage: python wer.py ref.txt hyp.txt"""

import re
import sys
from pathlib import Path

import jiwer

_NON_WORD = re.compile(r"[^\w\s']", flags=re.UNICODE)
_WHITESPACE = re.compile(r"\s+")


def normalize(text: str) -> str:
    """Lowercase, fold ё→е, drop punctuation, collapse whitespace."""
    folded = text.lower().replace("ё", "е")
    without_punctuation = _NON_WORD.sub(" ", folded)
    return _WHITESPACE.sub(" ", without_punctuation).strip()


def wer_percent(reference: str, hypothesis: str) -> float:
    normalized_reference = normalize(reference)
    if not normalized_reference:
        raise ValueError("reference text is empty after normalization")
    normalized_hypothesis = normalize(hypothesis)
    if not normalized_hypothesis:
        return 100.0
    return round(jiwer.wer(normalized_reference, normalized_hypothesis) * 100, 2)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: wer.py ref.txt hyp.txt", file=sys.stderr)
        return 2
    reference = Path(argv[1]).read_text(encoding="utf-8")
    hypothesis = Path(argv[2]).read_text(encoding="utf-8")
    print(wer_percent(reference, hypothesis))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
