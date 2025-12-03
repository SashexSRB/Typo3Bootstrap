#!/usr/bin/env bash
set -e

# @TODO: Replace the TypoScript directory with Site Set directory, Legacy TypoScript loading won't be supported in v14 or v15.
# @TODO: Add logic to create the Site Set structure and config.yaml
# @TODO: Remove redundant files from being created.

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
read -p "Enter TYPO3 project name: " PROJECT
if [ -d "$PROJECT" ]; then
  read -p "Directory '$PROJECT' already exists. Overwrite? (y/n): " OVERWRITE
  [[ "$OVERWRITE" =~ ^[Yy]$ ]] || {
    echo "Aborted."
    exit 1
  }
  rm -rf "$PROJECT"
fi
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
  read -p "Enter extension name (no spaces): " EXT_NAME
  read -p "Enter extension key (EXT_KEY, e.g. 'myext'): " EXT_KEY
  read -p "Enter extension description: " EXT_DESC
  read -p "Enter extension author full name: " EXT_AUTHOR_FULLNAME
  read -p "Enter extension author E-Mail: " EXT_AUTHOR_EMAIL
  read -p "Enter TypoScript displayed name: " TS_DISPLAYED_NAME

  mkdir -p "packages/$EXT_NAME/Configuration/TypoScript"
  mkdir -p "packages/$EXT_NAME/Configuration/TCA/Overrides"
  mkdir -p "packages/$EXT_NAME/Resources"

  echo -e "${GREEN}Creating files for extension '$EXT_NAME' with key '$EXT_KEY'...${RESET}"

  # compose.json (extension)
  HOMEPAGE=$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]')
  cat <<EOF >"packages/$EXT_NAME/composer.json"
{
  "name": "hotbytes/$EXT_NAME",
  "description": "$EXT_DESC",
  "type": "typo3-cms-extension",
  "authors": [
    {
      "name": "$EXT_AUTHOR_FULLNAME",
      "email": "$EXT_AUTHOR_EMAIL",
      "homepage": "https://$HOMEPAGE.ddev.site",
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

  # ext_localconf.php
  echo "<?php
defined('TYPO3') or die();" >"packages/$EXT_NAME/ext_localconf.php"

  # ext_tables.sql
  touch "packages/$EXT_NAME/ext_tables.sql"

  # setup.typoscript
  touch "packages/$EXT_NAME/Configuration/TypoScript/setup.typoscript"

  # sys_template.php
  cat <<EOF >"packages/$EXT_NAME/Configuration/TCA/Overrides/sys_template.php"
<?php

defined('TYPO3') or die();

\TYPO3\CMS\Core\Utility\ExtensionManagementUtility::addStaticFile(
  '$EXT_KEY',
  'Configuration/Typoscript',
  '$TS_DISPLAYED_NAME'
);
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
