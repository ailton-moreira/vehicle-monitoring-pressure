#!/bin/bash

# Ensure checkpoint directories exist with proper permissions
mkdir -p /flink-checkpoints /tmp/flink-checkpoints /tmp/flink-savepoints
chmod 777 /flink-checkpoints /tmp/flink-checkpoints /tmp/flink-savepoints

# Call the original Flink Docker entrypoint
exec /flink-entrypoint-original.sh "$@"
