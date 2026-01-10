#!/bin/bash

URL="https://website.apps.test.ocp.globomantics.com"

while true; do
  CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$URL")
  TS=$(date '+%H:%M')

  if [ "$CODE" = "000" ]; then
    echo "$TS DOWN ($CODE)"
  else
    echo "$TS UP ($CODE)"
  fi

  sleep 1
done