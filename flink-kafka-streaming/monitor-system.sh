#!/bin/bash

# Continuous monitoring script for Vehicle Pressure Monitoring System
# Usage: ./monitor-system.sh [interval_seconds]

INTERVAL=${1:-30}  # Default to 30 seconds if no argument provided

echo "🔍 Starting continuous monitoring (interval: ${INTERVAL}s)"
echo "Press Ctrl+C to stop monitoring"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

while true; do
    clear
    echo -e "${BLUE}🚀 Vehicle Pressure Monitoring System - Health Check${NC}"
    echo "Last updated: $(date)"
    echo "============================================"
    
    # Check Docker services
    echo -e "${YELLOW}📊 Service Status:${NC}"
    services=("zookeeper" "kafka" "jobmanager" "taskmanager1" "taskmanager2" "taskmanager3" "data-simulator" "kafka-ui")
    
    for service in "${services[@]}"; do
        if cd flink-kafka-streaming 2>/dev/null && docker-compose ps | grep -q "$service.*Up"; then
            echo -e "   ${GREEN}✅${NC} $service"
        else
            echo -e "   ${RED}❌${NC} $service"
        fi
    done
    
    echo ""
    
    # Check Flink job status
    echo -e "${YELLOW}🔧 Flink Job Status:${NC}"
    cd flink-kafka-streaming 2>/dev/null
    JOB_STATUS=$(timeout 5 curl -s http://localhost:8081/jobs 2>/dev/null | jq -r '.jobs[] | select(.name=="Vehicle Pressure Processor") | .state' 2>/dev/null)
    
    if [ "$JOB_STATUS" = "RUNNING" ]; then
        echo -e "   ${GREEN}✅${NC} Vehicle Pressure Processor: RUNNING"
    elif [ "$JOB_STATUS" = "FAILED" ]; then
        echo -e "   ${RED}❌${NC} Vehicle Pressure Processor: FAILED"
    elif [ -z "$JOB_STATUS" ]; then
        echo -e "   ${YELLOW}⚠️${NC} Vehicle Pressure Processor: NOT DEPLOYED"
    else
        echo -e "   ${YELLOW}⚠️${NC} Vehicle Pressure Processor: $JOB_STATUS"
    fi
    
    echo ""
    
    # Check Kafka topic message counts
    echo -e "${YELLOW}📈 Message Counts (last 30 seconds):${NC}"
    
    # Input topic
    INPUT_COUNT=$(timeout 5 docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:29092 \
        --topic sensor_pressure_stream 2>/dev/null | \
        awk -F: '{sum += $3} END {print sum}' 2>/dev/null || echo "N/A")
    echo -e "   Input (sensor_pressure_stream): $INPUT_COUNT messages"
    
    # Output topic
    OUTPUT_COUNT=$(timeout 5 docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:29092 \
        --topic vehicle_pressure_max 2>/dev/null | \
        awk -F: '{sum += $3} END {print sum}' 2>/dev/null || echo "N/A")
    echo -e "   Output (vehicle_pressure_max): $OUTPUT_COUNT messages"
    
    echo ""
    
    # Check resource usage
    echo -e "${YELLOW}💾 Resource Usage:${NC}"
    
    # Memory usage of key containers
    JOBMANAGER_MEM=$(docker stats --no-stream jobmanager 2>/dev/null | tail -n 1 | awk '{print $4}' || echo "N/A")
    KAFKA_MEM=$(docker stats --no-stream kafka 2>/dev/null | tail -n 1 | awk '{print $4}' || echo "N/A")
    
    echo -e "   JobManager Memory: $JOBMANAGER_MEM"
    echo -e "   Kafka Memory: $KAFKA_MEM"
    
    echo ""
    
    # Recent error check
    echo -e "${YELLOW}🚨 Recent Errors (last 5 minutes):${NC}"
    
    # Check for errors in job manager logs
    JM_ERRORS=$(docker logs jobmanager --since 5m 2>/dev/null | grep -i error | wc -l || echo "0")
    echo -e "   JobManager errors: $JM_ERRORS"
    
    # Check for errors in task manager logs
    TM_ERRORS=$(docker logs taskmanager1 --since 5m 2>/dev/null | grep -i error | wc -l || echo "0")
    echo -e "   TaskManager errors: $TM_ERRORS"
    
    # Check for errors in simulator logs
    SIM_ERRORS=$(docker logs data-simulator --since 5m 2>/dev/null | grep -i error | wc -l || echo "0")
    echo -e "   Simulator errors: $SIM_ERRORS"
    
    echo ""
    echo "============================================"
    echo "⏰ Next update in ${INTERVAL} seconds..."
    echo "🌐 Access Points:"
    echo "   • Flink UI: http://localhost:8081"
    echo "   • Kafka UI: http://localhost:8080"
    
    sleep $INTERVAL
done
