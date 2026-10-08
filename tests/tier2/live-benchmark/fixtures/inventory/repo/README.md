# Ledger

A deliberately small service used as a Tier 1 fixture. Cost and runtime scale with
fixture size, so this stays at three files and one obvious gap.

## What it does

Tracks stock levels for a warehouse. `reserve` holds stock for an order; `release`
returns it.

## Known gap

`reserve` does not check for concurrent callers, so two orders can reserve the same
unit. There is no persistence layer yet.
