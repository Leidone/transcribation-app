import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wer import normalize, wer_percent  # noqa: E402


def test_identical_text_has_zero_wer():
    # Arrange
    reference = "Давайте созвонимся завтра в десять"

    # Act
    result = wer_percent(reference, reference)

    # Assert
    assert result == 0.0


def test_empty_hypothesis_is_one_hundred_percent():
    assert wer_percent("one two three", "") == 100.0


def test_one_substitution_in_four_words_is_twenty_five_percent():
    assert wer_percent("we ship on friday", "we ship on monday") == 25.0


def test_case_and_punctuation_are_ignored():
    assert wer_percent("Hello, world!", "hello world") == 0.0


def test_yo_and_ye_are_treated_as_the_same_letter():
    assert normalize("Всё ещё") == normalize("Все еще")


def test_empty_reference_raises():
    with pytest.raises(ValueError):
        wer_percent("", "anything")
