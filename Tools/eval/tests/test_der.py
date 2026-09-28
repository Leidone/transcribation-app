import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from der import Segment, attribution_accuracy, load_segments  # noqa: E402


def seg(start, end, speaker):
    return Segment(start=start, end=end, speaker=speaker)


REFERENCE = [seg(0, 10, "anna"), seg(10, 20, "boris")]


def test_perfect_attribution_is_one():
    hypothesis = [seg(0, 10, "S0"), seg(10, 20, "S1")]
    assert attribution_accuracy(REFERENCE, hypothesis) == 1.0


def test_swapped_labels_still_score_one_after_optimal_mapping():
    hypothesis = [seg(0, 10, "S1"), seg(10, 20, "S0")]
    assert attribution_accuracy(REFERENCE, hypothesis) == 1.0


def test_half_of_the_speech_attributed_wrongly_is_point_five():
    # a single hypothesis speaker can only be mapped to one reference speaker
    hypothesis = [seg(0, 20, "S0")]
    assert attribution_accuracy(REFERENCE, hypothesis) == 0.5


def test_empty_hypothesis_is_zero():
    assert attribution_accuracy(REFERENCE, []) == 0.0


def test_empty_reference_raises():
    with pytest.raises(ValueError):
        attribution_accuracy([], [seg(0, 1, "S0")])


def test_load_segments_reads_csv(tmp_path):
    path = tmp_path / "ref.speakers.csv"
    path.write_text("start,end,speaker\n0.0,4.5,anna\n4.5,9.0,boris\n", encoding="utf-8")

    assert load_segments(path) == [seg(0.0, 4.5, "anna"), seg(4.5, 9.0, "boris")]
