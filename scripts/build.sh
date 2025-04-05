#!/bin/bash
set -e

# Générer des Dockerfiles et construire des images selon l'inventaire
INVENTORY_FILE="inventory.yml"
TEMPLATE_FILE="Dockerfile.template"
REGISTRY="ghcr.io/${GITHUB_REPOSITORY,,}"  # Utilisation de ,, pour convertir en minuscules

# Vérifier si yq est installé
if ! command -v yq &> /dev/null; then
    echo "Installing yq..."
    wget -qO /usr/local/bin/yq [https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64](https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64)
    chmod +x /usr/local/bin/yq
fi

# Lire le nombre d'images dans l'inventaire
IMAGE_COUNT=$(yq e '.images | length' "$INVENTORY_FILE")

for i in $(seq 0 $((IMAGE_COUNT-1))); do
    NAME=$(yq e ".images[$i].name" "$INVENTORY_FILE")
    ITOP_URL=$(yq e ".images[$i].itop_url" "$INVENTORY_FILE")
    PHP_VERSION=$(yq e ".images[$i].php_version" "$INVENTORY_FILE")
    TOOLKIT_URL=$(yq e ".images[$i].toolkit_url" "$INVENTORY_FILE")
    
    echo "Building image: $NAME with PHP $PHP_VERSION"
    
    # Créer le répertoire pour cette image
    mkdir -p "builds/$NAME"
    
    # Générer le Dockerfile à partir du template
    cat "$TEMPLATE_FILE" | \
        sed "s|%%ITOP_URL%%|$ITOP_URL|g" | \
        sed "s|%%PHP_VERSION%%|$PHP_VERSION|g" | \
        sed "s|%%TOOLKIT_URL%%|$TOOLKIT_URL|g" > "builds/$NAME/Dockerfile"
    
    # Construire l'image Docker
    docker build -t "$REGISTRY/$NAME:latest" "builds/$NAME/"
    
    # Tagger avec la version PHP
    docker tag "$REGISTRY/$NAME:latest" "$REGISTRY/$NAME:php$PHP_VERSION"
    
    # Pousser les images
    docker push "$REGISTRY/$NAME:latest"
    docker push "$REGISTRY/$NAME:php$PHP_VERSION"
done