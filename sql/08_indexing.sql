USE coldchain;

-- Speeds up per-sensor time-range lookups on the largest table
CREATE INDEX idx_temp_sensor_time ON temperature_log (sensor_id, recorded_at);
