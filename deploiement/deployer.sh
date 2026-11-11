#!/bin/sh
# Envoie le site sur bornes.ivoire.tech.
#
#   sh deploiement/deployer.sh            # montre ce qui serait fait, n'envoie rien
#   sh deploiement/deployer.sh --envoyer  # pour de vrai
#
# L'essai à blanc d'abord, toujours : `--delete` efface sur le serveur ce qui n'existe plus
# ici, et l'on veut avoir lu la liste avant qu'elle s'applique.
#
# Le même script sert au poste et à l'intégration continue ; seul HOTE change.
set -eu

HOTE="${HOTE:-ivoire}"                            # alias défini dans ~/.ssh/config
CIBLE="${CIBLE:-/var/www/bornes.ivoire.tech}"
RACINE=$(cd "$(dirname "$0")/.." && pwd)

# `.well-known` est EXCLU de la suppression : c'est là que certbot dépose ses validations.
# Sans cette exclusion, un déploiement lancé pendant un renouvellement le ferait échouer.
EXCLUSIONS="--exclude=.git --exclude=.gitignore --exclude=.github --exclude=deploiement
            --exclude=README.md --exclude=.DS_Store --exclude=.well-known"

# --- Vérification avant envoi -------------------------------------------------
# Une image référencée mais absente ne casse rien au déploiement : elle casse la page,
# en silence, chez le visiteur. On refuse d'envoyer plutôt que de le découvrir après.
manquantes=0
for ressource in $(grep -oE 'src="img/[^"]+"' "$RACINE/index.html" | sed 's/^src="//; s/"$//' | sort -u); do
    if [ ! -f "$RACINE/$ressource" ]; then
        echo "MANQUANT : $ressource est référencé dans index.html mais absent du dépôt" >&2
        manquantes=$((manquantes + 1))
    fi
done
if [ "$manquantes" -gt 0 ]; then
    echo "Rien n'a été envoyé : $manquantes ressource(s) manquante(s)." >&2
    exit 1
fi
echo "Ressources référencées : toutes présentes."

MODE="--dry-run"
[ "${1:-}" = "--envoyer" ] && MODE=""

# shellcheck disable=SC2086
# Pas de `-p` : sans cela rsync recopie les permissions du poste, et le répertoire arrive
# en 700 — Apache, qui tourne en www-data, répond alors 403 sur un dossier pourtant rempli.
#
# Et pas de `--chmod` non plus : macOS livre openrsync, qui ne le connaît pas. Les modes
# sont donc imposés après coup, ce qui marche quelle que soit la version de rsync du poste.
rsync -rltz --delete $MODE $EXCLUSIONS --itemize-changes \
  "$RACINE"/ "$HOTE:$CIBLE/"

if [ -n "$MODE" ]; then
    echo
    echo "Essai à blanc. Relancer avec --envoyer pour appliquer."
    exit 0
fi

ssh "$HOTE" "find '$CIBLE' -type d -exec chmod 755 {} + && find '$CIBLE' -type f -exec chmod 644 {} +"

echo
echo "Envoyé, permissions normalisées."
echo "Vérification :"
code=$(curl -s -o /dev/null -w '%{http_code}' https://bornes.ivoire.tech/) || code=000
echo "  https://bornes.ivoire.tech/ → $code"
[ "$code" = "200" ] || { echo "  (200 attendu — voir le journal du serveur)" >&2; exit 1; }
