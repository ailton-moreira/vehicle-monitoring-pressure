package com.example;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.Objects;

/**
 * POJO representing the maximum pressure output for a vehicle
 */
public class VehiclePressureMax {
    
    @JsonProperty("timestamp")
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd HH:mm:ss.SSS'Z'", timezone = "UTC")
    private Instant timestamp;
    
    @JsonProperty("pressureMax")
    private double pressureMax;
    
    @JsonProperty("temperature")
    private double temperature;
    
    @JsonProperty("sensorId")
    private String sensorId;
    
    @JsonProperty("vehicleId")
    private String vehicleId;
    
    // Default constructor for Jackson
    public VehiclePressureMax() {}
    
    public VehiclePressureMax(Instant timestamp, double pressureMax, double temperature, String sensorId, String vehicleId) {
        this.timestamp = timestamp;
        this.pressureMax = pressureMax;
        this.temperature = temperature;
        this.sensorId = sensorId;
        this.vehicleId = vehicleId;
    }
    
    // Factory method to create from SensorReading
    public static VehiclePressureMax fromSensorReading(SensorReading reading) {
        return new VehiclePressureMax(
            reading.getTimestamp(),
            reading.getPressure(),
            reading.getTemperature(),
            reading.getSensorId(),
            reading.getVehicleId()
        );
    }
    
    // Getters and Setters
    public Instant getTimestamp() {
        return timestamp;
    }
    
    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }
    
    public double getPressureMax() {
        return pressureMax;
    }
    
    public void setPressureMax(double pressureMax) {
        this.pressureMax = pressureMax;
    }
    
    public double getTemperature() {
        return temperature;
    }
    
    public void setTemperature(double temperature) {
        this.temperature = temperature;
    }
    
    public String getSensorId() {
        return sensorId;
    }
    
    public void setSensorId(String sensorId) {
        this.sensorId = sensorId;
    }
    
    public String getVehicleId() {
        return vehicleId;
    }
    
    public void setVehicleId(String vehicleId) {
        this.vehicleId = vehicleId;
    }
    
    @Override
    public boolean equals(Object obj) {
        if (this == obj) return true;
        if (obj == null || getClass() != obj.getClass()) return false;
        VehiclePressureMax vpm = (VehiclePressureMax) obj;
        return Double.compare(vpm.pressureMax, pressureMax) == 0 &&
               Double.compare(vpm.temperature, temperature) == 0 &&
               Objects.equals(timestamp, vpm.timestamp) &&
               Objects.equals(sensorId, vpm.sensorId) &&
               Objects.equals(vehicleId, vpm.vehicleId);
    }
    
    @Override
    public int hashCode() {
        return Objects.hash(timestamp, pressureMax, temperature, sensorId, vehicleId);
    }
    
    @Override
    public String toString() {
        return "VehiclePressureMax{" +
               "timestamp=" + timestamp +
               ", pressureMax=" + pressureMax +
               ", temperature=" + temperature +
               ", sensorId='" + sensorId + '\'' +
               ", vehicleId='" + vehicleId + '\'' +
               '}';
    }
}