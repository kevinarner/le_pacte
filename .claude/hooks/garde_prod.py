#!/usr/bin/env python3
"""Hook PreToolUse (Bash) : défense en profondeur contre les écritures en
production Swend hors de la porte scripts/prod_ecrire.sh.

Ce n'est PAS une frontière de sécurité : il analyse le texte des commandes
(et des scripts qu'elles exécutent directement), pas le trafic réseau. Il
arrête les écritures accidentelles et les contournements évidents ; une
commande volontairement obscurcie peut passer. Limites détaillées :
supabase/changements/README.md.

Sortie 0 : la commande continue (la règle « ask » de .claude/settings.json
s'applique ensuite à la porte). Sortie 2 : commande bloquée, raison sur stderr.
"""
import json
import os
import re
import shlex
import subprocess
import sys

PORTE = "prod_ecrire.sh"
GARDE_FOUS = (
    ".claude/hooks/garde_prod.py",
    "scripts/lib/paquet.sh",
    "scripts/paquet_controler.sh",
    "scripts/tests/test_garde_prod.sh",
)
# Seules formes admises pour appeler la porte (celles que couvre la règle « ask »).
PORTE_CANONIQUE = re.compile(
    r"\s*(?:bash\s+)?(?:\./)?scripts/prod_ecrire\.sh(?:\s+[A-Za-z0-9._-]+)*\s*"
)
CIBLES_PROD = re.compile(
    r"api\.supabase\.com|[a-z0-9-]+\.supabase\.co\b|pooler\.supabase\.com", re.I
)
CIBLES_PROJET = re.compile(r"[a-z0-9-]+\.supabase\.co\b|pooler\.supabase\.com", re.I)
OUTILS_RESEAU = re.compile(
    r"\b(curl|wget|http\.client|python[0-9.]*|node|deno|bun|ruby|perl|php|"
    r"nc|ncat|socat|openssl|telnet|psql|pg_dump|pg_restore|fetch|requests|"
    r"urllib[0-9]*|httpx|aiohttp|axios|undici|Invoke-WebRequest|Invoke-RestMethod)\b",
    re.I,
)
# CLI Supabase : commandes qui écrivent sur un projet lié, avec ou sans URL.
CLI_ECRITURE = re.compile(
    r"(^|[\s;&|(`])supabase\s+(db\s+(push|reset)|functions\s+(deploy|delete)|"
    r"secrets\s+(set|unset)|migration\s+(up|repair)|link|config\s+push|projects\s+delete)\b",
    re.I,
)
# Endpoints de l'API Management qui modifient le projet.
CHEMINS_INTERDITS = re.compile(
    r"/v1/projects/[^/\s'\"]+/(functions|secrets|config|api-keys|branches|backups|restore|"
    r"pause|upgrade|network-|custom-hostname|ssl-enforcement|database/migrations|"
    r"database/webhooks|postgrest|pgsodium|readonly|billing|members)",
    re.I,
)
METHODES_INTERDITES = re.compile(
    r"(-X|--request)\s*['\"]?(DELETE|PATCH|PUT)\b|method\s*[=:]\s*['\"](DELETE|PATCH|PUT)", re.I
)
INTERPRETES = {
    "bash", "sh", "zsh", "dash", "ksh", "source", ".", "python", "python3",
    "node", "deno", "bun", "ruby", "perl", "php",
}
PREFIXES = {"env", "exec", "nohup", "timeout", "sudo", "nice", "time", "xargs", "command", "builtin"}


def bloquer(raison):
    sys.stderr.write(
        "BLOQUÉ par le garde-fou production (.claude/hooks/garde_prod.py) : "
        + raison
        + "\nToute écriture en production passe par « scripts/prod_ecrire.sh <ID> <empreinte> » "
        "après « Go <ID> » (CLAUDE.md, supabase/changements/README.md). "
        "Lectures : endpoint …/database/query/read-only uniquement.\n"
    )
    sys.exit(2)


def segments(commande):
    """Commandes simples d'une ligne de commande composée."""
    morceaux = re.split(r"\|\||&&|[;|&\n(){}`]|\$\(", commande)
    return [m.strip() for m in morceaux if m.strip()]


def mots(segment):
    try:
        return shlex.split(segment)
    except ValueError:
        return segment.split()


