from src.ledger import Ledger, OutOfStock


def test_reserve_reduces_available():
    ledger = Ledger({"sku-1": 5})
    ledger.reserve("order-1", "sku-1", 2)
    assert ledger.on_hand("sku-1") == 5


def test_reserve_rejects_oversell():
    ledger = Ledger({"sku-1": 1})
    try:
        ledger.reserve("order-1", "sku-1", 2)
    except OutOfStock:
        return
    raise AssertionError("expected OutOfStock")
