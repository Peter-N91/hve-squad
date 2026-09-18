(() => {
  const readPreference = (key, fallback) => {
    try { return localStorage.getItem(`hve-docs-${key}`) || fallback; }
    catch { return fallback; }
  };
  const savePreference = (key, value) => {
    try { localStorage.setItem(`hve-docs-${key}`, value); }
    catch {}
  };

  const french = document.documentElement.lang === 'fr';
  const pageName = location.pathname.split('/').pop() || 'index.html';
  const nav = document.querySelector('.nav-inner');
  const links = document.querySelector('.nav-links');
  const main = document.querySelector('main');
  if (nav && links && main) {
    main.id ||= 'main';
    main.tabIndex = -1;
    const skip = document.createElement('a');
    skip.href = `#${main.id}`;
    skip.className = 'skip-link';
    skip.textContent = french ? 'Aller au contenu' : 'Skip to content';
    document.body.prepend(skip);
    links.id = 'docs-navigation';
    document.querySelector('.nav').setAttribute('aria-label', french ? 'Navigation principale' : 'Main navigation');
    links.querySelector('.active')?.setAttribute('aria-current', 'page');

    const actions = document.createElement('div');
    actions.className = 'header-actions';
    const menu = document.createElement('button');
    menu.type = 'button';
    menu.className = 'menu-toggle';
    menu.textContent = 'Menu';
    menu.setAttribute('aria-controls', links.id);
    menu.setAttribute('aria-expanded', 'false');
    menu.addEventListener('click', () => {
      const open = menu.getAttribute('aria-expanded') !== 'true';
      menu.setAttribute('aria-expanded', String(open));
      links.classList.toggle('open', open);
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && links.classList.contains('open')) {
        links.classList.remove('open');
        menu.setAttribute('aria-expanded', 'false');
        menu.focus();
      }
    });
    const languageLabel = document.createElement('label');
    languageLabel.className = 'language-control';
    languageLabel.textContent = french ? 'Langue' : 'Language';
    const language = document.createElement('select');
    language.add(new Option('English', 'en'));
    language.add(new Option('Fran\u00e7ais', 'fr'));
    language.value = french ? 'fr' : 'en';
    language.addEventListener('change', () => {
      if (language.value === document.documentElement.lang) return;
      const target = new URL(`${french ? '../' : 'fr/'}${pageName}`, location.href);
      target.search = location.search;
      target.hash = location.hash;
      location.assign(target.href);
    });
    languageLabel.append(language);
    const themeLabel = document.createElement('label');
    themeLabel.className = 'theme-control';
    const theme = document.createElement('input');
    theme.type = 'checkbox';
    theme.checked = document.documentElement.dataset.theme === 'dark';
    theme.addEventListener('change', () => {
      const value = theme.checked ? 'dark' : 'light';
      document.documentElement.dataset.theme = value;
      savePreference('theme', value);
      const url = new URL(location.href);
      if (url.searchParams.has('scoutTheme')) {
        url.searchParams.set('scoutTheme', value);
        history.replaceState(null, '', url);
      }
    });
    themeLabel.append(theme, french ? 'Sombre' : 'Dark');
    actions.append(menu, languageLabel, themeLabel);
    nav.append(actions);

    document.body.classList.add('docs-ready');
  }

  if (!document.querySelector('.host-guide')) {
    const container = document.querySelector('.hero .container');
    if (container) {
      const guide = document.createElement('div');
      guide.className = 'host-guide host-summary';
      const descriptions = french ? {
        cli: 'Dans Copilot CLI, saisissez /agent et choisissez Squad Coordinator. Envoyez votre demande dans sa conversation, sans le pr\u00e9fixe /squad.',
        app: 'Dans Copilot App, ouvrez votre projet et choisissez Squad Coordinator dans le s\u00e9lecteur d\u2019agents. Envoyez votre demande, sans le pr\u00e9fixe /squad.',
        vscode: 'Dans Copilot Chat, choisissez le prompt /squad, et non le skill du m\u00eame nom. Les exemples de r\u00e9f\u00e9rence utilisent cette syntaxe.'
      } : {
        cli: 'In Copilot CLI, enter /agent and choose Squad Coordinator. Send your request in its conversation, without the /squad prefix.',
        app: 'In Copilot App, open your project and choose Squad Coordinator in the agent picker. Send your request without the /squad prefix.',
        vscode: 'In Copilot Chat, choose the /squad prompt, not the similarly named skill. Reference examples use this syntax.'
      };
      for (const host of ['cli', 'app', 'vscode']) {
        const panel = document.createElement('section');
        panel.dataset.host = host;
        const paragraph = document.createElement('p');
        paragraph.textContent = descriptions[host];
        const setup = document.createElement('a');
        setup.href = `getting-started.html?host=${host}`;
        setup.textContent = french ? 'Installation et premi\u00e8re demande' : 'Installation and first request';
        panel.append(paragraph, setup);
        guide.append(panel);
      }
      container.append(guide);
    }
  }

  document.querySelectorAll('.host-guide').forEach((guide, guideIndex) => {
    const panels = [...guide.querySelectorAll(':scope > [data-host]')];
    const tablist = document.createElement('div');
    tablist.className = 'host-tabs';
    tablist.setAttribute('role', 'tablist');
    tablist.setAttribute('aria-label', document.documentElement.lang === 'fr' ? 'Environnement Copilot' : 'Copilot environment');
    const activate = (host, focus = false) => {
      panels.forEach((panel, index) => {
        const selected = panel.dataset.host === host;
        panel.hidden = !selected;
        tabs[index].setAttribute('aria-selected', String(selected));
        tabs[index].tabIndex = selected ? 0 : -1;
        if (selected && focus) tabs[index].focus();
      });
      savePreference('host', host);
      const url = new URL(location.href);
      if (url.searchParams.has('host')) {
        url.searchParams.set('host', host);
        history.replaceState(null, '', url);
      }
    };
    const tabs = panels.map((panel, index) => {
      const tab = document.createElement('button');
      tab.type = 'button';
      tab.id = `host-tab-${guideIndex}-${panel.dataset.host}`;
      panel.id ||= `host-panel-${guideIndex}-${panel.dataset.host}`;
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', tab.id);
      panel.tabIndex = 0;
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panel.id);
      tab.textContent = { cli: 'Copilot CLI', app: 'Copilot App', vscode: 'VS Code' }[panel.dataset.host];
      tab.addEventListener('click', () => activate(panel.dataset.host));
      tab.addEventListener('keydown', event => {
        let target;
        if (event.key === 'ArrowRight') target = (index + 1) % panels.length;
        if (event.key === 'ArrowLeft') target = (index + panels.length - 1) % panels.length;
        if (event.key === 'Home') target = 0;
        if (event.key === 'End') target = panels.length - 1;
        if (target !== undefined) {
          event.preventDefault();
          activate(panels[target].dataset.host, true);
        }
      });
      tablist.append(tab);
      return tab;
    });
    guide.prepend(tablist);
    const requested = new URLSearchParams(location.search).get('host') || readPreference('host', 'vscode');
    activate(panels.some(panel => panel.dataset.host === requested) ? requested : 'vscode');
  });
})();