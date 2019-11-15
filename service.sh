#!/usr/bin/env bash

cmd="${1:-create}"

. "test.env"
cf ${cmd}-user-provided-service octonet-service -p "{\"client_id\": \"$OAUTH_CLIENT_ID\", \"client_secret\": \"$OAUTH_CLIENT_SECRET\", \"session_secret\": \"$SESSION_SECRET\"}"
