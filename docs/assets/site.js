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

  const agents = {
    '/squad': 'Squad Coordinator',
    '/squad-federation': 'Squad Federation Coordinator',
    '/squad-document': 'Squad Document',
    '/squad-governance-report': 'Squad Governance Report',
    '/squad-learn': 'Squad Learn'
  };
  const commandPattern = /^[ \t]*(\/squad(?:-federation|-document|-governance-report|-learn)?)(?=\s|$)[ \t]?(.*)$/;
  const defaultRequests = french ? {
    '/squad': 'Initialise la squad.',
    '/squad-federation': 'Initialise la f\u00e9d\u00e9ration.',
    '/squad-governance-report': 'G\u00e9n\u00e8re le rapport de gouvernance avec les param\u00e8tres par d\u00e9faut.',
    '/squad-learn': 'Aide-moi \u00e0 proposer un apprentissage partag\u00e9.'
  } : {
    '/squad': 'Initialize the squad.',
    '/squad-federation': 'Initialize the federation.',
    '/squad-governance-report': 'Generate the governance report with default settings.',
    '/squad-learn': 'Help me propose a shared learning.'
  };
  const parseExample = text => {
    const requests = [];
    let current;
    let quoted = false;
    let notes = [];
    for (const line of text.split('\n')) {
      if (!quoted && (!line.trim() || line.trimStart().startsWith('#'))) {
        if (line.trim()) notes.push(line.trimStart().slice(1).trim());
        continue;
      }
      const match = !quoted && line.match(commandPattern);
      if (match) {
        current = { command: match[1], lines: [match[2]], notes };
        requests.push(current);
        notes = [];
      } else if (current && quoted) {
        current.lines.push(line);
      } else {
        return [];
      }
      for (let index = 0; index < line.length; index++) {
        if (line[index] === '\\') { index++; continue; }
        if (line[index] === '"') quoted = !quoted;
      }
    }
    if (quoted || notes.length) return [];
    return requests;
  };

  document.querySelectorAll('pre > code').forEach(code => {
    if (code.closest('[data-host-reference]')) return;
    const requests = parseExample(code.textContent);
    if (!requests.length) return;
    const original = code.parentElement;
    const guide = document.createElement('div');
    guide.className = 'host-guide command-example';
    for (const host of ['cli', 'app', 'vscode']) {
      const panel = document.createElement('section');
      panel.dataset.host = host;
      if (host === 'vscode') {
        const instruction = document.createElement('p');
        instruction.className = 'command-instruction';
        instruction.textContent = french
          ? 'Dans Copilot Chat, choisissez le prompt (pas le skill). Envoyez chaque demande s\u00e9par\u00e9ment.'
          : 'In Copilot Chat, choose the prompt (not the skill). Send each request separately.';
        panel.append(instruction, original.cloneNode(true));
      } else {
        requests.forEach(request => {
          const instruction = document.createElement('p');
          instruction.className = 'command-instruction';
          instruction.textContent = host === 'cli'
            ? (french ? 'Dans Copilot CLI, saisissez /agent et choisissez ' : 'In Copilot CLI, enter /agent and choose ')
            : (french ? 'Dans Copilot App, choisissez ' : 'In Copilot App, select ');
          const agent = document.createElement('strong');
          agent.textContent = agents[request.command];
          instruction.append(agent, french ? '. Envoyez dans sa conversation :' : '. Send in its conversation:');
          if (request.notes.length) {
            const note = document.createElement('p');
            note.className = 'command-note';
            note.textContent = request.notes.join('\n');
            panel.append(note);
          }
          const pre = document.createElement('pre');
          const input = document.createElement('code');
          input.textContent = request.lines.join('\n') || defaultRequests[request.command];
          pre.append(input);
          panel.append(instruction, pre);
        });
      }
      guide.append(panel);
    }
    original.replaceWith(guide);
  });

  const selections = [];
  document.querySelectorAll('.host-guide').forEach((guide, guideIndex) => {
    const panels = [...guide.querySelectorAll(':scope > [data-host]')];
    const tablist = document.createElement('div');
    tablist.className = 'host-tabs';
    tablist.setAttribute('role', 'tablist');
    tablist.setAttribute('aria-label', document.documentElement.lang === 'fr' ? 'Environnement Copilot' : 'Copilot environment');
    const select = (host, focus = false) => {
      panels.forEach((panel, index) => {
        const selected = panel.dataset.host === host;
        panel.hidden = !selected;
        tabs[index].setAttribute('aria-selected', String(selected));
        tabs[index].tabIndex = selected ? 0 : -1;
        if (selected && focus) tabs[index].focus({ preventScroll: true });
      });
    };
    const activate = (host, focus = false, preservePosition = true) => {
      const previousTop = tablist.getBoundingClientRect().top;
      selections.forEach(update => update(host));
      select(host, focus);
      const offset = tablist.getBoundingClientRect().top - previousTop;
      if (preservePosition && offset) window.scrollBy({ top: offset, behavior: 'instant' });
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
    selections.push(select);
    const requested = new URLSearchParams(location.search).get('host') || readPreference('host', 'vscode');
    activate(panels.some(panel => panel.dataset.host === requested) ? requested : 'vscode', false, false);
  });
})();