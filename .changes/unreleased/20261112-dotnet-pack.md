---
bump: patch
type: Added
---

- **Opt-in `.NET` pack (`pack=dotnet`).** Reuses `modernizer`, `tester`, `performance`, and `developer` with twenty pinned official `dotnet/skills` directory entries across upgrades, NuGet Central Package Management, VSTest-to-MTP migration, `.NET` test and public-API review, hot-path performance and BenchmarkDotNet/trace planning, EF Core, ASP.NET Core Web API, Blazor, C# refactoring, and MSBuild authoring through the shared approval, installation, reload, host-availability, and Watch Mode lifecycle.
- **Separately approved `.NET` preview jobs and setup guides.** Gates `migrate-dotnet10-to-dotnet11` and `exp-mock-usage-analysis` behind explicit preview approval, verifies packaged support files, blocklists all sixteen upstream `.agent.md` workers/orchestrators, and adds English and French `#dotnet-setup` guides while leaving other packs and unpacked squads unchanged.
