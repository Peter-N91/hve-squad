(() => {
  const ui = JSON.parse(document.getElementById("site-ui").textContent);
  const status = document.getElementById("site-status");
  const root = new URL(document.body.dataset.root || "./", window.location.href);
  const theme = document.querySelector(".theme-select");
  theme.value = document.documentElement.dataset.themePreference;
  theme.addEventListener("change", () => {
    window.dispatchEvent(new CustomEvent("hve-theme-change", { detail: theme.value }));
    const url = new URL(window.location.href);
    if (url.searchParams.has("scoutTheme")) {
      if (theme.value === "system") url.searchParams.delete("scoutTheme");
      else url.searchParams.set("scoutTheme", theme.value);
      history.replaceState(null, "", url);
    }
    try {
      localStorage.setItem("hve-docs-theme", theme.value);
    } catch (error) {
      status.textContent = ui.themeStorageError;
      console.warn("Could not save the theme preference.", error);
    }
  });
  document.querySelector(".locale-select").addEventListener("change", event => {
    const destination = new URL(event.target.value, window.location.href);
    destination.search = window.location.search;
    destination.hash = window.location.hash;
    window.location.assign(destination.href);
  });

  const mobileMenu = document.querySelector(".mobile-navigation");
  const mobileSummary = mobileMenu.querySelector("summary");
  const closeMenu = () => { mobileMenu.open = false; };
  mobileMenu.querySelectorAll("a").forEach(link => link.addEventListener("click", closeMenu));
  document.addEventListener("click", event => {
    if (mobileMenu.open && !mobileMenu.contains(event.target)) closeMenu();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && mobileMenu.open) {
      closeMenu();
      mobileSummary.focus();
    }
  });
  window.matchMedia("(min-width: 1001px)").addEventListener("change", event => {
    if (event.matches) closeMenu();
  });
  document.querySelectorAll(".mobile-toc a").forEach(link => {
    link.addEventListener("click", () => { link.closest("details").open = false; });
  });

  // Host-specific examples are materialized before this script; complete their copy UI here.
  document.querySelectorAll(".doc-content pre:not(.diagram-code)").forEach((pre, index) => {
    const code = pre.querySelector("code");
    if (!code) return;
    let wrapper = pre.parentElement;
    if (!wrapper.classList.contains("code-block")) {
      wrapper = document.createElement("div");
      wrapper.className = "code-block";
      pre.before(wrapper);
      wrapper.append(pre);
    }
    if (!pre.id) pre.id = `host-code-sample-${index + 1}`;
    pre.tabIndex = 0;
    if (!pre.hasAttribute("aria-label")) pre.setAttribute("aria-label", ui.code);
    let button = wrapper.querySelector("[data-copy-target]");
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "copy-button js-only";
      button.textContent = ui.copy;
      button.setAttribute("aria-label", `${ui.copy}: ${ui.code} ${index + 1}`);
      button.setAttribute("data-site-ui", "");
      wrapper.prepend(button);
    }
    button.dataset.copyTarget = pre.id;
  });

  document.querySelectorAll("[data-copy-target]").forEach(button => {
    let reset;
    button.addEventListener("click", async () => {
      clearTimeout(reset);
      const block = document.getElementById(button.dataset.copyTarget);
      const code = block.querySelector("code") || block;
      try {
        if (!navigator.clipboard) throw new Error("Clipboard API is unavailable.");
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = ui.copied;
        button.removeAttribute("title");
        status.textContent = ui.copied;
        reset = setTimeout(() => { button.textContent = ui.copy; }, 1800);
      } catch (error) {
        button.textContent = ui.copyFailed;
        button.title = ui.copyError;
        status.textContent = ui.copyError;
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        console.warn("Could not copy code.", error);
      }
    });
  });

  function revealAnchor() {
    if (!window.location.hash) return;
    let id;
    try { id = decodeURIComponent(window.location.hash.slice(1)); }
    catch (error) { console.warn("Invalid documentation anchor.", error); return; }
    const target = document.getElementById(id);
    const panel = target?.closest("[data-host][hidden]");
    if (!panel) return;
    const guide = panel.closest(".host-guide");
    const tab = [...guide.querySelectorAll('[role="tab"]')].find(item => item.getAttribute("aria-controls") === panel.id);
    tab?.click();
    target.scrollIntoView();
  }
  window.addEventListener("hashchange", revealAnchor);
  revealAnchor();

  const tocLinks = [...document.querySelectorAll(".toc-link")];
  const tocTargets = new Set(tocLinks.map(link => link.hash));
  const headings = [...document.querySelectorAll(".doc-content h2[id], .doc-content h3[id]")]
    .filter(heading => tocTargets.has(`#${heading.id}`));
  let scheduled = false;
  function updateCurrentSection() {
    const headerBottom = document.querySelector(".site-header").getBoundingClientRect().bottom + 32;
    let active = headings[0];
    for (const heading of headings) {
      if (heading.getBoundingClientRect().top > headerBottom) break;
      active = heading;
    }
    for (const link of tocLinks) {
      if (active && link.hash === `#${active.id}`) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    }
    scheduled = false;
  }
  window.addEventListener("scroll", () => {
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(updateCurrentSection);
    }
  }, { passive: true });
  updateCurrentSection();

  const dialog = document.querySelector(".search-dialog");
  const searchState = dialog.querySelector(".search-state");
  const searchTrigger = document.querySelector(".search-trigger");
  let searchReady = false;
  let searchLoading;
  let lastFocus;
  async function loadSearch() {
    if (searchReady) return;
    if (searchLoading) return searchLoading;
    searchState.hidden = false;
    searchState.textContent = ui.searchLoading;
    searchLoading = (async () => {
      if (!window.PagefindUI) {
        if (!document.querySelector("[data-search-styles]")) {
          const style = document.createElement("link");
          style.rel = "stylesheet";
          style.href = new URL("pagefind/pagefind-ui.css", root);
          style.dataset.searchStyles = "";
          document.head.prepend(style);
        }
        await new Promise((resolve, reject) => {
          const script = document.createElement("script");
          script.src = new URL("pagefind/pagefind-ui.js", root);
          script.onload = resolve;
          script.onerror = () => { script.remove(); reject(new Error("Pagefind UI could not load.")); };
          document.head.append(script);
        });
      }
      new window.PagefindUI({
        element: "#search-results",
        bundlePath: new URL("pagefind/", root).pathname,
        baseUrl: root.pathname,
        showSubResults: true,
        showImages: false,
        resetStyles: false,
        translations: ui.searchTranslations,
      });
      searchReady = true;
      searchState.hidden = true;
    })();
    try {
      await searchLoading;
    } finally {
      searchLoading = undefined;
    }
  }
  async function openSearch() {
    if (dialog.open) return;
    closeMenu();
    lastFocus = document.activeElement;
    dialog.showModal();
    try {
      await loadSearch();
      if (dialog.open) dialog.querySelector("input")?.focus();
    } catch (error) {
      searchState.hidden = false;
      searchState.textContent = ui.searchError;
      console.error("Documentation search is unavailable.", error);
    }
  }
  searchTrigger.addEventListener("click", openSearch);
  dialog.querySelector(".search-close").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", event => {
    const bounds = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) dialog.close();
  });
  dialog.addEventListener("close", () => lastFocus?.focus());
  document.addEventListener("keydown", event => {
    const target = event.target;
    const typing = target instanceof HTMLElement && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));
    if (!typing && (event.key === "/" || ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k"))) {
      event.preventDefault();
      openSearch();
    }
  });
})();
