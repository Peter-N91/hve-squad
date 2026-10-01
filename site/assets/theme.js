(() => {
  const key = "hve-docs-theme";
  let preference = "system";
  try {
    const stored = localStorage.getItem(key);
    if (["system", "light", "dark"].includes(stored)) preference = stored;
  } catch (error) {
    // Reading remains available when storage is disabled by browser policy.
    console.warn("Theme preference storage is unavailable.", error);
  }
  const queryTheme = new URLSearchParams(window.location.search).get("scoutTheme");
  if (["light", "dark"].includes(queryTheme)) preference = queryTheme;
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  const apply = () => {
    document.documentElement.dataset.theme = preference === "system" ? (media.matches ? "dark" : "light") : preference;
    document.documentElement.dataset.themePreference = preference;
  };
  document.documentElement.classList.add("js");
  apply();
  media.addEventListener("change", apply);
  window.addEventListener("hve-theme-change", event => {
    if (!["system", "light", "dark"].includes(event.detail)) return;
    preference = event.detail;
    apply();
  });
  window.addEventListener("storage", event => {
    if (event.key !== key) return;
    preference = ["light", "dark"].includes(event.newValue) ? event.newValue : "system";
    apply();
    const select = document.querySelector(".theme-select");
    if (select) select.value = preference;
  });
})();
