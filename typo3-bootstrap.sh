#!/usr/bin/env bash
set -e

# --- COLORS ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- REQUIREMENTS CHECK ---
if ! command -v ddev &>/dev/null; then
  echo "❌ ddev not found. Please install it first."
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "❌ jq not found. Please install it first."
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

# --- LAUNCH TYPO3 ---
echo -e "${GREEN}Launching TYPO3...${RESET}"
ddev launch /typo3/

# --- OPTIONAL EXTENSION CREATION ---
read -p "Do you want to create a basic extension? (y/n): " CREATE_EXT

if [[ "$CREATE_EXT" =~ ^[Yy]$ ]]; then
  read -p "Enter extension name (no spaces): " EXTNAME
  read -p "Enter extension key (EXTKEY, e.g. 'myext'): " EXTKEY
  read -p "Enter extension description: " EXTDESC
  read -p "Enter extension author full name: " EXTAUTHFULLNAME
  read -p "Enter extension author E-Mail: " EXTAUTHEMAIL
  read -p "Enter display name (for TypoScript template): " DISPLNAME

  mkdir -p "packages/$EXTNAME/Configuration/TypoScript"
  mkdir -p "packages/$EXTNAME/Configuration/TCA/Overrides"
  mkdir -p "packages/$EXTNAME/Resources"

  echo -e "${GREEN}Creating files for extension '$EXTNAME' with key '$EXTKEY'...${RESET}"

  # compose.json (extension)
  HOMEPAGE=$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]')
  cat <<EOF >"packages/$EXTNAME/composer.json"
{
  "name": "hotbytes/$EXTNAME",
  "description": "$EXTDESC",
  "type": "typo3-cms-extension",
  "authors": [
    {
      "name": "$EXTAUTHFULLNAME",
      "email": "$EXTAUTHEMAIL",
      "homepage": "https://$HOMEPAGE.ddev.site",
      "role": "creator"
    }
  ],
  "extra": {
    "typo3/cms": {
      "extension-key": "$EXTKEY"
    }
  } 
}
EOF

  # ext_emconf.php
  cat <<EOF >"packages/$EXTNAME/ext_emconf.php"
<?php

\$EM_CONF[\$_EXTKEY] = [
  'title' => '$EXTNAME',
  'description' => '$EXTDESC',
  'category' => 'plugin',
  'state' => 'beta',
  'author' => '$EXTAUTHFULLNAME',
  'author_email' => '$EXTAUTHEMAIL',
  'version' => '1.0.0',
];
EOF

  # ext_localconf.php
  echo "<?php
defined('TYPO3') or die();" >"packages/$EXTNAME/ext_localconf.php"

  # ext_tables.sql
  touch "packages/$EXTNAME/ext_tables.sql"

  # setup.typoscript
  touch "packages/$EXTNAME/Configuration/TypoScript/setup.typoscript"

  # sys_template.php
  cat <<EOF >"packages/$EXTNAME/Configuration/TCA/Overrides/sys_template.php"
<?php

defined('TYPO3') or die();

\TYPO3\CMS\Core\Utility\ExtensionManagementUtility::addStaticFile(
  '$EXTKEY',
  'Configuration/Typoscript',
  '$DISPLNAME'
);
EOF

  echo -e "${YELLOW}Updating main composer.json...${RESET}"
  COMPOSER_FILE="composer.json"

  # Add dependency to "require" block
  TMP=$(mktemp)
  jq --arg ext "hotbytes/$EXTNAME" '.require[$ext] = "@dev"' "$COMPOSER_FILE" >"$TMP" && mv "$TMP" "$COMPOSER_FILE"

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

  echo -e "${GREEN}Extension '$EXTNAME' created, added to composer.json, and installed.${RESET}"
fi

echo -e "${GREEN}✅ TYPO3 project setup complete.${RESET}"
