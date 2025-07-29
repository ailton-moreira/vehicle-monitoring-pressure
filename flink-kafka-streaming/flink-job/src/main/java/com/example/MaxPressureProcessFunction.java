package com.example;

import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * KeyedProcessFunction that maintains the maximum pressure per vehicle
 * This function ensures proper state partitioning by vehicleId and handles
 * the core business logic of tracking maximum pressure values.
 */
public class MaxPressureProcessFunction extends KeyedProcessFunction<String, SensorReading, VehiclePressureMax> {
    
    private static final Logger LOG = LoggerFactory.getLogger(MaxPressureProcessFunction.class);
    
    // State to store the current maximum pressure information for each vehicle
    private transient ValueState<VehiclePressureMax> maxPressureState;
    
    @Override
    public void open(Configuration parameters) throws Exception {
        super.open(parameters);
        
        // Initialize the state descriptor for maximum pressure tracking
        ValueStateDescriptor<VehiclePressureMax> maxPressureDescriptor = new ValueStateDescriptor<>(
            "maxPressure",
            TypeInformation.of(VehiclePressureMax.class)
        );
        
        // Enable TTL (Time To Live) for state cleanup - optional but recommended for production
        // This prevents state from growing indefinitely for inactive vehicles
        // StateTtlConfig ttlConfig = StateTtlConfig
        //     .newBuilder(Time.days(30))
        //     .setUpdateType(StateTtlConfig.UpdateType.OnCreateAndWrite)
        //     .setStateVisibility(StateTtlConfig.StateVisibility.NeverReturnExpired)
        //     .build();
        // maxPressureDescriptor.enableTimeToLive(ttlConfig);
        
        maxPressureState = getRuntimeContext().getState(maxPressureDescriptor);
        
        LOG.info("MaxPressureProcessFunction initialized for task: {}", 
                getRuntimeContext().getIndexOfThisSubtask());
    }
    
    @Override
    public void processElement(SensorReading sensorReading, 
                             KeyedProcessFunction<String, SensorReading, VehiclePressureMax>.Context context, 
                             Collector<VehiclePressureMax> collector) throws Exception {
        
        String vehicleId = sensorReading.getVehicleId();
        double currentPressure = sensorReading.getPressure();
        
        // Get the current maximum pressure for this vehicle
        VehiclePressureMax currentMax = maxPressureState.value();
        
        boolean shouldEmit = false;
        VehiclePressureMax newMax;
        
        if (currentMax == null) {
            // First reading for this vehicle - initialize the maximum
            newMax = VehiclePressureMax.fromSensorReading(sensorReading);
            shouldEmit = true;
            
            LOG.info("First reading for vehicle {}: pressure={}, sensor={}", 
                    vehicleId, currentPressure, sensorReading.getSensorId());
            
        } else if (currentPressure > currentMax.getPressureMax()) {
            // New maximum found - update the state and emit
            newMax = VehiclePressureMax.fromSensorReading(sensorReading);
            shouldEmit = true;
            
            LOG.info("New maximum for vehicle {}: {} -> {} (sensor: {})", 
                    vehicleId, currentMax.getPressureMax(), currentPressure, sensorReading.getSensorId());
            
        } else {
            // Current reading is not a new maximum - no need to emit
            newMax = currentMax;
            shouldEmit = false;
            
            LOG.debug("No new maximum for vehicle {}: current={}, max={}", 
                     vehicleId, currentPressure, currentMax.getPressureMax());
        }
        
        // Update the state with the new maximum (or keep the existing one)
        maxPressureState.update(newMax);
        // Log the new max calculation
            LOG.info("New pressureMax for vehicle {}: {} (sensor: {}, timestamp: {})",
                newMax.getVehicleId(), newMax.getPressureMax(), newMax.getSensorId(), newMax.getTimestamp());

        
        // Emit the result only if we have a new maximum
        if (shouldEmit) {
            collector.collect(newMax);
            
            LOG.info("Emitted new maximum for vehicle {}: pressureMax={}, timestamp={}, sensor={}", 
                    newMax.getVehicleId(), newMax.getPressureMax(), newMax.getTimestamp(), newMax.getSensorId());
        }
    }
    
    @Override
    public void onTimer(long timestamp, 
                       KeyedProcessFunction<String, SensorReading, VehiclePressureMax>.OnTimerContext ctx, 
                       Collector<VehiclePressureMax> out) throws Exception {
        // This method can be used for periodic operations like state cleanup
        // or periodic emission of current maximums
        // For now, we don't need any timer-based logic
    }
}