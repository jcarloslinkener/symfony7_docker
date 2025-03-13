#!/usr/bin/env bash

docker compose --env-file docker.env down --volumes --remove-orphans
