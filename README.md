# Vehicle Pressure Monitoring System with Kafka & Flink

A real-time stream processing system that monitors vehicle sensor pressure data using Apache Kafka and Apache Flink. This project demonstrates distributed stream processing, state management, and maximum value aggregation across multiple sensors per vehicle.

## 🚀 Project Overview

This system addresses a distributed streaming challenge where:

- **IoT sensors** send pressure readings for multiple vehicles
- **Apache Kafka** handles the data streaming
- **Apache Flink** processes the streams to find maximum pressure per vehicle
- **Docker** orchestrates the entire system

### Problem Solved

The original issue was that when scaling from 1 to 3 Flink executors, the maximum pressure calculations became inconsistent because:

1. Data was partitioned by `sensorId` instead of `vehicleId`
2. Multiple sensors per vehicle were processed by different executors
3. No coordination existed between executors for global maximum calculation

### Solution Implemented

- ✅ **Proper Key Partitioning**: Key by `vehicleId` to ensure all sensor data for a vehicle reaches the same executor
- ✅ **Persistent State Management**: RocksDB state backend with checkpointing for fault tolerance
- ✅ **Event Time Processing**: Watermarks for consistent temporal processing
- ✅ **Exactly-Once Processing**: Guaranteed delivery semantics

## 📋 Prerequisites

### System Requirements

- **Docker** (v20.10+) and **Docker Compose** (v2.0+)
- **Java 11** (for local development)
- **Maven 3.6+** (for building the Flink job)
- **Python 3.11+** (for running the simulator locally)

### Hardware Requirements

- Minimum 8GB RAM
- 4 CPU cores recommended
- 10GB free disk space

## 🏗️ Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────┐
│   IoT       │    │    Kafka     │    │     Flink       │    │     Kafka        │    │   Portal    │
│  Sensors    │───▶│   (Input)    │───▶│   Processing    │───▶│   (Output)       │───▶│  Dashboard  │
│             │    │              │    │                 │    │                  │    │             │
└─────────────┘    └──────────────┘    └─────────────────┘    └──────────────────┘    └─────────────┘
                         │                       │                       │
                         │                       ▼                       │
                         │              ┌─────────────────┐              │
                         │              │   RocksDB       │              │
                         │              │ State Backend   │              │
                         │              └─────────────────┘              │
                         │                                               │
                         ▼                                               ▼
                   Topic: sensor_pressure_stream              Topic: vehicle_pressure_max
                   Partitions: 6                              Partitions: 4
                   Key: sensorId                              Key: vehicleId
                   Cleanup: delete                            Cleanup: compact
```

## 🚀 Getting Started

### Step 1: Clone and Navigate to Project

```bash
git clone <repository-url>
cd Kafka_flink
```

### Step 2: Build the Flink Job

```bash
cd flink-kafka-streaming
chmod +x build.sh
./build.sh
```

Expected output:

```
✅ Build successful! JAR created at: target/vehicle-pressure-processor-1.0-SNAPSHOT.jar
```

### Step 3: Start the System

```bash
# Start all services
docker-compose up -d

# Check if all services are running
docker-compose ps
```

Expected services:

- ✅ `zookeeper` - Kafka coordination
- ✅ `kafka` - Message broker
- ✅ `kafka-init` - Topic initialization (will complete and exit)
- ✅ `jobmanager` - Flink Job Manager
- ✅ `taskmanager1-3` - Flink Task Managers (3 instances)
- ✅ `data-simulator` - Python IoT simulator
- ✅ `kafka-ui` - Kafka monitoring interface

- Create the checkpoint dir in jobmanager

  ```bash
  docker exec jobmanager mkdir -p /flink-checkpoints
  ```

- Change the dir permition
  ```bash
  docker exec jobmanager chmod 777 /flink-checkpoints
  ```

### Step 4: Verify System Health

#### Check Kafka Topics

```bash
docker exec kafka kafka-topics --list --bootstrap-server localhost:29092
```

Expected topics:

- `sensor_pressure_stream` (6 partitions)
- `vehicle_pressure_max` (4 partitions)

#### Check Flink Cluster

Open browser: http://localhost:8081

You should see:

- 1 Job Manager
- 3 Task Managers
- Total Task Slots: 6

### Step 5: Deploy the Flink Job

```bash
# Submit the job to Flink cluster
docker exec jobmanager flink run \
  --class com.example.VehiclePressureProcessor \
  /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar
```

### Step 6: Monitor the System

#### Flink Web UI

- **URL**: http://localhost:8081
- **Monitor**: Job execution, checkpoints, metrics

#### Kafka UI

- **URL**: http://localhost:8080
- **Monitor**: Topics, messages, consumer groups

#### View Real-time Data

```bash
# Monitor input data
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:29092 \
  --topic sensor_pressure_stream \
  --from-beginning

# Monitor output data (maximum pressures)
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:29092 \
  --topic vehicle_pressure_max \
  --from-beginning
```

#### Check Logs

```bash
# Flink Job Manager logs
docker logs jobmanager

# Task Manager logs
docker logs taskmanager1

