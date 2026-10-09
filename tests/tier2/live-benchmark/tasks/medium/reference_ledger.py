"""Reference ledger used to grade the workers' tests. MUTANT selects a planted defect."""
import os

MUTANT = os.environ.get("LEDGER_MUTANT", "")


class OutOfStock(Exception):
    pass


class Ledger:
    def __init__(self, initial=None):
        self._stock = dict(initial or {})
        self._reserved = {}

    def on_hand(self, sku):
        return self._stock.get(sku, 0)

    def available(self, sku):
        return self.on_hand(sku) - self._reserved.get(sku, 0)

    def reserve(self, order_id, sku, quantity):
        free = self.on_hand(sku) if MUTANT == "ignore-reserved" else self.available(sku)
        if free < quantity:
            raise OutOfStock(sku)
        self._reserved[sku] = self._reserved.get(sku, 0) + quantity
        return order_id

    def release(self, sku, quantity):
        if quantity <= 0 or quantity > self._reserved.get(sku, 0):
            raise ValueError(sku)
        if MUTANT == "release-noop":
            return
        self._reserved[sku] = self._reserved[sku] - quantity
