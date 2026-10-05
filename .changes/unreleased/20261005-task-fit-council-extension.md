---
bump: minor
type: Changed
---

- **Task-fit council** — The pre-implementation council no longer requires a fixed four-role quorum. Each lens the work touches (architecture, security, cost, product-fit, RAI) maps to one role, and only those roles are dispatched, so a council can be two roles, all five, or `rai` alone. The verdict lists every lens left out under `Council Members Not Proposed` with its reason. The automatic trigger is unchanged: two or more council-member domains, or any responsible-AI concern.

- **Council extension** — When the work needs a council role the roster does not carry, the coordinator offers it as a council extension, the same way it offers `intake-validator` and the opt-in roles. At Init the offer rides in the existing profile confirmation when the opening request already signals a council, for profiles, packs, custom rosters, and federation sub-squads alike. In interactive mode the council's `confirm` step proposes the task-fit council. Autopilot and autonomous runs select from the roster without asking and stop only when a needed role is missing. Watch Mode reports the role to add and never adds it.

- **Council waiver** — Declining the council records a `## Council Waiver` decision that satisfies the Implementation Gate for the topic. It never clears a Risk Gate or an Impactful-Action Gate. The council routing row is now seeded on every roster so a council request always reaches the offer.
