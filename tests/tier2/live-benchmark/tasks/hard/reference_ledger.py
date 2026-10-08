"""Reference ledger for the hard level. LEDGER_MUTANT selects a planted defect."""
import os
import threading
import time

MUTANT = os.environ.get("LEDGER_MUTANT", "")


class OutOfStock(Exception):
    pass


class _NoLock:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Ledger:
    def __init__(self, initial=None, ttl=None, clock=None):
        if ttl is not None and ttl <= 0:
            raise ValueError("ttl must be positive")
        self._stock = dict(initial or {})
        self._ttl = ttl
        self._clock = clock or time.monotonic
        # sku -> list of [expires_at or None, quantity]
        self._holds = {}
        self._lock = _NoLock() if MUTANT == "no-lock" else threading.Lock()

    def _active(self, sku, now):
        holds = self._holds.get(sku, [])
        if MUTANT == "ignore-expiry":
            return holds
        if MUTANT == "expiry-off-by-one":
            holds = [h for h in holds if h[0] is None or now <= h[0]]
        else:
            holds = [h for h in holds if h[0] is None or now < h[0]]
        self._holds[sku] = holds
        return holds

    def on_hand(self, sku):
        return self._stock.get(sku, 0)

    def available(self, sku):
        with self._lock:
            return self.on_hand(sku) - sum(q for _, q in self._active(sku, self._clock()))

    def reserve(self, order_id, sku, quantity):
        with self._lock:
            free = self.on_hand(sku) - sum(q for _, q in self._active(sku, self._clock()))
            if free < quantity:
                raise OutOfStock(sku)
            now = self._clock()
            expires = None if self._ttl is None else now + self._ttl
            self._holds.setdefault(sku, []).append([expires, quantity])
            return order_id

    def release(self, sku, quantity):
        with self._lock:
            holds = self._active(sku, self._clock())
            if quantity <= 0 or quantity > sum(q for _, q in holds):
                raise ValueError(sku)
            if MUTANT == "release-noop":
                return
            remaining = quantity
            for hold in reversed(holds):
                take = min(hold[1], remaining)
                hold[1] -= take
                remaining -= take
                if remaining == 0:
                    break
            self._holds[sku] = [h for h in holds if h[1] > 0]