def premier_mot(ms):
    """Premier mot réellement exécuté : saute VAR=x et les préfixes (env, sudo…)."""
    i = 0
    while i < len(ms):
        m = ms[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", m):
            i += 1
            continue
        if os.path.basename(m) in PREFIXES:
            i += 1
            while i < len(ms) and ms[i].startswith("-"):
                i += 1
            continue
        return i
    return None


def fichiers_executes(commande, cwd):
    """Fichiers locaux exécutés directement (./x.sh, bash x.sh, python3 x.py…)."""
    trouves = []
    for seg in segments(commande):
        ms = mots(seg)
        i = premier_mot(ms)
        if i is None:
            continue
        candidats = []
        if os.path.basename(ms[i]) in INTERPRETES:
            options = [m for m in ms[i + 1:i + 2] if m.startswith("-")]
            if options == ["-n"] and os.path.basename(ms[i]) in {"bash", "sh", "zsh", "dash", "ksh"} \
                    and not (len(ms) > i + 2 and ms[i + 2].startswith("-")):
                continue  # contrôle de syntaxe : rien n'est exécuté
            for m in ms[i + 1:]:
                if m in ("-c", "-e", "-m"):
                    break
                if not m.startswith("-"):
                    candidats.append(m)
                    break
        else:
            candidats.append(ms[i])
        for c in candidats:
            chemin = c if os.path.isabs(c) else os.path.join(cwd, c)
            if os.path.isfile(chemin) and os.path.getsize(chemin) < 2_000_000:
                trouves.append(os.path.realpath(chemin))
    return trouves


def appel_porte_non_canonique(commande):
    """Vrai si la porte est exécutée autrement que sous une forme canonique seule."""
    if PORTE not in commande:
        return False
    if PORTE_CANONIQUE.fullmatch(commande):
        return False
    for seg in segments(commande):
        ms = mots(seg)
        i = premier_mot(ms)
        if i is None:
            continue
        if PORTE in ms[i]:
            return True
        if os.path.basename(ms[i]) in INTERPRETES and PORTE in seg:
            # « bash -n » / « sh -n » lit le script sans l'exécuter (contrôle de syntaxe).
            options = []
            for m in ms[i + 1:]:
                if not m.startswith("-"):
                    break
                options.append(m)
            if options == ["-n"] and os.path.basename(ms[i]) in {"bash", "sh", "zsh", "dash", "ksh"}:
                continue
            return True
    return False


def racine_depot(cwd):
    try:
        return subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except Exception:
        return ""


def analyser(commande, cwd):
    # 1. La porte : seulement sous une forme canonique (que la règle « ask » couvre).
    if appel_porte_non_canonique(commande):
        bloquer("la porte d'écriture doit être appelée seule, sous la forme "
                "« scripts/prod_ecrire.sh <ID> <empreinte> [--rollback] ».")
    if PORTE_CANONIQUE.fullmatch(commande):
        return  # la règle « ask » demande l'approbation humaine

    # 2. Texte analysé : la commande + les scripts locaux qu'elle exécute.
    texte = commande
    racine = racine_depot(cwd)
    racine = os.path.realpath(racine) if racine else ""
    # Le code des garde-fous contient forcément les motifs recherchés : ces
    # fichiers précis ne sont pas analysés (la porte refuse de s'exécuter si
    # l'un d'eux a une modification non commitée).
    garde_fous = {os.path.join(racine, p) for p in GARDE_FOUS} if racine else set()
    for f in fichiers_executes(commande, cwd):
        if f in garde_fous:
            continue
        try:
            with open(f, encoding="utf-8", errors="ignore") as h:
                contenu = h.read()
        except OSError:
            continue
        dossiers_admis = [os.path.join(racine, d) + os.sep for d in ("scripts", os.path.join(".claude", "hooks"))] if racine else []
        if PORTE in contenu and not any(f.startswith(d) for d in dossiers_admis):
            bloquer(f"{f} mentionne la porte d'écriture : seuls les fichiers de scripts/ et .claude/hooks/ le peuvent.")
        texte += "\n" + contenu

    if CLI_ECRITURE.search(texte):
        bloquer("commande d'écriture du CLI Supabase hors de la porte.")

    # 3. Rien qui vise la production, ou aucun outil réseau : rien à faire.
    if not CIBLES_PROD.search(texte) or not OUTILS_RESEAU.search(texte):
        return

    # 4. Ce qui vise la production doit être une lecture …/database/query/read-only.
    if CIBLES_PROJET.search(texte):
        bloquer("appel direct au projet de production (*.supabase.co / pooler) hors de la porte.")
    if CHEMINS_INTERDITS.search(texte):
        bloquer("endpoint de l'API Management qui modifie le projet.")
    if METHODES_INTERDITES.search(texte):
        bloquer("méthode HTTP d'écriture (DELETE / PATCH / PUT).")
    for m in re.finditer(r"database/query", texte):
        if not texte.startswith("/read-only", m.end()):
            bloquer("…/database/query sans /read-only : c'est l'endpoint d'écriture.")
    if "database/query/read-only" not in texte:
        bloquer("requête vers api.supabase.com qui n'est pas une lecture …/database/query/read-only.")


def main():
    try:
        entree = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if entree.get("tool_name") != "Bash":
        sys.exit(0)
    commande = (entree.get("tool_input") or {}).get("command") or ""
    cwd = entree.get("cwd") or os.getcwd()
    try:
        analyser(commande, cwd)
    except SystemExit:
        raise
    except Exception as e:  # en cas de doute sur une commande qui parle de Supabase : bloquer
        if "supabase" in commande.lower() or PORTE in commande:
            bloquer(f"analyse impossible ({type(e).__name__}) d'une commande qui vise Supabase.")
    sys.exit(0)


if __name__ == "__main__":
    main()
