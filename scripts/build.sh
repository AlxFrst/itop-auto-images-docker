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

# Vérifier si jq est installé (nécessaire pour le parsing JSON)
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    apt-get update && apt-get install -y jq
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

# Vérifier et supprimer les images obsolètes du registre
echo "Checking for obsolete images in registry..."
if [ -n "$GITHUB_TOKEN" ]; then
    OWNER_REPO=${GITHUB_REPOSITORY}
    OWNER=$(echo $OWNER_REPO | cut -d '/' -f 1)
    REPO=$(echo $OWNER_REPO | cut -d '/' -f 2)
    
# Remplacer les lignes 93-120 par ceci:
    echo "Fetching packages from GitHub Container Registry API..."
    # Utiliser l'API GraphQL pour récupérer les packages
    API_RESPONSE=$(curl -s -X POST \
                -H "Authorization: token $GITHUB_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{"query": "query { user { packages(first: 100, packageType: CONTAINER) { nodes { name } } } }"}' \
                "https://api.github.com/graphql")
    
    # Extraire les noms des packages
    if echo "$API_RESPONSE" | jq -e '.data.user.packages' > /dev/null; then
        echo "Successfully queried user packages"
        PACKAGES=$(echo "$API_RESPONSE" | jq -r '.data.user.packages.nodes[].name' | grep "^$REPO\/" | cut -d '/' -f 2)
    else
        echo "Failed to fetch user packages, trying organization..."
        # Essayer comme organisation
        API_RESPONSE=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d '{"query": "query { organization(login: \"'$OWNER'\") { packages(first: 100, packageType: CONTAINER) { nodes { name } } } }"}' \
                    "https://api.github.com/graphql")
        
        if echo "$API_RESPONSE" | jq -e '.data.organization.packages' > /dev/null; then
            echo "Successfully queried organization packages"
            PACKAGES=$(echo "$API_RESPONSE" | jq -r '.data.organization.packages.nodes[].name' | grep "^$REPO\/" | cut -d '/' -f 2)
        else
            echo "Failed to fetch organization packages. Error: $(echo "$API_RESPONSE" | jq -r '.errors[].message')"
            PACKAGES=""
        fi
    fi
    
    if [ -n "$PACKAGES" ]; then
        echo "Found packages in registry: $PACKAGES"
        
        # Pour chaque package, vérifier s'il est dans l'inventaire actuel
        for PACKAGE in $PACKAGES; do
            if [[ ! " ${CURRENT_IMAGES[*]} " =~ " ${PACKAGE} " ]]; then
                echo "Removing obsolete image: $PACKAGE"
                
                # Essayer de supprimer comme package personnel
                curl -X DELETE \
                    -H "Accept: application/vnd.github.v3+json" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    "https://api.github.com/user/packages/container/$REPO%2F$PACKAGE"
                
                # Si ça ne fonctionne pas, essayer comme package d'organisation
                curl -X DELETE \
                    -H "Accept: application/vnd.github.v3+json" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    "https://api.github.com/orgs/$OWNER/packages/container/$REPO%2F$PACKAGE"
                
                echo "Deletion request sent for $PACKAGE"
            else
                echo "Package $PACKAGE is in inventory, keeping it"
            fi
        done
    else
        echo "No packages found in registry or API access error"
    fi
else
    echo "GITHUB_TOKEN not set, skipping registry cleanup"
fi

# Enregistrer la liste actuelle des images (pour compatibilité)
printf "%s\n" "${CURRENT_IMAGES[@]}" > "$KNOWN_IMAGES_FILE"

echo "Build process completed successfully"