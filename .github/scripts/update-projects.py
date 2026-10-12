#!/usr/bin/env python3
"""Generate the profile's public project index from GitHub's public user API.

Only publicly visible repositories belonging to OWNER are considered.
No private-repository API endpoint is queried and no external packages are used.
"""

from __future__ import annotations

import html
import json
import os
import re
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

OWNER = "loic31000"
DESTINATION = Path(__file__).resolve().parents[2] / "PROJECTS.md"

GROUPS = {
    "Sécurité, réseau & investigations": {
        "CyberHub",
        "security-ci",
        "bgp-hijack-orange-2026",
        "bgp-monitor-orange-hijack",
    },
    "IA locale & ingénierie": {
        "local-agents",
        "codex-engineering-playbook-fr",
        "codex-playbook-lab",
    },
    "Open source, outils & observabilité": {
        "github-traffic-observer",
        "github-readme-stats",
        "FileRenamer",
        "fetch-meteo-project",
    },
    "Applications web & full-stack": {
        "AniRecap",
        "phase3-symfony-facturation",
        "phase3-symfony-tasklist-reloaded",
        "module5-react-threadfront",
        "PokedexSPA",
        "symfony_pokedex",
        "Mini-Insta",
        "project-allocine",
        "mvc_project",
        "tp-pokedex",
    },
    "Jeux & expériences créatives": {
        "Earth-Defender-Project",
        "earth_defender",
        "Mastermind-Pokemon",
        "twelve-projet",
        "Projet-Quiz",
        "maquette-supersmash",
    },
    "Formation & exercices": {
        "exercises-CSS",
        "exercises_php",
        "Exercices-TypeScript-Classes-Constructeurs-et-Encapsulation",
        "tasklist-template",
    },
}


def fetch_public_repositories() -> list[dict]:
    token = os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN")
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "loic31000-public-projects-index",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = "Bearer " + token

    repositories = []
    page = 1
    while True:
        # /users/.../repos lists the owner's PUBLIC repositories, unlike /user/repos.
        url = (
            "https://api.github.com/users/"
            + OWNER
            + "/repos?per_page=100&type=owner&sort=pushed&direction=desc&page="
            + str(page)
        )
        try:
            with urlopen(Request(url, headers=headers), timeout=25) as response:
                batch = json.load(response)
        except (HTTPError, URLError, TimeoutError) as exc:
            raise RuntimeError("Impossible de récupérer les dépôts GitHub publics") from exc

        if not isinstance(batch, list):
            raise RuntimeError("Réponse GitHub inattendue : tableau de dépôts attendu")

        repositories.extend(
            repo
            for repo in batch
            if isinstance(repo, dict)
            and repo.get("private") is False
            and repo.get("owner", {}).get("login", "").lower() == OWNER.lower()
            and repo.get("name") != OWNER  # Ignore the profile README repository.
        )
        if len(batch) < 100:
            break
        page += 1

    if not repositories:
        raise RuntimeError("Aucun dépôt public reçu : index non réécrit par sécurité")
    return repositories


def escape_inline(value: str) -> str:
    plain = re.sub(r"\s+", " ", value.strip())
    return html.escape(plain.replace(chr(0x2014), "-"), quote=False).replace("|", r"\|")


def get_section(repo_name: str) -> str:
    for label, names in GROUPS.items():
        if repo_name in names:
            return label
    return "Autres dépôts publics"


def render_catalog(repositories: list[dict]) -> str:
    sections: dict[str, list[dict]] = {}
    for repo in repositories:
        section = get_section(repo["name"])
        sections.setdefault(section, []).append(repo)

    lines = [
        '<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0D1117,40:001a00,100:00FF41&height=110&section=header&animation=fadeIn" width="100%"/>',
        "",
        "# Tous les projets publics",
        "",
        "> <code>loic@github:~$ find ./projects -type repo</code>",
        "",
        "Cet index regroupe **tous les dépôts publics** du compte, y compris les",
        "exercices et expérimentations. Les projets mis en avant sur le",
        "**[profil principal](./README.md)** sont volontairement sélectionnés.",
        "",
        "**Source :** API GitHub publique · **Actualisation :** chaque lundi via GitHub Actions.",
        "Les dépôts privés ne sont **jamais** lus ni publiés dans cet index.",
        "",
        "**" + str(len(repositories)) + " dépôts publics** (hors dépôt de profil) · "
        "[Voir le tri GitHub par activité](https://github.com/" + OWNER + "?tab=repositories)",
        "",
        "<hr>",
        "",
    ]

    order = [*GROUPS, "Autres dépôts publics"]
    for section in order:
        entries = sections.get(section, [])
        if not entries:
            continue

        lines += ["## " + section + " (" + str(len(entries)) + ")", ""]
        entries.sort(key=lambda repo: (repo.get("pushed_at") or "", repo["name"].lower()), reverse=True)
        for repo in entries:
            name = repo["name"]
            link = "https://github.com/" + OWNER + "/" + name
            description = escape_inline(repo.get("description") or "Code et documentation à découvrir sur le dépôt.")
            description = description[:220].rstrip()
            language = escape_inline(repo.get("language") or "stack non précisée")
            pushed = str(repo.get("pushed_at") or "")[:10] or "date non disponible"
            flags = []
            if repo.get("fork"):
                flags.append("fork")
            if repo.get("archived"):
                flags.append("archivé")
            meta = " · ".join([language, "dernier push " + pushed, *flags])
            lines.append("- **[" + escape_inline(name) + "](" + link + ")** - " + description + "  ")
            lines.append("  <sub>" + escape_inline(meta) + "</sub>")
        lines.append("")

    lines += [
        "<hr>",
        "",
        "<sub>Index généré par <code>.github/scripts/update-projects.py</code>. "
        "Ne pas modifier manuellement : la prochaine exécution écraserait les changements.</sub>",
        "",
        '<img src="https://capsule-render.vercel.app/api?type=waving&color=0:00FF41,60:001a00,100:0D1117&height=70&section=footer" width="100%"/>',
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    repositories = fetch_public_repositories()
    content = render_catalog(repositories)
    if DESTINATION.exists() and DESTINATION.read_text(encoding="utf-8") == content:
        print("Catalogue déjà à jour (" + str(len(repositories)) + " dépôts).")
        return
    DESTINATION.write_text(content, encoding="utf-8")
    print("Catalogue généré (" + str(len(repositories)) + " dépôts).")


if __name__ == "__main__":
    main()
