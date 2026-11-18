"""Pure allocation engine for Spliqo.

Implements the Largest Remainder Method (Hamilton-Hare) for exact paise splits
and live share estimation. No I/O, no floats, no datetime, no randomness.
Authoritative implementation validated against shared/allocation_vectors.json.
"""

from typing import Final

MAX_RECEIPT_TOTAL_PAISE: Final[int] = 10_000_000


def split_exact(amount: int, weights: dict[str, int]) -> dict[str, int]:
    """Largest Remainder split of a non-negative integer amount.

    Args:
        amount: Non-negative integer in paise to split.
        weights: Dictionary of keys (lowercase UUID strings) to non-negative
                 integer weights. At least one weight must be positive.

    Returns:
        Dictionary mapping each key to its exact integer share.
        The sum of returned values is guaranteed to equal `amount`.

    Raises:
        ValueError: If amount < 0, sum(weights) <= 0, or any weight < 0.
    """
    total_w = sum(weights.values())
    if amount < 0 or total_w <= 0 or any(w < 0 for w in weights.values()):
        raise ValueError("invalid_split_input")
    base: dict[str, int] = {}
    rem: dict[str, int] = {}
    for key, w in weights.items():
        base[key], rem[key] = divmod(amount * w, total_w)
    leftover = amount - sum(base.values())
    # Deterministic tie-breaking: largest remainder first; if equal, ascending lexicographical key
    for key in sorted(weights, key=lambda k: (-rem[k], k))[:leftover]:
        base[key] += 1
    return base


def _distribute_items(
    items: dict[str, int],
    claims: dict[str, list[str]],
    participants: list[str],
) -> dict[str, int]:
    """Distribute item costs among claimants using Largest Remainder split."""
    items_total = {p: 0 for p in participants}
    for item_id, price in items.items():
        claimants = claims.get(item_id, [])
        if not claimants:
            raise ValueError("unclaimed_item")  # host must resolve first
        for p, share in split_exact(price, {p: 1 for p in claimants}).items():
            if p not in items_total:
                items_total[p] = 0
            items_total[p] += share
    return items_total


def calculate_split(
    items: dict[str, int],
    claims: dict[str, list[str]],
    participants: list[str],
    subtotal_paise: int,
    total_paise: int,
) -> dict[str, int]:
    """Authoritative final amounts for all participants in a finalized session.

    Invariants enforced:
    1. sum(items.values()) == subtotal_paise >= 1
    2. 1 <= total_paise <= MAX_RECEIPT_TOTAL_PAISE
    3. Every item must have at least one claimant (no unallocated items allowed)
    4. sum(final.values()) == total_paise exactly
    5. all(final_i >= 0)
    6. Participant with 0 items receives 0 adjustment and 0 final share

    Args:
        items: Mapping of item_id to price in paise.
        claims: Mapping of item_id to list of participant_ids claiming it.
        participants: Complete list of participant IDs in the session.
        subtotal_paise: Sum of item prices in paise.
        total_paise: Final receipt total in paise.

    Returns:
        Mapping of participant_id to exact final amount in paise.

    Raises:
        ValueError: If validation fails or invariants are violated.
    """
    if sum(items.values()) != subtotal_paise or subtotal_paise < 1:
        raise ValueError("items_do_not_match_subtotal")
    if not 1 <= total_paise <= MAX_RECEIPT_TOTAL_PAISE:
        raise ValueError("total_out_of_range")

    items_total = _distribute_items(items, claims, participants)
    adjustment = total_paise - subtotal_paise  # signed: tax + service - discount + round-off
    if abs(adjustment) > 0 and sum(items_total.values()) > 0:
        adj = split_exact(abs(adjustment), items_total)
    else:
        adj = {p: 0 for p in participants}

    sign = -1 if adjustment < 0 else 1
    final = {p: items_total[p] + sign * adj[p] for p in participants}

    if sum(final.values()) != total_paise:
        raise RuntimeError("sum_invariant_failed")
    if any(v < 0 for v in final.values()):
        raise RuntimeError("negative_share")
    return final


def estimate_share(items_paise: int, subtotal_paise: int, total_paise: int) -> int:
    """Live provisional estimate for one participant during active session.

    Computes adjustment against the entire receipt subtotal (not current claims),
    using integer round_half_up.

    Args:
        items_paise: Participant's current claimed items total in paise.
        subtotal_paise: Total receipt subtotal in paise.
        total_paise: Total receipt bill in paise.

    Returns:
        Provisional estimated share in paise.
    """
    if subtotal_paise < 1:
        raise ValueError("invalid_subtotal_paise")
    if items_paise < 0:
        raise ValueError("invalid_items_paise")
    adjustment = total_paise - subtotal_paise
    a = abs(adjustment)
    adj = (a * items_paise + subtotal_paise // 2) // subtotal_paise
    return items_paise + (adj if adjustment >= 0 else -adj)
