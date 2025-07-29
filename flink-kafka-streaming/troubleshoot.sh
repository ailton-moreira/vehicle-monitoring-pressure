#!/bin/bash

# Troubleshooting script for Vehicle Pressure Monitoring System
echo "🔧 Vehicle Pressure Monitoring System - Troubleshooting"
echo "======================================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "\n${BLUE}$1${NC}"
    echo "----------------------------------------"
}

print_issue() {
    echo -e "${RED}❌ $1${NC}"
}

print_solution() {
    echo -e "${GREEN}💡 $1${NC}"
}

print_command() {
    echo -e "${YELLOW}   $ $1${NC}"
}

# Navigate to project directory
if [ -f "flink-kafka-streaming/docker-compose.yml" ]; then
    cd flink-kafka-streaming
elif [ -f "docker-compose.yml" ]; then
    echo "Already in flink-kafka-streaming directory"
else
    echo -e "${RED}Error: Please run this script from the project root directory${NC}"
    exit 1
fi

print_section "1. CHECKING DOCKER SERVICES"

# Check if services are running
services=("zookeeper" "kafka" "jobmanager" "taskmanager1" "taskmanager2" "taskmanager3" "data-simulator" "kafka-ui")
failed_services=()

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo -e "${GREEN}✅${NC} $service is running"
    else
        echo -e "${RED}❌${NC} $service is not running"
        failed_services+=("$service")
    fi
done

