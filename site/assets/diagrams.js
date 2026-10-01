(() => {
  const figures = [...document.querySelectorAll(".diagram")];
  if (!figures.length) return;
  const ui = JSON.parse(document.getElementById("site-ui").textContent);
  for (const figure of figures) {
    const button = figure.querySelector(".diagram-zoom");
    button.addEventListener("click", () => {
      const expanded = figure.classList.toggle("diagram-expanded");
      button.setAttribute("aria-pressed", String(expanded));
      button.textContent = expanded ? ui.diagramFit : ui.diagramZoom;
      const view = figure.querySelector(".diagram-render");
      if (!expanded) view.scrollTo(0, 0);
    });
  }
  let revision = 0;
  let rendering = false;
  let sequence = 0;

  async function refresh() {
    revision++;
    if (rendering) return;
    rendering = true;
    let completed;
    try {
      do {
        completed = revision;
        const style = getComputedStyle(document.documentElement);
        const colour = token => style.getPropertyValue(token).trim();
        const dark = document.documentElement.dataset.theme === "dark";
        try {
          if (!window.mermaid) throw new Error("The self-hosted diagram renderer is unavailable.");
          window.mermaid.initialize({
            startOnLoad: false,
            securityLevel: "strict",
            suppressErrorRendering: true,
            theme: "base",
            fontFamily: '"Source Sans 3", sans-serif',
            themeVariables: {
              darkMode: dark,
              background: colour("--bg"),
              primaryColor: colour("--accent-soft"),
              primaryTextColor: colour("--text"),
              primaryBorderColor: colour("--accent"),
              lineColor: colour("--muted"),
              secondaryColor: colour("--surface"),
              tertiaryColor: colour("--surface-muted"),
              clusterBkg: colour("--surface"),
              clusterBorder: colour("--border-strong"),
              edgeLabelBackground: colour("--surface"),
              actorBkg: colour("--accent-soft"),
              actorBorder: colour("--accent"),
              actorTextColor: colour("--text"),
              actorLineColor: colour("--muted"),
              signalColor: colour("--text"),
              signalTextColor: colour("--text"),
              labelBoxBkgColor: colour("--surface"),
              labelBoxBorderColor: colour("--border"),
              labelTextColor: colour("--text"),
              noteBkgColor: colour("--surface"),
              noteTextColor: colour("--text"),
              noteBorderColor: colour("--accent-border"),
              fontSize: "16px",
            },
            flowchart: { htmlLabels: false, useMaxWidth: false, curve: "basis" },
            sequence: { useMaxWidth: false, mirrorActors: false, wrap: true },
          });
          for (const figure of figures) {
            if (completed !== revision) break;
            const source = figure.querySelector(".diagram-code code").textContent;
            const view = figure.querySelector(".diagram-render");
            const error = figure.querySelector(".diagram-error");
            const details = figure.querySelector(".diagram-source");
            try {
              const { svg } = await window.mermaid.render(`hve-diagram-${++sequence}`, source);
              if (completed !== revision) break;
              view.innerHTML = svg;
              const naturalWidth = view.querySelector("svg").viewBox.baseVal.width;
              if (naturalWidth > 0) view.style.setProperty("--diagram-natural-width", `${naturalWidth}px`);
              view.hidden = false;
              figure.querySelector(".diagram-toolbar").hidden = false;
              error.hidden = true;
              if (!figure.dataset.rendered) {
                details.open = false;
                figure.dataset.rendered = "true";
              }
            } catch (cause) {
              error.hidden = false;
              details.open = true;
              console.error("Could not render documentation diagram.", cause);
            }
          }
        } catch (cause) {
          for (const figure of figures) {
            figure.querySelector(".diagram-error").hidden = false;
            figure.querySelector(".diagram-source").open = true;
          }
          console.error("Documentation diagram renderer is unavailable.", cause);
        }
      } while (completed !== revision);
    } finally {
      rendering = false;
    }
  }

  new MutationObserver(refresh).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  document.fonts.ready.then(refresh);
})();
