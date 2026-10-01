(() => {
  // The shell embeds { host: <host-locales.json> } in #site-ui.
  // Load this deferred script before site.js, which owns code IDs and copy controls.
  const language = document.documentElement.lang;
  const configuration = document.getElementById('site-ui');
  if (!configuration) throw new Error('Host guides require the #site-ui JSON configuration.');
  const locales = JSON.parse(configuration.textContent).host;
  if (!locales || !Object.hasOwn(locales, language)) {
    throw new Error(`Host guides have no locale for html.lang="${language}".`);
  }
  const messages = locales[language];
  const hosts = ['cli', 'app', 'vscode'];
  const commands = ['/squad', '/squad-federation', '/squad-document', '/squad-governance-report', '/squad-learn'];
  const requireMessage = (value, key) => {
    if (typeof value !== 'string' || !value.trim()) {
      throw new Error(`Host guides locale "${language}" is missing "${key}".`);
    }
  };
  requireMessage(messages?.tablistLabel, 'tablistLabel');
  hosts.forEach(host => {
    requireMessage(messages.hostLabels?.[host], `hostLabels.${host}`);
    requireMessage(messages.instructions?.[host], `instructions.${host}`);
    if (host !== 'vscode' && messages.instructions[host].split('{agent}').length !== 2) {
      throw new Error(`Host guides locale "${language}" requires one {agent} in instructions.${host}.`);
    }
  });
  commands.forEach(command => {
    requireMessage(messages.agents?.[command], `agents.${command}`);
    if (command !== '/squad-document') {
      requireMessage(messages.defaultRequests?.[command], `defaultRequests.${command}`);
    }
  });

  const readPreference = () => {
    try { return localStorage.getItem('hve-docs-host') || 'vscode'; }
    catch (error) {
      console.warn('Host preference storage is unavailable; using VS Code.', error);
      return 'vscode';
    }
  };
  const savePreference = host => {
    try { localStorage.setItem('hve-docs-host', host); }
    catch (error) {
      console.warn('Could not save the host preference; it applies only to this page.', error);
    }
  };
  const commandPattern = /^[ \t]*(\/squad(?:-federation|-document|-governance-report|-learn)?)(?=\s|$)[ \t]?(.*)$/;
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
    for (const request of requests) {
      request.input = request.lines.join('\n');
      if (!request.input.trim()) request.input = messages.defaultRequests?.[request.command];
      // Document has no default request; keep the original rather than inventing one.
      if (typeof request.input !== 'string' || !request.input.trim()) return [];
    }
    return requests;
  };

  const createCode = (text, source) => {
    const pre = document.createElement('pre');
    const code = document.createElement('code');
    // Rebuild instead of cloning: generated IDs and copy targets belong to site.js.
    if (source) {
      pre.className = source.parentElement.className;
      code.className = source.className;
    }
    code.textContent = text;
    pre.append(code);
    return pre;
  };

  document.querySelectorAll('pre > code').forEach(code => {
    if (code.closest('[data-host-reference], .host-guide')) return;
    const requests = parseExample(code.textContent);
    if (!requests.length) return;
    const original = code.parentElement;
    const replacement = original.parentElement.classList.contains('code-block')
      ? original.parentElement
      : original;
    const guide = document.createElement('div');
    guide.className = 'host-guide command-example';
    for (const host of hosts) {
      const panel = document.createElement('section');
      panel.dataset.host = host;
      if (host === 'vscode') {
        const instruction = document.createElement('p');
        instruction.className = 'command-instruction';
        instruction.textContent = messages.instructions.vscode;
        panel.append(instruction, createCode(code.textContent, code));
      } else {
        requests.forEach(request => {
          const instruction = document.createElement('p');
          instruction.className = 'command-instruction';
          const [before, after] = messages.instructions[host].split('{agent}');
          const agent = document.createElement('strong');
          agent.textContent = messages.agents[request.command];
          instruction.append(before, agent, after);
          if (request.notes.length) {
            const note = document.createElement('p');
            note.className = 'command-note';
            note.textContent = request.notes.join('\n');
            panel.append(note);
          }
          panel.append(instruction, createCode(request.input));
        });
      }
      guide.append(panel);
    }
    replacement.replaceWith(guide);
  });

  const ids = new Set([...document.querySelectorAll('[id]')].map(element => element.id));
  const uniqueId = base => {
    let id = base;
    for (let suffix = 1; ids.has(id); suffix++) id = `${base}-${suffix}`;
    ids.add(id);
    return id;
  };
  const selections = [];
  const requested = new URLSearchParams(location.search).get('host') || readPreference();
  const initialHost = hosts.includes(requested) ? requested : 'vscode';
  const persist = host => {
    savePreference(host);
    const url = new URL(location.href);
    if (url.searchParams.has('host')) {
      url.searchParams.set('host', host);
      history.replaceState(history.state, '', url);
    }
  };
  document.querySelectorAll('.host-guide').forEach((guide, guideIndex) => {
    const panels = [...guide.querySelectorAll(':scope > [data-host]')];
    if (panels.length !== hosts.length || !hosts.every(host => panels.filter(panel => panel.dataset.host === host).length === 1)) {
      console.warn('Host guide has incomplete panels; leaving its content visible.', guide);
      return;
    }
    const tablist = document.createElement('div');
    tablist.className = 'host-tabs';
    tablist.setAttribute('role', 'tablist');
    tablist.setAttribute('aria-label', messages.tablistLabel);
    const select = (host, focus = false) => {
      panels.forEach((panel, index) => {
        const selected = panel.dataset.host === host;
        panel.hidden = !selected;
        tabs[index].setAttribute('aria-selected', String(selected));
        tabs[index].tabIndex = selected ? 0 : -1;
        if (selected && focus) tabs[index].focus({ preventScroll: true });
      });
    };
    const activate = (host, focus = false) => {
      const previousTop = tablist.getBoundingClientRect().top;
      selections.forEach(update => update(host));
      if (focus) select(host, true);
      const offset = tablist.getBoundingClientRect().top - previousTop;
      if (offset) window.scrollBy({ top: offset, behavior: 'instant' });
      persist(host);
    };
    const tabs = panels.map((panel, index) => {
      const tab = document.createElement('button');
      tab.type = 'button';
      tab.id = uniqueId(`host-tab-${guideIndex}-${panel.dataset.host}`);
      panel.id ||= uniqueId(`host-panel-${guideIndex}-${panel.dataset.host}`);
      panel.setAttribute('role', 'tabpanel');
      panel.setAttribute('aria-labelledby', tab.id);
      panel.tabIndex = 0;
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-controls', panel.id);
      tab.textContent = messages.hostLabels[panel.dataset.host];
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
    select(initialHost);
  });
  if (selections.length) persist(initialHost);
  document.dispatchEvent(new CustomEvent('hve-content-ready'));
})();
