package com.example;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.serialization.SerializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.contrib.streaming.state.EmbeddedRocksDBStateBackend;
import org.apache.flink.streaming.api.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.CheckpointConfig;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.kafka.clients.consumer.OffsetResetStrategy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.time.Duration;

/**
 * Main Flink job for processing vehicle sensor pressure data
 * 
 * This job addresses the distributed processing issue by:
 * 1. Properly partitioning data by vehicleId instead of sensorId
 * 2. Using persistent state backend (RocksDB) for fault tolerance
 * 3. Implementing proper checkpointing for exactly-once processing
 * 4. Using event time processing with watermarks
 */
public class VehiclePressureProcessor {
    
    private static final Logger LOG = LoggerFactory.getLogger(VehiclePressureProcessor.class);
    
    // Kafka configuration
    private static final String INPUT_TOPIC = "sensor_pressure_stream";
    private static final String OUTPUT_TOPIC = "vehicle_pressure_max";
    private static final String KAFKA_BOOTSTRAP_SERVERS = "kafka:29092";
    private static final String CONSUMER_GROUP = "vehicle_pressure_processor";
    
    // Flink configuration
    private static final int PARALLELISM = 6; // Match input topic partitions
    private static final Duration CHECKPOINT_INTERVAL = Duration.ofSeconds(60);
    private static final Duration WATERMARK_IDLE_TIMEOUT = Duration.ofMinutes(1);
    private static final Duration MAX_OUT_OF_ORDERNESS = Duration.ofSeconds(30);
    
    public static void main(String[] args) throws Exception {
        LOG.info("Starting Vehicle Pressure Processor");
        
        // Create the execution environment
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configure the execution environment
        configureEnvironment(env);
        
        // Create Kafka source
        KafkaSource<SensorReading> kafkaSource = createKafkaSource();
        
        // Create Kafka sink
        KafkaSink<VehiclePressureMax> kafkaSink = createKafkaSink();
        
        // Build the processing pipeline
        DataStream<SensorReading> sensorStream = env
            .fromSource(kafkaSource, createWatermarkStrategy(), "Kafka Source")
            .name("Sensor Data Source")
            .uid("sensor-data-source");
        
        // Key by vehicleId to ensure all sensor data for a vehicle goes to the same operator
        DataStream<VehiclePressureMax> maxPressureStream = sensorStream
            .keyBy(SensorReading::getVehicleId)
            .process(new MaxPressureProcessFunction())
            .name("Max Pressure Calculator")
            .uid("max-pressure-calculator");
        
        // Sink to output Kafka topic
        maxPressureStream
            .sinkTo(kafkaSink)
            .name("Kafka Sink")
            .uid("kafka-sink");
        
        // Add some logging for monitoring
        sensorStream.print("INPUT").name("Input Logger").uid("input-logger");
        maxPressureStream.print("OUTPUT").name("Output Logger").uid("output-logger");
        
        LOG.info("Job configuration completed. Starting execution...");
        
        // Execute the job
        env.execute("Vehicle Pressure Processor");
    }
    
