package com.example;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.Objects;

/**
 * POJO representing a sensor reading from the input Kafka topic
 */
public class SensorReading {
    
    @JsonProperty("timestamp")
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd HH:mm:ss.SSS'Z'", timezone = "UTC")
    private Instant timestamp;
    
    @JsonProperty("pressure")
    private double pressure;
    
    @JsonProperty("temperature")
    private double temperature;
    
    @JsonProperty("sensorId")
    private String sensorId;
    
    @JsonProperty("vehicleId")
    private String vehicleId;
    
    // Default constructor for Jackson
    public SensorReading() {}
    
    public SensorReading(Instant timestamp, double pressure, double temperature, String sensorId, String vehicleId) {
        this.timestamp = timestamp;
        this.pressure = pressure;
        this.temperature = temperature;
        this.sensorId = sensorId;
        this.vehicleId = vehicleId;
    }
    
    // Getters and Setters
    public Instant getTimestamp() {
        return timestamp;
    }
    
    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }
    
    public double getPressure() {
        return pressure;
    }
    
    public void setPressure(double pressure) {
        this.pressure = pressure;
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
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        SensorReading that = (SensorReading) o;
        return Double.compare(that.pressure, pressure) == 0 &&
               Double.compare(that.temperature, temperature) == 0 &&
               Objects.equals(timestamp, that.timestamp) &&
               Objects.equals(sensorId, that.sensorId) &&
               Objects.equals(vehicleId, that.vehicleId);
    }
    
    @Override
    public int hashCode() {
        return Objects.hash(timestamp, pressure, temperature, sensorId, vehicleId);
    }
    
    @Override
    public String toString() {
        return "SensorReading{" +
               "timestamp=" + timestamp +
               ", pressure=" + pressure +
               ", temperature=" + temperature +
               ", sensorId='" + sensorId + '\'' +
               ", vehicleId='" + vehicleId + '\'' +
               '}';
    }
}