from src.ledger import Ledger, OutOfStock
import pytest


def test_available_subtracts_reservations():
    ledger = Ledger({"a": 5})
    ledger.reserve("o1", "a", 2)
    assert ledger.available("a") == 3


def test_available_unknown_sku_is_zero():
    assert Ledger().available("missing") == 0


def test_on_hand_unchanged_by_reserve():
    ledger = Ledger({"a": 5})
    ledger.reserve("o1", "a", 2)
    assert ledger.on_hand("a") == 5


def test_release_returns_stock():
    ledger = Ledger({"a": 2})
    ledger.reserve("o1", "a", 2)
    ledger.release("a", 2)
    assert ledger.available("a") == 2


def test_release_more_than_reserved_raises_and_leaves_state():
    ledger = Ledger({"a": 5})
    ledger.reserve("o1", "a", 2)
    with pytest.raises(ValueError):
        ledger.release("a", 3)
    assert ledger.available("a") == 3


def test_release_unreserved_sku_raises():
    with pytest.raises(ValueError):
        Ledger({"a": 5}).release("a", 1)


@pytest.mark.parametrize("qty", [0, -1])
def test_release_non_positive_raises_and_leaves_state(qty):
    ledger = Ledger({"a": 5})
    ledger.reserve("o1", "a", 2)
    with pytest.raises(ValueError):
        ledger.release("a", qty)
    assert ledger.available("a") == 3


def test_reserve_still_rejects_oversell():
    ledger = Ledger({"a": 1})
    with pytest.raises(OutOfStock):
        ledger.reserve("o1", "a", 2)


def test_reserve_rejects_request_exceeding_remaining():
    ledger = Ledger({"a": 3})
    ledger.reserve("o1", "a", 2)
    with pytest.raises(OutOfStock):
        ledger.reserve("o2", "a", 2)


def test_reserve_returns_order_id():
    assert Ledger({"a": 1}).reserve("o1", "a", 1) == "o1"
