"""Speaker attribution accuracy for the diarization spike.

Share of reference speech time (seconds) where the hypothesis speaker, after the best
one-to-one mapping of hypothesis labels to reference labels, matches the reference speaker.
Usage: python der.py ref.speakers.csv hyp.speakers.csv
"""

import csv
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.optimize import linear_sum_assignment


@dataclass(frozen=True)
class Segment:
    start: float
    end: float
    speaker: str


def load_segments(path: Path) -> list[Segment]:
    with Path(path).open(encoding="utf-8", newline="") as handle:
        return [
            Segment(float(row["start"]), float(row["end"]), row["speaker"])
            for row in csv.DictReader(handle)
        ]


def _overlap(a: Segment, b: Segment) -> float:
    return max(0.0, min(a.end, b.end) - max(a.start, b.start))


def attribution_accuracy(reference: list[Segment], hypothesis: list[Segment]) -> float:
    total_speech = sum(s.end - s.start for s in reference)
    if total_speech <= 0:
        raise ValueError("reference has no speech")
    if not hypothesis:
        return 0.0

    reference_speakers = sorted({s.speaker for s in reference})
    hypothesis_speakers = sorted({s.speaker for s in hypothesis})
    overlap_matrix = np.zeros((len(reference_speakers), len(hypothesis_speakers)))
    for ref in reference:
        for hyp in hypothesis:
            overlap_seconds = _overlap(ref, hyp)
            if overlap_seconds:
                row = reference_speakers.index(ref.speaker)
                column = hypothesis_speakers.index(hyp.speaker)
                overlap_matrix[row, column] += overlap_seconds

    rows, columns = linear_sum_assignment(-overlap_matrix)
    matched_seconds = overlap_matrix[rows, columns].sum()
    return round(float(matched_seconds / total_speech), 4)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: der.py ref.speakers.csv hyp.speakers.csv", file=sys.stderr)
        return 2
    print(attribution_accuracy(load_segments(Path(argv[1])), load_segments(Path(argv[2]))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
