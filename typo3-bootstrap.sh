#!/usr/bin/env bash
set -e

# @TODO: Add fulcrum installation
# @TODO: Add helhum/typo3-console as a necessary dependency and install it

# --- COLORS ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- REQUIREMENTS CHECK ---
if ! command -v ddev &>/dev/null; then
  echo "✘ ddev not found. Please install it first."
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "✘ jq not found. Please install it first."
  exit 1
fi

# --- PROJECT SETUP ---
while true; do
  read -p "Enter TYPO3 project name: " PROJECT
  if [ -z "$PROJECT" ]; then
    echo "Project name cannot be empty."
    continue
  fi
  if [ -d "$PROJECT" ]; then
    echo "A project named '$PROJECT' already exists. Please choose a different name."
  else
    break
  fi
done

mkdir "$PROJECT" && cd "$PROJECT"

echo -e "${GREEN}Configuring DDEV for TYPO3...${RESET}"
ddev config --php-version=8.4 --docroot=public --project-type=typo3 --webserver-type=apache-fpm --database=mysql:8.4

echo -e "${GREEN}Starting DDEV...${RESET}"
ddev start

echo -e "${GREEN}Installing TYPO3 base distribution...${RESET}"
ddev composer create "typo3/cms-base-distribution:^13"

echo -e "${GREEN}Running TYPO3 setup...${RESET}"
ddev typo3 setup --server-type=other --driver=mysqli --host=db --port=3306 --dbname=db --username=db --password=db

# --- OPTIONAL EXTENSION CREATION ---
read -p "Do you want to create a basic extension? (y/n): " CREATE_EXT

if [[ "$CREATE_EXT" =~ ^[Yy]$ ]]; then
  read -p "Enter extension name (no spaces, snake case! e.g. 'site_package'): " EXT_NAME
  read -p "Enter extension vendor name (no spaces): " EXT_VENDOR
  read -p "Enter extension key (EXT_KEY, e.g. 'myext'): " EXT_KEY
  read -p "Enter extension description: " EXT_DESC
  read -p "Enter extension author's full name: " EXT_AUTHOR_FULLNAME
  read -p "Enter extension author's email address: " EXT_AUTHOR_EMAIL
  read -p "Enter extension author's website" EXT_AUTHOR_WEBSITE
  read -p "Enter site set name: " EXT_SITESET_NAME
  read -p "Enter site set display label: " EXT_SITESET_LABEL

  mkdir -p "packages/$EXT_NAME/Configuration/Sets/$EXT_SITESET_NAME"
  mkdir -p "packages/$EXT_NAME/Resources"

  echo -e "${GREEN}Creating files for extension '$EXT_NAME' with key '$EXT_KEY'...${RESET}"

  # composer.json (extension)
  cat <<EOF >"packages/$EXT_NAME/composer.json"
{
  "name": "$EXT_VENDOR/$EXT_NAME",
  "description": "$EXT_DESC",
  "type": "typo3-cms-extension",
  "authors": [
    {
      "name": "$EXT_AUTHOR_FULLNAME",
      "email": "$EXT_AUTHOR_EMAIL",
      "homepage": "https://$EXT_AUTHOR_WEBSITE",
      "role": "creator"
    }
  ],
  "extra": {
    "typo3/cms": {
      "extension-key": "$EXT_KEY"
    }
  } 
}
EOF

  # Configuration/Sets/EXT_SITESET_NAME/setup.typoscript
  touch "packages/$EXT_NAME/Configuration/Sets/$EXT_SITESET_NAME/setup.typoscript"

  # Configuration/Sets/EXT_SITESET_NAME/config.yaml
  cat <<EOF >"packages/$EXT_NAME/Configuration/Sets/$EXT_SITESET_NAME/config.yaml"
name: $EXT_VENDOR/$EXT_KEY
label: '$EXT_SITESET_LABEL'
EOF

  echo -e "${YELLOW}Updating main composer.json...${RESET}"
  COMPOSER_FILE="composer.json"

  # Add dependency to "require" block
  TMP=$(mktemp)
  jq --arg ext "hotbytes/$EXT_NAME" '.require[$ext] = "@dev"' "$COMPOSER_FILE" >"$TMP" && mv "$TMP" "$COMPOSER_FILE"

  # Ensure repositories path entry exists
  HAS_REPO=$(jq '.repositories[]? | select(.url=="./packages/*")' "$COMPOSER_FILE" || true)
  if [ -z "$HAS_REPO" ]; then
    TMP=$(mktemp)
    jq '.repositories += [{"type":"path","url":"./packages/*","options":{"symlink":true}}]' "$COMPOSER_FILE" >"$TMP" && mv "$TMP" "$COMPOSER_FILE"
  else
    # Ensure symlink option is present
    TMP=$(mktemp)
    jq '(.repositories[] | select(.url=="./packages/*").options.symlink) = true' "$COMPOSER_FILE" >"$TMP" && mv "$TMP" "$COMPOSER_FILE"
  fi

  echo -e "${GREEN}Running 'ddev composer install' to link the new extension...${RESET}"
  ddev composer update

  echo -e "${GREEN}Extension '$EXT_NAME' created, added to composer.json, and installed.${RESET}"
fi

echo -e "${GREEN}✅ TYPO3 project setup complete.${RESET}"
