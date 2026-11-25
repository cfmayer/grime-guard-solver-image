#!/usr/bin/env bash
# Creates ONE 1x H200 SXM Community pod booted from the prebuilt solver image (Runpod REST API v2).
# THIS SPENDS MONEY (~$3.59/h Community at time of writing). Requires RUNPOD_API_KEY and an SSH key registered on the
# Runpod account (startSsh injects it as PUBLIC_KEY; the image's entrypoint authorizes it and starts sshd).
curl -sS -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer $RUNPOD_API_KEY" -H 'Content-Type: application/json' -d '{"name":"grimeguard-spuma","cloud":"COMMUNITY","gpu":{"id":"NVIDIA H200","count":1,"minCudaVersion":"12.3"},"image":"ghcr.io/cfmayer/grime-guard-solver-image:latest","disk":400,"ports":["22/tcp"],"startSsh":true}'
