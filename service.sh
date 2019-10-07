#!/usr/bin/env bash

. "test.env"

cf create-user-provided-service octonet-service -p "{\"client_id\": \"$OAUTH_CLIENT_ID\", \"client_secret\": \"$OAUTH_CLIENT_SECRET\", \"session_secret\": \"Ajjia54521eiuwooiocv68\"}"
