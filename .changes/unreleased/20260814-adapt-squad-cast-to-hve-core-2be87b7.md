---
bump: minor
type: Changed
---

- **HVE Core retired its entire dispatchable data-science agent cast** (`DS Gen Data Spec`, `DS Gen Jupyter Notebook`, `DS Gen Streamlit Dashboard`, `DS Test Streamlit Dashboard`) and its `Evaluation Dataset Creator`, replacing them with reference-pack skills and a `disable-model-invocation: true` orchestrator (`Data Workstream Coach`) that `runSubagent` cannot reach. A new squad-owned charter, `Squad Data Scientist` (`squad-src/.github/agents/squad/squad-data-scientist.agent.md`), now serves the `data-scientist` role's Primary, running the `ds-catalog`, `ds-analysis-authoring`, `ds-dataops`, `ds-feasibility`, and `ml-experimentation` skills, and reaches the existing Power BI/Fabric skills explicitly instead of ambiently. `Squad Prompt Engineer` now also runs `ds-evaluation-design` for the `prompt-engineer` role's eval-dataset alternate, replacing the retired `Evaluation Dataset Creator`. `apm.yml` moves to hve-core@2be87b7.
