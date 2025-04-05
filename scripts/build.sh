#!/bin/bash
set -e

# Générer des Dockerfiles et construire des images selon l'inventaire
INVENTORY_FILE="inventory.yml"
TEMPLATE_FILE="Dockerfile.template"
REGISTRY="ghcr.io/${GITHUB_REPOSITORY,,}"  # Utilisation de ,, pour convertir en minuscules
CACHE_DIR=".dockerfile_cache"
KNOWN_IMAGES_FILE=".known_images"

# Vérifier si yq est installé
if ! command -v yq &> /dev/null; then
    echo "Installing yq..."
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod +x /usr/local/bin/yq
fi

# Créer le répertoire de cache s'il n'existe pas
mkdir -p "$CACHE_DIR"

# Lire le nombre d'images dans l'inventaire
IMAGE_COUNT=$(yq e '.images | length' "$INVENTORY_FILE")

# Collecter les noms d'images actuelles pour détecter les suppressions
CURRENT_IMAGES=()

for i in $(seq 0 $((IMAGE_COUNT-1))); do
    NAME=$(yq e ".images[$i].name" "$INVENTORY_FILE")
    ITOP_URL=$(yq e ".images[$i].itop_url" "$INVENTORY_FILE")
    PHP_VERSION=$(yq e ".images[$i].php_version" "$INVENTORY_FILE")
    TOOLKIT_URL=$(yq e ".images[$i].toolkit_url" "$INVENTORY_FILE")
    
    CURRENT_IMAGES+=("$NAME")
    
    echo "Processing image: $NAME with PHP $PHP_VERSION"
    
    # Créer le répertoire pour cette image
    mkdir -p "builds/$NAME"
    
    # Générer le Dockerfile à partir du template
    DOCKERFILE_CONTENT=$(cat "$TEMPLATE_FILE" | \
        sed "s|%%ITOP_URL%%|$ITOP_URL|g" | \
        sed "s|%%PHP_VERSION%%|$PHP_VERSION|g" | \
        sed "s|%%TOOLKIT_URL%%|$TOOLKIT_URL|g")
    
    echo "$DOCKERFILE_CONTENT" > "builds/$NAME/Dockerfile"
    
    # Vérifier si l'image existe et si le Dockerfile a changé
    CACHE_FILE="$CACHE_DIR/$NAME.dockerfile"
    NEEDS_REBUILD=false
    
    # Vérifier si l'image existe dans le registre
    if ! docker pull "$REGISTRY/$NAME:latest" &> /dev/null; then
        echo "Image $NAME doesn't exist in registry, will build"
        NEEDS_REBUILD=true
    # Vérifier si le Dockerfile a changé depuis la dernière construction
    elif [ ! -f "$CACHE_FILE" ] || [ "$(cat "$CACHE_FILE")" != "$DOCKERFILE_CONTENT" ]; then
        echo "Dockerfile for $NAME has changed, will rebuild"
        NEEDS_REBUILD=true
    else
        echo "Image $NAME exists and Dockerfile unchanged, skipping build"
    fi
    
    if [ "$NEEDS_REBUILD" = true ]; then
        # Construire l'image Docker
        echo "Building image: $REGISTRY/$NAME:latest"
        docker build -t "$REGISTRY/$NAME:latest" "builds/$NAME/"
        
        # Tagger avec la version PHP
        docker tag "$REGISTRY/$NAME:latest" "$REGISTRY/$NAME:php$PHP_VERSION"
        
        # Pousser les images
        docker push "$REGISTRY/$NAME:latest"
        docker push "$REGISTRY/$NAME:php$PHP_VERSION"
        
        # Mettre à jour le cache
        echo "$DOCKERFILE_CONTENT" > "$CACHE_FILE"
    fi
done

# Détecter et supprimer les images obsolètes
if [ -f "$KNOWN_IMAGES_FILE" ]; then
    while read -r OLD_IMAGE; do
        if [[ ! " ${CURRENT_IMAGES[*]} " =~ " ${OLD_IMAGE} " ]]; then
            echo "Removing obsolete image: $OLD_IMAGE"
            # Utiliser GitHub API pour supprimer l'image
            # Nécessite un token avec les permissions appropriées
            if [ -n "$GITHUB_TOKEN" ]; then
                OWNER_REPO=${GITHUB_REPOSITORY}
                OWNER=$(echo $OWNER_REPO | cut -d '/' -f 1)
                REPO=$(echo $OWNER_REPO | cut -d '/' -f 2)
                
                echo "Deleting image $OLD_IMAGE from GitHub Container Registry"
                # Attention: Ceci utilise l'API GitHub expérimentale pour supprimer des packages
                curl -X DELETE \
                  -H "Accept: application/vnd.github.v3+json" \
                  -H "Authorization: token $GITHUB_TOKEN" \
                  "https://api.github.com/user/packages/container/$REPO/$OLD_IMAGE"
                
                echo "Deleted $OLD_IMAGE from registry"
            else
                echo "GITHUB_TOKEN not set, skipping deletion of $OLD_IMAGE"
            fi
        fi
    done < "$KNOWN_IMAGES_FILE"
fi

# Enregistrer la liste actuelle des images
printf "%s\n" "${CURRENT_IMAGES[@]}" > "$KNOWN_IMAGES_FILE"

echo "Build process completed successfully"