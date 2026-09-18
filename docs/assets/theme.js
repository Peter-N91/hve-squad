(() => {
  const param = new URLSearchParams(window.location.search).get('scoutTheme');
  let saved;
  try { saved = localStorage.getItem('hve-docs-theme'); } catch {}
  const preferred = param || saved;
  const theme = ['light', 'dark'].includes(preferred)
    ? preferred
    : window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', theme);
})();