# Data Simulator logs
docker logs data-simulator
```

## 📊 Understanding the Data Flow

### Input Data Format (sensor_pressure_stream)

```json
{
  "timestamp": "2025-07-22 22:30:45.123Z",
  "pressure": 850000,
  "temperature": 25.5,
  "sensorId": "honda23100",
  "vehicleId": "HONDA 231"
}
```

### Output Data Format (vehicle_pressure_max)

```json
{
  "timestamp": "2025-07-22 22:30:45.123Z",
  "pressureMax": 950000,
  "temperature": 30.2,
  "sensorId": "honda23101",
  "vehicleId": "HONDA 231"
}
```

### Processing Logic

1. **Input**: Sensors send pressure readings keyed by `sensorId`
2. **Repartition**: Data is rekeyed by `vehicleId` for proper state distribution
3. **State Management**: Each vehicle's maximum pressure is stored in RocksDB
4. **Comparison**: New readings are compared with stored maximum
5. **Output**: Only new maximums are emitted to output topic

## 🛠️ Configuration

### Environment Variables

| Variable                  | Default        | Description                      |
| ------------------------- | -------------- | -------------------------------- |
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:29092`  | Kafka broker address             |
| `SIMULATION_DURATION`     | `0` (infinite) | Simulator run duration (seconds) |
| `MESSAGES_PER_SECOND`     | `5`            | Message generation rate          |

### Flink Configuration

- **Parallelism**: 6 (matches input topic partitions)
- **Checkpointing**: Every 60 seconds
- **State Backend**: RocksDB for persistence
- **Event Time**: With 30-second watermark tolerance

### Kafka Configuration

- **Input Topic**: 6 partitions, delete cleanup policy
- **Output Topic**: 4 partitions, compact cleanup policy
- **Replication Factor**: 1 (for development)

## 🧪 Testing Scenarios

### Scenario 1: Basic Functionality Test

```bash
# 1. Start the system (steps 1-6 above)
# 2. Check that data flows through the system
# 3. Verify maximum calculation is working

# Expected: You should see maximum pressure updates in the output topic
```

### Scenario 2: High Pressure Spike Test

The simulator automatically generates pressure spikes to test maximum detection:

```bash
# Monitor the logs to see when spikes occur
docker logs data-simulator | grep "Anomaly"

# Check output topic for corresponding maximum updates
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:29092 \
  --topic vehicle_pressure_max \
  --from-beginning | jq '.'
```

### Scenario 3: Fault Tolerance Test

```bash
# Kill a task manager to test recovery
docker stop taskmanager1

# Wait 2 minutes and check Flink UI - job should recover
# Restart the task manager
docker start taskmanager1
```

### Scenario 4: Scaling Test

1. Open your docker-compose.yml.
2. Find the taskmanager1 service.
3. Remove or comment out the line with container_name: taskmanager1.
4. Save the file.
5. Run the scale command

```bash
# Scale up task managers
docker-compose up -d --scale taskmanager1=2

# Scale up all task managers executors instance
docker-compose up -d --scale taskmanager1=2 --scale taskmanager2=2 --scale taskmanager3=2
# Check Flink UI for additional task slots
```

## 📈 Performance Monitoring

### Key Metrics to Monitor

#### Flink Metrics

- **Throughput**: Records/second processed
- **Latency**: End-to-end processing time
- **Checkpointing**: Success rate and duration
- **Memory Usage**: Task manager heap usage

#### Kafka Metrics

- **Producer Rate**: Messages/second to input topic
- **Consumer Lag**: Delay in processing messages
- **Topic Growth**: Message accumulation rate

### Performance Tuning Tips

1. **Increase Parallelism**: Match Kafka partition count
2. **Tune Checkpointing**: Balance frequency vs performance
3. **Optimize State**: Use TTL for inactive vehicles
4. **Memory Allocation**: Increase heap size for large state

## 🐛 Troubleshooting

### Common Issues

#### 1. "No space left on device"

```bash
# Clean up Docker volumes
docker system prune -a --volumes
```

#### 2. Flink job fails with serialization errors

```bash
# Check timestamp format compatibility
# Verify JSON structure matches POJOs
docker logs jobmanager | grep -i error
```

#### 3. Kafka connection refused

```bash
# Wait for Kafka to be ready (may take 1-2 minutes)
docker logs kafka | grep "started"
```

#### 4. No data in output topic

```bash
# Check if job is running
curl http://localhost:8081/jobs

# Verify input data is flowing
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:29092 \
  --topic sensor_pressure_stream \
  --max-messages 5
```

### Debug Commands

```bash
# Check service health
docker-compose ps

# View all logs
docker-compose logs

# Check specific service
docker logs <service-name> -f

# Access Kafka container
docker exec -it kafka bash

# Access Flink container
docker exec -it jobmanager bash
```

## 🛑 Stopping the System

### Graceful Shutdown

```bash
# Cancel the Flink job first
curl -X PATCH http://localhost:8081/jobs/<job-id>

# Stop all services
docker-compose down

# Clean up volumes (optional)
docker-compose down -v
```

### Force Stop

```bash
# Force stop all containers
docker-compose down --remove-orphans

# Clean everything including images
docker-compose down --rmi all --volumes --remove-orphans
```

## 🚀 Production Deployment Considerations

### High Availability

- Deploy Kafka cluster with replication factor 3
- Use external Zookeeper ensemble
- Set up Flink in HA mode with multiple job managers

### Security

- Enable SSL/TLS for Kafka connections
- Implement authentication and authorization
- Use network policies for container isolation

### Monitoring & Alerting

- Set up Prometheus + Grafana for metrics
- Configure alerts for job failures
- Monitor resource utilization

### Backup & Recovery

- Set up automated state backup
- Test recovery procedures
- Document runbooks for common scenarios

## 📚 Additional Resources

- [Apache Flink Documentation](https://flink.apache.org/docs/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Stream Processing Patterns](https://www.oreilly.com/library/view/stream-processing-with/9781491974285/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Note**: This system is designed for demonstration and development purposes. For production use, additional considerations for security, monitoring, and high availability are required.
