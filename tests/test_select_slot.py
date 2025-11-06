import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[1]))

from src.traffic import select_slot


def test_determine_slot_defaults_to_primary_when_no_traffic():
    assert select_slot._determine_slot({}, "blue", "green") == "blue"


def test_determine_slot_uses_alternate_when_default_active_only():
    traffic = {"blue": 100}
    assert select_slot._determine_slot(traffic, "blue", "green") == "green"


def test_determine_slot_prefers_slot_with_lowest_traffic_share():
    traffic = {"blue": 70, "green": 30}
    assert select_slot._determine_slot(traffic, "blue", "green") == "green"


def test_determine_slot_handles_case_insensitive_names():
    traffic = {"Blue": 10, "GREEN": 90}
    assert select_slot._determine_slot(traffic, "blue", "green") == "blue"
