#!/bin/bash

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
sleep 30

# Create input topic: sensor_pressure_stream
kafka-topics --create \
  --bootstrap-server kafka:29092 \
  --topic sensor_pressure_stream \
  --partitions 6 \
  --replication-factor 1 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000

# Create output topic: vehicle_pressure_max
kafka-topics --create \
  --bootstrap-server kafka:29092 \
  --topic vehicle_pressure_max \
  --partitions 4 \
  --replication-factor 1 \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.1

echo "Topics created successfully!"

# List topics to verify
kafka-topics --list --bootstrap-server kafka:29092