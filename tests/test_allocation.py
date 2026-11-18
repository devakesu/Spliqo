"""Tests for the pure allocation engine.

Validates implementation against shared/allocation_vectors.json and tests invariants.
"""

import json
from pathlib import Path
from typing import Any, cast

import pytest

from app.domain.allocation import (
    MAX_RECEIPT_TOTAL_PAISE,
    calculate_split,
    estimate_share,
    split_exact,
)

SHARED_VECTORS_PATH = Path(__file__).resolve().parent.parent / "shared" / "allocation_vectors.json"


@pytest.fixture
def allocation_vectors_data() -> dict[str, Any]:
    """Load the shared golden vectors."""
    with open(SHARED_VECTORS_PATH, encoding="utf-8") as f:
        return cast(dict[str, Any], json.load(f))


def test_shared_golden_vectors(allocation_vectors_data: dict[str, Any]) -> None:
    """Assert calculate_split matches all shared golden vectors."""
    vectors = cast(list[dict[str, Any]], allocation_vectors_data["vectors"])
    for vec in vectors:
        items = cast(dict[str, int], vec["items"])
        claims = cast(dict[str, list[str]], vec["claims"])
        participants = cast(list[str], vec["participants"])
        subtotal_paise = cast(int, vec["subtotal_paise"])
        total_paise = cast(int, vec["total_paise"])
        expected_final = cast(dict[str, int], vec["expected_final"])

        result = calculate_split(
            items=items,
            claims=claims,
            participants=participants,
            subtotal_paise=subtotal_paise,
            total_paise=total_paise,
        )
        assert result == expected_final, f"Mismatch in vector: {vec['name']}"
        assert sum(result.values()) == total_paise


def test_shared_estimate_vectors(allocation_vectors_data: dict[str, Any]) -> None:
    """Assert estimate_share matches all shared estimate vectors."""
    estimates = cast(list[dict[str, Any]], allocation_vectors_data["estimates"])
    for est in estimates:
        items_paise = cast(int, est["items_paise"])
        subtotal_paise = cast(int, est["subtotal_paise"])
        total_paise = cast(int, est["total_paise"])
        expected_estimate = cast(int, est["expected_estimate"])

        result = estimate_share(
            items_paise=items_paise,
            subtotal_paise=subtotal_paise,
            total_paise=total_paise,
        )
        assert result == expected_estimate, f"Mismatch in estimate: {est['name']}"


def test_split_exact_invariants() -> None:
    """Assert split_exact invariants."""
    # Sum of parts must exactly equal amount
    result = split_exact(100, {"a": 1, "b": 1, "c": 1})
    assert sum(result.values()) == 100
    assert result == {"a": 34, "b": 33, "c": 33}

    # Zero amount
    assert split_exact(0, {"a": 1, "b": 2}) == {"a": 0, "b": 0}

    # Negative amount raises ValueError
    with pytest.raises(ValueError, match="invalid_split_input"):
        split_exact(-10, {"a": 1})

    # Zero total weight raises ValueError
    with pytest.raises(ValueError, match="invalid_split_input"):
        split_exact(100, {"a": 0, "b": 0})

    # Negative weight raises ValueError
    with pytest.raises(ValueError, match="invalid_split_input"):
        split_exact(100, {"a": -1, "b": 2})


def test_calculate_split_unclaimed_item_raises() -> None:
    """Assert calculate_split raises if any item is unclaimed."""
    with pytest.raises(ValueError, match="unclaimed_item"):
        calculate_split(
            items={"i1": 5000, "i2": 3000},
            claims={"i1": ["a"]},  # i2 is unclaimed
            participants=["a", "b"],
            subtotal_paise=8000,
            total_paise=8000,
        )


def test_calculate_split_subtotal_mismatch_raises() -> None:
    """Assert calculate_split raises if items do not sum to subtotal_paise."""
    with pytest.raises(ValueError, match="items_do_not_match_subtotal"):
        calculate_split(
            items={"i1": 5000},
            claims={"i1": ["a"]},
            participants=["a"],
            subtotal_paise=6000,  # 5000 != 6000
            total_paise=6000,
        )


def test_calculate_split_total_out_of_range_raises() -> None:
    """Assert total must be between 1 and MAX_RECEIPT_TOTAL_PAISE."""
    with pytest.raises(ValueError, match="total_out_of_range"):
        calculate_split(
            items={"i1": 100},
            claims={"i1": ["a"]},
            participants=["a"],
            subtotal_paise=100,
            total_paise=0,
        )

    with pytest.raises(ValueError, match="total_out_of_range"):
        calculate_split(
            items={"i1": 100},
            claims={"i1": ["a"]},
            participants=["a"],
            subtotal_paise=100,
            total_paise=MAX_RECEIPT_TOTAL_PAISE + 1,
        )


def test_estimate_share_invalid_inputs() -> None:
    """Assert estimate_share validates inputs."""
    with pytest.raises(ValueError, match="invalid_subtotal_paise"):
        estimate_share(items_paise=10, subtotal_paise=0, total_paise=100)

    with pytest.raises(ValueError, match="invalid_items_paise"):
        estimate_share(items_paise=-1, subtotal_paise=100, total_paise=100)

