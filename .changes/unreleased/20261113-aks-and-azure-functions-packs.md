---
bump: patch
type: Added
---

- **Opt-in `aks` and `azure-functions` packs (`pack=aks`, `pack=azure-functions`).** Reuses existing local charters with seven pinned official AKS directory skills from `microsoft/azure-skills` (`azure-architect`, `developer`, `modernizer`, `azure-diagnose`, `cost-manager`) and ten pinned official Azure Functions directory skills from `Azure/azure-functions-skills` (`developer`, `deployer`, `tester`, `azure-diagnose`, `modernizer`) through the shared approval, selected-subset installation, reload, host-availability, and Watch Mode lifecycle.
- **Separately approved Azure Functions preview jobs, blocklist updates, and setup guides.** Gates `azure-functions-update` and `azure-functions-hosted-skills` behind explicit preview approval, blocklists archived `Azure/AKS-Skills` (`aks`) and multi-role `platform-sre-kubernetes`, verifies packaged support files, and adds English and French `#aks-setup` and `#azure-functions-setup` guides while leaving other packs and unpacked squads unchanged.
