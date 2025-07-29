#!/usr/bin/env python3
"""
IoT Sensor Data Simulator for Kafka Streaming
Generates realistic sensor pressure data for multiple vehicles and sensors
"""

import json
import time
import random
import logging
from datetime import datetime, timezone
from typing import Dict, List
import os
from kafka import KafkaProducer
from faker import Faker
import numpy as np

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SensorDataSimulator:
    """Simulates IoT sensor data for vehicle pressure monitoring"""
    
    def __init__(self, kafka_servers: str, topic: str):
        self.kafka_servers = kafka_servers
        self.topic = topic
        self.fake = Faker()
        
        # Initialize Kafka producer
        self.producer = KafkaProducer(
            bootstrap_servers=kafka_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None,
            acks='all',
            retries=3,
            batch_size=16384,
            linger_ms=10,
            buffer_memory=33554432
        )
        
        # Vehicle and sensor configuration
        self.vehicles = self._generate_vehicles(10)  # 10 vehicles
        self.sensors_per_vehicle = 1000  # 3 sensors per vehicle
        self.sensor_data = self._initialize_sensor_data()
        
        logger.info(f"Initialized simulator with {len(self.vehicles)} vehicles")
        logger.info(f"Total sensors: {len(self.vehicles) * self.sensors_per_vehicle}")
    
    def _generate_vehicles(self, count: int) -> List[str]:
        """Generate realistic vehicle IDs"""
        vehicles = []
        prefixes = ['Porsche', 'BMW', 'GM', 'AUDI', 'VW', "Mercedes", 'Toyota', 'Honda', 'Ford', 'Nissan']
        
        for _ in range(count):
            prefix = random.choice(prefixes)
            number = random.randint(100, 999)
            vehicles.append(f"{prefix} {number}")
        
        return vehicles
    
    def _initialize_sensor_data(self) -> Dict:
        """Initialize sensor data with realistic baselines"""
        sensor_data = {}
        
        for vehicle_id in self.vehicles:
            vehicle_sensors = {}
            base_pressure = random.uniform(750000, 850000)  # Base pressure range
            base_temp = random.uniform(20, 35)  # Base temperature range
            
            for sensor_num in range(self.sensors_per_vehicle):
                sensor_id = f"{vehicle_id.replace(' ', '').replace('-', '').lower()}{sensor_num:02d}"
                
                vehicle_sensors[sensor_id] = {
                    'vehicle_id': vehicle_id,
                    'base_pressure': base_pressure + random.uniform(-50000, 50000),
                    'current_pressure': base_pressure,
                    'base_temperature': base_temp + random.uniform(-5, 5),
                    'current_temperature': base_temp,
                    'pressure_trend': random.choice(['increasing', 'decreasing', 'stable']),
                    'last_update': datetime.now(timezone.utc)
                }
            
            sensor_data.update(vehicle_sensors)
        
        return sensor_data
    
    def _generate_realistic_pressure(self, sensor_id: str) -> float:
        """Generate realistic pressure values with trends and anomalies"""
        sensor = self.sensor_data[sensor_id]
        current_pressure = sensor['current_pressure']
        base_pressure = sensor['base_pressure']
        trend = sensor['pressure_trend']
        
        # Normal variation (±5% of base pressure)
        normal_variation = random.uniform(-0.05, 0.05) * base_pressure
        
        # Trend-based change
        trend_change = 0
        if trend == 'increasing':
            trend_change = random.uniform(0, 0.02) * base_pressure
        elif trend == 'decreasing':
            trend_change = random.uniform(-0.02, 0) * base_pressure
        
        # Occasional anomalies (5% chance of significant spike)
        anomaly_change = 0
        if random.random() < 0.05:
            anomaly_change = random.uniform(0.1, 0.3) * base_pressure
            logger.info(f"Anomaly generated for sensor {sensor_id}: +{anomaly_change:.0f}")
        
        # Calculate new pressure
        new_pressure = current_pressure + normal_variation + trend_change + anomaly_change
        
        # Ensure pressure stays within realistic bounds
        new_pressure = max(500000, min(1200000, new_pressure))
        
        # Update sensor state
        sensor['current_pressure'] = new_pressure
        
        # Occasionally change trend (10% chance)
        if random.random() < 0.1:
            sensor['pressure_trend'] = random.choice(['increasing', 'decreasing', 'stable'])
        
        return new_pressure
    
    def _generate_realistic_temperature(self, sensor_id: str) -> float:
        """Generate realistic temperature values"""
        sensor = self.sensor_data[sensor_id]
        base_temp = sensor['base_temperature']
        current_temp = sensor['current_temperature']
        
        # Temperature varies more slowly than pressure
        temp_change = random.uniform(-2, 2)
        new_temp = current_temp + temp_change
        
        # Keep temperature within realistic bounds
        new_temp = max(10, min(60, new_temp))
        
        # Update sensor state
        sensor['current_temperature'] = new_temp
        
        return new_temp
    
    def generate_sensor_message(self, sensor_id: str) -> Dict:
        """Generate a single sensor message"""
        sensor = self.sensor_data[sensor_id]
        
        message = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + "Z",
            "pressure": self._generate_realistic_pressure(sensor_id),
            "temperature": self._generate_realistic_temperature(sensor_id),
            "sensorId": sensor_id,
            "vehicleId": sensor['vehicle_id']
        }
        
        return message
    
    def run_simulation(self, duration_seconds: int = None, messages_per_second: int = 10):
        """Run the sensor data simulation"""
        logger.info(f"Starting simulation - {messages_per_second} messages/second")
        
        start_time = time.time()
        message_count = 0
        
        try:
            while True:
                # Check duration limit
                if duration_seconds and (time.time() - start_time) > duration_seconds:
                    break
                
                # Generate messages for random sensors
                sensors_to_send = random.sample(
                    list(self.sensor_data.keys()), 
                    min(messages_per_second, len(self.sensor_data))
                )
                
                for sensor_id in sensors_to_send:
                    message = self.generate_sensor_message(sensor_id)
                    
                    # Send to Kafka
                    self.producer.send(
                        topic=self.topic,
                        key=sensor_id,
                        value=message
                    )
                    
                    message_count += 1
                    
                    if message_count % 100 == 0:
                        logger.info(f"Sent {message_count} messages")
                
                # Flush producer to ensure delivery
                self.producer.flush()
                
                # Wait for next batch
                time.sleep(1.0)
                
        except KeyboardInterrupt:
            logger.info("Simulation interrupted by user")
        except Exception as e:
            logger.error(f"Simulation error: {e}")
        finally:
            self.producer.close()
            logger.info(f"Simulation completed. Total messages sent: {message_count}")
    
    def generate_test_scenario(self):
        """Generate a specific test scenario to demonstrate the maximum pressure issue"""
        logger.info("Running test scenario to demonstrate maximum pressure tracking")
        
        # Select one vehicle for focused testing
        test_vehicle = self.vehicles[0]
        test_sensors = [sid for sid, data in self.sensor_data.items() 
                       if data['vehicle_id'] == test_vehicle]
        
        logger.info(f"Test vehicle: {test_vehicle}")
        logger.info(f"Test sensors: {test_sensors}")
        
        # Send initial baseline readings
        for sensor_id in test_sensors:
            message = self.generate_sensor_message(sensor_id)
            self.producer.send(self.topic, key=sensor_id, value=message)
            logger.info(f"Baseline - {sensor_id}: {message['pressure']:.0f}")
        
        time.sleep(2)
        
        # Send a high pressure reading from one sensor
        high_pressure_sensor = test_sensors[0]
        self.sensor_data[high_pressure_sensor]['current_pressure'] = 950000
        message = self.generate_sensor_message(high_pressure_sensor)
        self.producer.send(self.topic, key=high_pressure_sensor, value=message)
        logger.info(f"HIGH PRESSURE - {high_pressure_sensor}: {message['pressure']:.0f}")
        
        time.sleep(2)
        
        # Send normal readings from other sensors
        for sensor_id in test_sensors[1:]:
            message = self.generate_sensor_message(sensor_id)
            self.producer.send(self.topic, key=sensor_id, value=message)
            logger.info(f"Normal - {sensor_id}: {message['pressure']:.0f}")
        
        self.producer.flush()
        logger.info("Test scenario completed")

def main():
    """Main function to run the simulator"""
    # Get configuration from environment variables
    kafka_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    topic = os.getenv('KAFKA_TOPIC', 'sensor_pressure_stream')
    duration = int(os.getenv('SIMULATION_DURATION', '0'))  # 0 = infinite
    rate = int(os.getenv('MESSAGES_PER_SECOND', '10'))
    
    logger.info(f"Configuration:")
    logger.info(f"  Kafka servers: {kafka_servers}")
    logger.info(f"  Topic: {topic}")
    logger.info(f"  Duration: {'infinite' if duration == 0 else f'{duration} seconds'}")
    logger.info(f"  Rate: {rate} messages/second")
    
    # Wait for Kafka to be ready
    logger.info("Waiting for Kafka to be ready...")
    time.sleep(30)
    
    # Initialize and run simulator
    simulator = SensorDataSimulator(kafka_servers, topic)
    
    # Run test scenario first
    simulator.generate_test_scenario()
    
    # Then run continuous simulation
    simulator.run_simulation(duration_seconds=duration if duration > 0 else None, 
                           messages_per_second=rate)

if __name__ == "__main__":
    main()