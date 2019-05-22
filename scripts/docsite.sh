#!/usr/bin/env bash

# usage: npm run docsite [build|start]

set -o errexit

if [ "$1" = start ]; then
  npx concurrently -n docgen,docsite --no-color \
    'nodemon -w contracts -e sol,md -x npm run docgen' \
    'openzeppelin-docsite-run start'
else
  npm run docgen
  npx openzeppelin-docsite-run "$1"
fi
