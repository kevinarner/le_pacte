// Rapport lisible : une ligne PASS/FAIL par vérification, résumé final.
export class Rapport {
  constructor() { this.lignes = []; this.debut = Date.now(); this.scenarios = []; }
  ecrire(l) { this.lignes.push(l); console.log(l); }
  pass(scenario, libelle) { this.ecrire(`PASS — ${libelle}`); this.nPass = (this.nPass || 0) + 1; }
  fail(scenario, libelle, detail) {
    this.ecrire(`FAIL — ${libelle}`);
    for (const d of detail) this.ecrire(`       ${d}`);
    this.nFail = (this.nFail || 0) + 1;
  }
  titre(t) { this.ecrire(`\n== ${t}`); }
  resume() {
    const s = Math.round((Date.now() - this.debut) / 1000);
    const ko = this.scenarios.filter((x) => !x.ok);
    return [
      '', '== Résumé',
      `${this.nPass || 0} PASS`,
      `${this.nFail || 0} FAIL`,
      `scénarios : ${this.scenarios.length - ko.length}/${this.scenarios.length} réussis` +
        (ko.length ? ` — en échec : ${ko.map((x) => x.nom).join(', ')}` : ''),
      `durée totale : ${Math.floor(s / 60)} min ${s % 60} s`,
    ];
  }
}
