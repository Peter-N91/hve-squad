"""Reference ledger for the easy level. LEDGER_MUTANT selects a planted defect."""
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
        if MUTANT == "ignore-reserved":
            return self.on_hand(sku)
        if MUTANT == "double-subtract":
            return self.on_hand(sku) - 2 * self._reserved.get(sku, 0)
        if MUTANT == "unknown-sku-error":
            return self._stock[sku] - self._reserved.get(sku, 0)
        return self.on_hand(sku) - self._reserved.get(sku, 0)

    def reserve(self, order_id, sku, quantity):
        if self.on_hand(sku) - self._reserved.get(sku, 0) < quantity:
            raise OutOfStock(sku)
        self._reserved[sku] = self._reserved.get(sku, 0) + quantity
        return order_id

    def release(self, sku, quantity):
        self._reserved[sku] = max(0, self._reserved.get(sku, 0) - quantity)
