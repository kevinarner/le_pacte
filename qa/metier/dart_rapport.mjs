// Convertit la sortie `flutter test --reporter json` en lignes PASS/FAIL.
import readline from 'node:readline';
const noms = new Map();
const erreurs = new Map();
const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (ligne) => {
  let e; try { e = JSON.parse(ligne); } catch { return; }
  if (e.type === 'testStart') noms.set(e.test.id, e.test.name);
  if (e.type === 'error') erreurs.set(e.testID, (e.error || '').split('\n')[0]);
  if (e.type === 'testDone' && !e.hidden) {
    const nom = noms.get(e.testID);
    if (!nom || nom.startsWith('loading ')) return;
    if (e.result === 'success') console.log(`PASS — [dart] ${nom}`);
    else console.log(`FAIL — [dart] ${nom} — ${erreurs.get(e.testID) || e.result}`);
  }
});
