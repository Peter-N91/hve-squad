from src.ledger import Ledger, OutOfStock
import pytest


def test_available_subtracts_reservations():
    ledger = Ledger({"a": 5})
    ledger.reserve("o1", "a", 2)
    assert ledger.available("a") == 3


def test_available_without_reservations_is_on_hand():
    assert Ledger({"a": 4}).available("a") == 4


def test_available_unknown_sku_is_zero():
    assert Ledger().available("missing") == 0


def test_available_is_zero_when_fully_reserved():
    ledger = Ledger({"a": 2})
    ledger.reserve("o1", "a", 2)
    assert ledger.available("a") == 0


def test_release_returns_stock_to_available():
    ledger = Ledger({"a": 3})
    ledger.reserve("o1", "a", 3)
    ledger.release("a", 1)
    assert ledger.available("a") == 1


def test_existing_behaviour_is_unchanged():
    ledger = Ledger({"a": 5})
    assert ledger.reserve("o1", "a", 2) == "o1"
    assert ledger.on_hand("a") == 5
    with pytest.raises(OutOfStock):
        ledger.reserve("o2", "a", 4)
