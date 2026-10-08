---
bump: patch
type: Changed
---

- Expose stable coordinator-owned progress through a native task list when the host supports one and an in-chat plan on every host. Currently Squad is doing a lot of work behind the scenes, following RPI, but for the user is not easy to track what's doing and in which step it is. Even though the current step has a title, users may not know how many steps the agent needs to go through.VSCode provides a tool to show the steps: the "todos" tool, it seems a simple change to provide some better feedback to the user. Small additions to the squad-coordinator.agent, squad-prompt, operating-procedure and squad-behavior-contract.
