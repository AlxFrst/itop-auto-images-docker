#!/bin/bash
set -e

# Fichiers source et destination
INVENTORY_FILE="inventory.yml"
README_FILE="README.MD"

echo "Mise à jour du README avec les versions disponibles..."

# Vérifier si yq est installé
if ! command -v yq &> /dev/null; then
    echo "yq n'est pas installé. Tentative d'installation..."
    
    # Vérifier si homebrew est installé (macOS)
    if command -v brew &> /dev/null; then
        echo "Installation de yq via Homebrew..."
        brew install yq
    else
        # Tentative d'installation manuelle avec curl (pour macOS)
        echo "Installation manuelle de yq..."
        sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64" -o /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi
fi

# Lire le nombre d'images dans l'inventaire
IMAGE_COUNT=$(yq e '.images | length' "$INVENTORY_FILE")

# Créer une nouvelle table des versions disponibles
VERSION_TABLE="## 📋 Available Versions\n\nThe following versions are automatically built and available in the GitHub Container Registry:\n\n| Version | PHP Version |\n|---------|-------------|\n"

for i in $(seq 0 $((IMAGE_COUNT-1))); do
    NAME=$(yq e ".images[$i].name" "$INVENTORY_FILE")
    PHP_VERSION=$(yq e ".images[$i].php_version" "$INVENTORY_FILE")
    VERSION_TABLE+="| $NAME | $PHP_VERSION |\n"
done

# Mettre à jour le README
# Sauvegarder le README actuel
cp "$README_FILE" "${README_FILE}.bak"

# Remplacer la section des versions dans le README
awk -v versions="$VERSION_TABLE" '
BEGIN { in_versions = 0; printed = 0; }
/^## 📋 Available Versions/ { in_versions = 1; print versions; printed = 1; next; }
/^## 🔧 How to use/ { in_versions = 0; }
!in_versions { print; }
' "${README_FILE}.bak" > "$README_FILE"

echo "README mis à jour avec succès!"

# Supprimer la sauvegarde
rm "${README_FILE}.bak"
