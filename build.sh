#!/bin/bash
set -euo pipefail
rm -rf public &&
rm -rf firebase/public &&
hugo &&
cp -r public firebase/ &&
cp minify.sh firebase/public &&
cd firebase/public &&
find `pwd` -name '*.css'  -type f|xargs -I@ bash -c './minify.sh @' &&
find `pwd` -name '*.html' -type f|xargs -I@ bash -c "./minify.sh @" &&
rm minify.sh && cd ../../firebase && firebase deploy
