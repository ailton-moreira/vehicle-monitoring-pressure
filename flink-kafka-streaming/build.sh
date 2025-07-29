#!/bin/bash

# Build script for the Flink job
set -e

echo "🚀 Building Vehicle Pressure Processor Flink Job..."

# Navigate to the flink-job directory
cd flink-job

# Clean and compile the project
echo "🧹 Cleaning previous builds..."
mvn clean -q

echo "🔨 Compiling and packaging the job..."
mvn package -DskipTests -q

# Check if the JAR was created successfully
JAR_FILE="target/vehicle-pressure-processor-1.0-SNAPSHOT.jar"
if [ -f "$JAR_FILE" ]; then
    echo "✅ Build successful! JAR created at: $JAR_FILE"
    
    # Show JAR size and details
    echo "📊 JAR Details:"
    ls -lh target/*.jar | grep -E "(original|vehicle-pressure)" | while read -r line; do
        echo "   $line"
    done
    
    echo ""
    echo "🎯 Next steps:"
    echo "   1. Start the system: docker-compose up -d"
    echo "   2. Deploy the job: docker exec jobmanager flink run --class com.example.VehiclePressureProcessor /opt/flink/usrlib/vehicle-pressure-processor-1.0-SNAPSHOT.jar"
    echo "   3. Monitor: http://localhost:8081"
    
else
    echo "❌ Build failed! JAR not found."
    echo "💡 Try running with verbose output: mvn clean package -DskipTests"
    exit 1
fi

echo ""
echo "🎉 Build completed successfully!"