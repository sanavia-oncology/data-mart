#!/usr/bin/env zsh
for p in 3005; do kill $(lsof -t -i :$p -sTCP:LISTEN) 2>/dev/null; done
