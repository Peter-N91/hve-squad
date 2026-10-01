const french = {
  usage: [
    [
      ['Issue labeled squad/auto', 'Issue portant l’étiquette squad/auto'],
      ['Write collaborator?', 'Collaborateur autorisé à écrire ?'],
      ['Ignored, comment left on issue', 'Ignorée, commentaire ajouté à l’issue'],
      ['Copilot CLI runs Squad Coordinator with mode=autopilot', 'Copilot CLI exécute Squad Coordinator avec mode=autopilot'],
      ['Profile inferred from the issue (fallback: default)', 'Profil déduit de l’issue (repli : default)'],
      ['Research, Plan, Implement, Review', 'Recherche, planification, implémentation, revue'],
      ['Impactful or Risk Gate?', 'Validation d’action à impact ou de risque ?'],
      ['Approve from phone via github-issue', 'Approuver depuis un téléphone via github-issue'],
      ['Open DRAFT pull request that closes the issue', 'Ouvrir une pull request BROUILLON qui clôt l’issue'],
      ['You review and merge', 'Vous examinez et fusionnez'],
      ['-- no -->', '-- non -->'],
      ['-- yes -->', '-- oui -->'],
    ],
    [
      ['Gate reached (council / impactful / final)', 'Validation requise (conseil / impact / finale)'],
      ['Short chat / notification message', 'Message bref dans la conversation / notification'],
      ['Decision Ref deep link', 'Lien direct Decision Ref'],
      ['decisions.md#council-verdict-DATE-TOPIC — verdict, findings, conditions', 'decisions.md#council-verdict-DATE-TOPIC — verdict, constats, conditions'],
      ['state.json + history — run state and audit trail', 'state.json + history — état de l’exécution et piste d’audit'],
      ['notifications.md — append-only ping log', 'notifications.md — journal de notifications en ajout uniquement'],
      ['-. fallback .->', '-. repli .->'],
    ],
  ],
  maintaining: [[
    ['Cron 06:00 UTC', 'Planification 06:00 UTC'],
    ['pinned SHA vs hve-core main', 'SHA épinglé comparé à main de hve-core'],
    ['Does squad-src still reference<br/>a removed or un-dispatched agent?', 'squad-src référence-t-il encore<br/>un agent supprimé ou non invocable ?'],
    ['no (mechanical)', 'non (mécanique)'],
    ['Bump pin + assemble release<br/>from .changes fragments + push', 'Mettre à jour la version épinglée + assembler la version<br/>à partir des fragments .changes + pousser'],
    ['tag + GitHub Release', 'tag + version GitHub'],
    ['yes (breaking)', 'oui (rupture)'],
    ['Open issue labeled squad/auto<br/>body = full adaptation brief', 'Ouvrir une issue étiquetée squad/auto<br/>corps = cahier des charges complet de l’adaptation'],
    ['fires on the label', 'se déclenche sur l’étiquette'],
    ['Sub-squad issue-N<br/>autopilot, unattended', 'Sous-squad issue-N<br/>autopilot, sans intervention'],
    ['DRAFT PR that closes the issue', 'PR BROUILLON qui clôt l’issue'],
    ['Label the PR squad/review?', 'Étiqueter la PR squad/review ?'],
    ['squad-watch.yml again<br/>sub-squad pr-N, tester role', 'squad-watch.yml à nouveau<br/>sous-squad pr-N, rôle tester'],
    ['Review comments on the PR', 'Commentaires de revue sur la PR'],
    ['Human merges', 'Fusion par une personne'],
    ['-- yes -->', '-- oui -->'],
    ['-- no -->', '-- non -->'],
  ]],
};

export function localizeDiagram(source, language, page, index = 0) {
  if (language === "en") return source;
  const replacements = language === "fr" ? french[page]?.[index] : null;
  if (!replacements) throw new Error(`Missing diagram translation: ${language}/${page}/${index}`);
  let result = source;
  for (const [from, to] of replacements) {
    if (!result.includes(from)) throw new Error(`Diagram label changed in ${page}/${index}: ${from}`);
    result = result.replaceAll(from, to);
  }
  return result;
}