    /**
     * Configure the Flink execution environment with proper settings
     */
    private static void configureEnvironment(StreamExecutionEnvironment env) {
        // Set parallelism to match input topic partitions
        env.setParallelism(PARALLELISM);
        
        // Use in-memory state backend for now (can be changed to RocksDB later)
        // This avoids checkpoint storage permission issues for initial testing
        EmbeddedRocksDBStateBackend rocksDBStateBackend = new EmbeddedRocksDBStateBackend(true);
        env.setStateBackend(rocksDBStateBackend);
        
        //env.getCheckpointConfig().setCheckpointStorage("file:///tmp/flink-checkpoints");

        // Configure checkpointing for fault tolerance with more robust settings
        env.enableCheckpointing(CHECKPOINT_INTERVAL.toMillis(), CheckpointingMode.EXACTLY_ONCE);
        
        CheckpointConfig checkpointConfig = env.getCheckpointConfig();
        checkpointConfig.setCheckpointStorage("file:///flink-checkpoints");
        checkpointConfig.setMinPauseBetweenCheckpoints(30000); // 30 seconds
        checkpointConfig.setCheckpointTimeout(600000); // 10 minutes
        checkpointConfig.setMaxConcurrentCheckpoints(1);
        checkpointConfig.setTolerableCheckpointFailureNumber(3); // Allow some checkpoint failures
        checkpointConfig.setExternalizedCheckpointCleanup(
            CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION);
        
        // Configure restart strategy for better fault tolerance
        env.getConfig().setRestartStrategy(
            org.apache.flink.api.common.restartstrategy.RestartStrategies.fixedDelayRestart(
                3, // number of restart attempts
                org.apache.flink.api.common.time.Time.of(10, java.util.concurrent.TimeUnit.SECONDS) // delay
            )
        );
        
        LOG.info("Environment configured with parallelism: {}, checkpoint interval: {}ms", 
                PARALLELISM, CHECKPOINT_INTERVAL.toMillis());
    }
    
    /**
     * Create Kafka source for consuming sensor data
     */
    private static KafkaSource<SensorReading> createKafkaSource() {
        return KafkaSource.<SensorReading>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setTopics(INPUT_TOPIC)
            .setGroupId(CONSUMER_GROUP)
            .setStartingOffsets(OffsetsInitializer.committedOffsets(OffsetResetStrategy.LATEST))
            .setValueOnlyDeserializer(new SensorReadingDeserializer())
            .build();
    }
    
    /**
     * Create Kafka sink for producing maximum pressure data
     */
    private static KafkaSink<VehiclePressureMax> createKafkaSink() {
        return KafkaSink.<VehiclePressureMax>builder()
            .setBootstrapServers(KAFKA_BOOTSTRAP_SERVERS)
            .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                .setTopic(OUTPUT_TOPIC)
                .setKeySerializationSchema(new VehicleIdKeySerializer())
                .setValueSerializationSchema(new VehiclePressureMaxSerializer())
                .build())
            .build();
    }
    
    /**
     * Create watermark strategy for event time processing
     */
    private static WatermarkStrategy<SensorReading> createWatermarkStrategy() {
        return WatermarkStrategy
            .<SensorReading>forBoundedOutOfOrderness(MAX_OUT_OF_ORDERNESS)
            .withTimestampAssigner((reading, timestamp) -> reading.getTimestamp().toEpochMilli())
            .withIdleness(WATERMARK_IDLE_TIMEOUT);
    }
    
    /**
     * Custom deserializer for SensorReading
     */
    public static class SensorReadingDeserializer implements DeserializationSchema<SensorReading> {
        private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        
        @Override
        public SensorReading deserialize(byte[] message) throws IOException {
            try {
                return objectMapper.readValue(message, SensorReading.class);
            } catch (Exception e) {
                LOG.error("Failed to deserialize sensor reading: {}", new String(message), e);
                throw e;
            }
        }
        
        @Override
        public boolean isEndOfStream(SensorReading nextElement) {
            return false;
        }
        
        @Override
        public TypeInformation<SensorReading> getProducedType() {
            return TypeInformation.of(SensorReading.class);
        }
    }
    
    /**
     * Custom serializer for VehiclePressureMax
     */
    public static class VehiclePressureMaxSerializer implements SerializationSchema<VehiclePressureMax> {
        private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());
        
        @Override
        public byte[] serialize(VehiclePressureMax element) {
            try {
                return objectMapper.writeValueAsBytes(element);
            } catch (Exception e) {
                throw new RuntimeException("Failed to serialize VehiclePressureMax", e);
            }
        }
    }
    
    /**
     * Custom key serializer to ensure proper partitioning by vehicleId
     */
    public static class VehicleIdKeySerializer implements SerializationSchema<VehiclePressureMax> {
        @Override
        public byte[] serialize(VehiclePressureMax element) {
            return element.getVehicleId().getBytes();
        }
    }
}