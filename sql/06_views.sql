USE coldchain;

-- Batches expiring within 60 days (or already expired), per facility
CREATE OR REPLACE VIEW v_expiring_soon AS
SELECT f.facility_name,
       p.product_name,
       b.batch_no,
       b.expiry_date,
       DATEDIFF(b.expiry_date, CURDATE()) AS days_left,
       SUM(i.quantity) AS quantity
FROM inventory i
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
JOIN batch b        ON b.batch_id = i.batch_id
JOIN product p      ON p.product_id = b.product_id
WHERE i.quantity > 0
  AND b.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 60 DAY)
GROUP BY f.facility_id, f.facility_name, p.product_name,
         b.batch_id, b.batch_no, b.expiry_date;

-- Alerts that are not yet resolved, with a readable location
CREATE OR REPLACE VIEW v_active_alerts AS
SELECT a.alert_id,
       COALESCE(CONCAT(f.facility_name, ' / ', u.unit_name),
                CONCAT('Shipment #', a.shipment_id)) AS location,
       a.start_time,
       a.end_time,
       TIMESTAMPDIFF(MINUTE, a.start_time, COALESCE(a.end_time, NOW())) AS duration_min,
       a.peak_temp,
       a.severity,
       a.status
FROM excursion_alert a
LEFT JOIN storage_unit u ON u.unit_id = a.unit_id
LEFT JOIN facility f     ON f.facility_id = u.facility_id
WHERE a.status <> 'Resolved';

-- Stock per facility and product: total vs usable
CREATE OR REPLACE VIEW v_stock_by_facility AS
SELECT f.facility_id,
       f.facility_name,
       f.facility_type,
       p.product_name,
       SUM(i.quantity) AS total_qty,
       SUM(CASE WHEN i.stock_status = 'Available'
                 AND b.status = 'Active'
                 AND b.expiry_date > CURDATE()
                THEN i.quantity ELSE 0 END) AS usable_qty,
       p.reorder_level
FROM inventory i
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
JOIN batch b        ON b.batch_id = i.batch_id
JOIN product p      ON p.product_id = b.product_id
GROUP BY f.facility_id, f.facility_name, f.facility_type,
         p.product_id, p.product_name, p.reorder_level;