if [ ${#failed_services[@]} -gt 0 ]; then
    print_issue "Some services are not running"
    print_solution "Try restarting failed services:"
    for service in "${failed_services[@]}"; do
        print_command "docker-compose restart $service"
    done
    print_solution "Or restart all services:"
    print_command "docker-compose down && docker-compose up -d"
fi

print_section "2. CHECKING KAFKA CONNECTIVITY"

# Test Kafka connectivity
if timeout 10 docker exec kafka kafka-topics --list --bootstrap-server localhost:29092 > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Kafka is accessible"
else
    print_issue "Cannot connect to Kafka"
    print_solution "Kafka might still be starting. Wait 1-2 minutes and try:"
    print_command "docker logs kafka | tail -20"
    print_solution "If Kafka keeps failing, try:"
    print_command "docker-compose restart kafka"
fi

print_section "3. CHECKING KAFKA TOPICS"

required_topics=("sensor_pressure_stream" "vehicle_pressure_max")
missing_topics=()

for topic in "${required_topics[@]}"; do
    if timeout 10 docker exec kafka kafka-topics --list --bootstrap-server localhost:29092 2>/dev/null | grep -q "$topic"; then
        echo -e "${GREEN}✅${NC} Topic $topic exists"
    else
        echo -e "${RED}❌${NC} Topic $topic is missing"
        missing_topics+=("$topic")
    fi
done

if [ ${#missing_topics[@]} -gt 0 ]; then
    print_issue "Some topics are missing"
    print_solution "Run the topic initialization:"
    print_command "docker-compose up kafka-init"
    print_solution "Or create topics manually:"
    print_command "docker exec kafka kafka-topics --create --bootstrap-server localhost:29092 --topic sensor_pressure_stream --partitions 6 --replication-factor 1"
    print_command "docker exec kafka kafka-topics --create --bootstrap-server localhost:29092 --topic vehicle_pressure_max --partitions 4 --replication-factor 1"
fi

print_section "4. CHECKING FLINK CLUSTER"

# Check Flink Web UI
if curl -s http://localhost:8081/overview > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Flink Web UI is accessible"
    
    # Check task managers
    tm_count=$(curl -s http://localhost:8081/taskmanagers | jq '.taskmanagers | length' 2>/dev/null || echo "0")
    if [ "$tm_count" -ge 3 ]; then
        echo -e "${GREEN}✅${NC} Task managers are running ($tm_count/3)"
    else
        print_issue "Not enough task managers running ($tm_count/3)"
        print_solution "Restart task managers:"
        print_command "docker-compose restart taskmanager1 taskmanager2 taskmanager3"
    fi
else
    print_issue "Flink Web UI is not accessible"
    print_solution "Check JobManager status:"
    print_command "docker logs jobmanager | tail -20"
    print_solution "Restart Flink cluster:"
    print_command "docker-compose restart jobmanager taskmanager1 taskmanager2 taskmanager3"
fi

print_section "5. CHECKING FLINK JOB STATUS"

# Check if job is deployed and running
job_status=$(timeout 10 curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[] | select(.name=="Vehicle Pressure Processor") | .state' 2>/dev/null)

if [ "$job_status" = "RUNNING" ]; then
    echo -e "${GREEN}✅${NC} Flink job is running"
elif [ "$job_status" = "FAILED" ]; then
    print_issue "Flink job has failed"
    print_solution "Check job logs and restart:"
    print_command "curl http://localhost:8081/jobs"
    print_solution "Redeploy the job:"
    print_command "./build.sh && docker exec jobmanager flink run --class com.example.VehiclePressureProcessor /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar"
elif [ -z "$job_status" ]; then
    print_issue "Flink job is not deployed"
    print_solution "Deploy the job:"
    print_command "./build.sh"
    print_command "docker exec jobmanager flink run --class com.example.VehiclePressureProcessor /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar"
else
    echo -e "${YELLOW}⚠️${NC} Flink job status: $job_status"
fi

print_section "6. CHECKING DATA FLOW"

# Check input data
print_command "Checking input data..."
if timeout 15 docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:29092 \
    --topic sensor_pressure_stream \
    --max-messages 1 \
    --timeout-ms 10000 > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Input data is flowing"
else
    print_issue "No input data detected"
    print_solution "Check data simulator:"
    print_command "docker logs data-simulator | tail -10"
    print_solution "Restart data simulator:"
    print_command "docker-compose restart data-simulator"
fi

# Check output data
print_command "Checking output data..."
if timeout 15 docker exec kafka kafka-console-consumer \
    --bootstrap-server localhost:29092 \
    --topic vehicle_pressure_max \
    --max-messages 1 \
    --timeout-ms 10000 > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Output data is being produced"
else
    print_issue "No output data detected"
    print_solution "This could mean:"
    echo "   - Flink job is not processing data"
    echo "   - No new maximum pressure values found yet"
    print_solution "Check Flink job logs:"
    print_command "docker logs jobmanager | grep -i vehicle"
fi

print_section "7. RESOURCE USAGE CHECK"

# Check disk space
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 90 ]; then
    print_issue "Disk usage is high (${disk_usage}%)"
    print_solution "Clean up Docker resources:"
    print_command "docker system prune -f"
    print_command "docker volume prune -f"
else
    echo -e "${GREEN}✅${NC} Disk usage is OK (${disk_usage}%)"
fi

# Check memory usage
memory_available=$(free -m | awk 'NR==2{printf "%.1f", $7*100/$2 }')
if (( $(echo "$memory_available < 20" | bc -l) )); then
    print_issue "Low memory available (${memory_available}%)"
    print_solution "Consider:"
    echo "   - Closing other applications"
    echo "   - Reducing Flink parallelism"
    echo "   - Increasing system memory"
else
    echo -e "${GREEN}✅${NC} Memory usage is OK"
fi

print_section "8. QUICK FIXES"

echo -e "${YELLOW}Common Quick Fixes:${NC}"
echo ""
echo "🔄 Full restart:"
print_command "docker-compose down && docker-compose up -d"
echo ""
echo "🧹 Clean restart:"
print_command "docker-compose down -v && docker-compose up -d"
echo ""
echo "📊 View live logs:"
print_command "docker-compose logs -f"
echo ""
echo "🔍 Check specific service:"
print_command "docker logs <service-name>"
echo ""
echo "🚀 Redeploy Flink job:"
print_command "./build.sh && docker exec jobmanager flink run --class com.example.VehiclePressureProcessor /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar"

print_section "9. USEFUL MONITORING COMMANDS"

echo "📈 Monitor input messages:"
print_command "docker exec kafka kafka-console-consumer --bootstrap-server localhost:29092 --topic sensor_pressure_stream"
echo ""
echo "📊 Monitor output messages:"
print_command "docker exec kafka kafka-console-consumer --bootstrap-server localhost:29092 --topic vehicle_pressure_max"
echo ""
echo "🌐 Access Web UIs:"
echo "   • Flink: http://localhost:8081"
echo "   • Kafka: http://localhost:8080"
echo ""
echo "🔍 Run continuous monitoring:"
print_command "./monitor-system.sh"

echo ""
echo -e "${GREEN}Troubleshooting complete!${NC}"
echo "If issues persist, check the logs for more detailed error messages."
