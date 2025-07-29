#!/bin/bash

# Deployment Validation Script for Vehicle Pressure Monitoring System
set -e

echo "🚀 Starting Vehicle Pressure Monitoring System Validation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        exit 1
    fi
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check prerequisites
print_info "Checking prerequisites..."

# Check Docker
docker --version > /dev/null 2>&1
print_status $? "Docker is installed"

# Check Docker Compose
docker-compose --version > /dev/null 2>&1
print_status $? "Docker Compose is installed"

# Check if we're in the right directory
if [ -f "flink-kafka-streaming/docker-compose.yml" ]; then
    cd flink-kafka-streaming
    print_status 0 "Found project directory"
else
    print_status 1 "Project directory not found. Run this script from the Kafka_flink root directory."
fi

# Build the Flink job
print_info "Building Flink job..."
chmod +x build.sh
./build.sh > /dev/null 2>&1
print_status $? "Flink job built successfully"

# Start the system
print_info "Starting Docker services..."
docker-compose up -d > /dev/null 2>&1
print_status $? "Docker services started"

# Wait for services to be ready
print_info "Waiting for services to initialize (90 seconds)..."
sleep 90

# Check if all required services are running
print_info "Checking service health..."

services=("zookeeper" "kafka" "jobmanager" "taskmanager1" "taskmanager2" "taskmanager3" "data-simulator" "kafka-ui")

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        print_status 0 "$service is running"
    else
        print_status 1 "$service is not running properly"
    fi
done

# Check Kafka topics
print_info "Checking Kafka topics..."
timeout 30 docker exec kafka kafka-topics --list --bootstrap-server localhost:29092 | grep -q "sensor_pressure_stream"
print_status $? "Input topic (sensor_pressure_stream) exists"

timeout 30 docker exec kafka kafka-topics --list --bootstrap-server localhost:29092 | grep -q "vehicle_pressure_max"
print_status $? "Output topic (vehicle_pressure_max) exists"

# Check Flink cluster
print_info "Checking Flink cluster..."
curl -s http://localhost:8081/overview > /dev/null 2>&1
print_status $? "Flink Web UI is accessible"

# Check if we can access Kafka UI
print_info "Checking Kafka UI..."
curl -s http://localhost:8080 > /dev/null 2>&1
print_status $? "Kafka UI is accessible"

# Check data flow
print_info "Checking data flow..."
timeout 30 docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:29092 \
    --topic sensor_pressure_stream \
    --max-messages 1 \
    --timeout-ms 25000 > /dev/null 2>&1
print_status $? "Data is flowing to input topic"

# Deploy Flink job
print_info "Deploying Flink job..."
timeout 60 docker exec jobmanager flink run \
    --class com.example.VehiclePressureProcessor \
    /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar > /dev/null 2>&1
print_status $? "Flink job deployed successfully"

# Wait for job to process some data
print_info "Waiting for job to process data (60 seconds)..."
sleep 60

# Check if output data is being produced
print_info "Checking output data..."
timeout 30 docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:29092 \
    --topic vehicle_pressure_max \
    --max-messages 1 \
    --timeout-ms 25000 > /dev/null 2>&1
print_status $? "Output data is being produced"

echo ""
echo -e "${GREEN}🎉 Vehicle Pressure Monitoring System is successfully deployed and running!${NC}"
echo ""
echo "📊 Access Points:"
echo "   • Flink Web UI: http://localhost:8081"
echo "   • Kafka UI: http://localhost:8080"
echo ""
echo "🔧 Useful Commands:"
echo "   • View logs: docker-compose logs <service-name>"
echo "   • Monitor input: docker exec kafka kafka-console-consumer --bootstrap-server localhost:29092 --topic sensor_pressure_stream"
echo "   • Monitor output: docker exec kafka kafka-console-consumer --bootstrap-server localhost:29092 --topic vehicle_pressure_max"
echo "   • Stop system: docker-compose down"
echo ""
echo -e "${YELLOW}Note: The system will continue running. Use 'docker-compose down' to stop it.${NC}"
