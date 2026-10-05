import sys
import threading
import time

import pytest

from src.ledger import Ledger, OutOfStock


class FakeClock:
    def __init__(self, now=0.0):
        self.now = now

    def __call__(self):
        return self.now


def test_available_subtracts_active_reservations():
    ledger = Ledger({"a": 5}, ttl=10, clock=FakeClock())
    ledger.reserve("o1", "a", 2)
    assert ledger.available("a") == 3


def test_available_unknown_sku_is_zero():
    assert Ledger(ttl=10, clock=FakeClock()).available("missing") == 0


def test_reservation_expires_at_ttl():
    clock = FakeClock(100.0)
    ledger = Ledger({"a": 5}, ttl=10, clock=clock)
    ledger.reserve("o1", "a", 2)
    clock.now = 110.0
    assert ledger.available("a") == 5


def test_reservation_is_active_just_before_ttl():
    clock = FakeClock(100.0)
    ledger = Ledger({"a": 5}, ttl=10, clock=clock)
    ledger.reserve("o1", "a", 2)
    clock.now = 109.5
    assert ledger.available("a") == 3


def test_reservations_never_expire_without_ttl():
    clock = FakeClock()
    ledger = Ledger({"a": 5}, clock=clock)
    ledger.reserve("o1", "a", 2)
    clock.now = 1e9
    assert ledger.available("a") == 3


def test_expired_stock_can_be_reserved_again():
    clock = FakeClock()
    ledger = Ledger({"a": 2}, ttl=5, clock=clock)
    ledger.reserve("o1", "a", 2)
    with pytest.raises(OutOfStock):
        ledger.reserve("o2", "a", 1)
    clock.now = 5.0
    assert ledger.reserve("o2", "a", 2) == "o2"
    assert ledger.available("a") == 0


def test_release_returns_stock():
    ledger = Ledger({"a": 3}, ttl=10, clock=FakeClock())
    ledger.reserve("o1", "a", 3)
    ledger.release("a", 2)
    assert ledger.available("a") == 2


def test_release_more_than_active_raises_and_leaves_state():
    clock = FakeClock()
    ledger = Ledger({"a": 5}, ttl=10, clock=clock)
    ledger.reserve("o1", "a", 2)
    with pytest.raises(ValueError):
        ledger.release("a", 3)
    assert ledger.available("a") == 3
    clock.now = 10.0
    with pytest.raises(ValueError):
        ledger.release("a", 1)
    assert ledger.available("a") == 5


@pytest.mark.parametrize("qty", [0, -1])
def test_release_non_positive_raises_and_leaves_state(qty):
    ledger = Ledger({"a": 5}, ttl=10, clock=FakeClock())
    ledger.reserve("o1", "a", 2)
    with pytest.raises(ValueError):
        ledger.release("a", qty)
    assert ledger.available("a") == 3


def test_existing_behaviour_is_kept_with_default_clock():
    ledger = Ledger({"a": 5})
    assert ledger.reserve("o1", "a", 2) == "o1"
    assert ledger.on_hand("a") == 5
    with pytest.raises(OutOfStock):
        ledger.reserve("o2", "a", 4)


def _slow_clock():
    # Yields inside reserve(), widening any unguarded check-then-act window.
    time.sleep(0.0005)
    return 0.0


def _run_threads(count, target):
    barrier = threading.Barrier(count)
    errors = []

    def body(i):
        try:
            barrier.wait()
            target(i)
        except Exception as exc:  # noqa: BLE001 - surfaced through the assertion below
            errors.append(exc)

    threads = [threading.Thread(target=body, args=(i,)) for i in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)
    assert not any(thread.is_alive() for thread in threads), "worker threads deadlocked"
    return errors


def test_concurrent_reserves_never_oversell():
    previous = sys.getswitchinterval()
    sys.setswitchinterval(1e-6)
    try:
        ledger = Ledger({"a": 20}, ttl=60, clock=_slow_clock)
        wins = []

        def reserve_one(i):
            try:
                ledger.reserve(f"o{i}", "a", 1)
                wins.append(i)
            except OutOfStock:
                pass

        errors = _run_threads(40, reserve_one)
        assert errors == []
        assert len(wins) == 20
        assert ledger.available("a") == 0
    finally:
        sys.setswitchinterval(previous)


def test_concurrent_reserve_and_release_balance():
    previous = sys.getswitchinterval()
    sys.setswitchinterval(1e-6)
    try:
        ledger = Ledger({"a": 10}, ttl=60, clock=_slow_clock)

        def cycle(i):
            ledger.reserve(f"o{i}", "a", 1)
            ledger.release("a", 1)

        errors = _run_threads(10, cycle)
        assert errors == []
        assert ledger.available("a") == 10
    finally:
        sys.setswitchinterval(previous)
