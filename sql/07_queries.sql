USE coldchain;

-- Q1: Shipment details (6-table JOIN): route, products, batches, value
SELECT 'Q1: Shipment details with route and value' AS query_title;
SELECT s.shipment_id,
       fs.facility_name AS source,
       fd.facility_name AS destination,
       p.product_name,
       b.batch_no,
       si.quantity,
       ROUND(si.quantity * p.unit_price, 2) AS value,
       s.status
FROM shipment s
JOIN facility fs      ON fs.facility_id = s.source_facility_id
JOIN facility fd      ON fd.facility_id = s.destination_facility_id
JOIN shipment_item si ON si.shipment_id = s.shipment_id
JOIN batch b          ON b.batch_id = si.batch_id
JOIN product p        ON p.product_id = b.product_id
ORDER BY s.shipment_id, p.product_name;

-- Q2: Value of stock that is expired or expires within 60 days, per facility
SELECT 'Q2: Expiry risk per facility (GROUP BY + HAVING)' AS query_title;
SELECT f.facility_name,
       COUNT(DISTINCT b.batch_id) AS batches_at_risk,
       SUM(i.quantity) AS units,
       ROUND(SUM(i.quantity * p.unit_price), 2) AS value_at_risk
FROM inventory i
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
JOIN batch b        ON b.batch_id = i.batch_id
JOIN product p      ON p.product_id = b.product_id
WHERE i.quantity > 0
  AND b.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 60 DAY)
GROUP BY f.facility_id, f.facility_name
HAVING SUM(i.quantity * p.unit_price) > 10000
ORDER BY value_at_risk DESC;

-- Q3: Excursion summary by severity
SELECT 'Q3: Alert summary by severity' AS query_title;
SELECT severity,
       COUNT(*) AS alerts,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, start_time, end_time)), 1) AS avg_minutes,
       MAX(peak_temp) AS highest_peak,
       MIN(peak_temp) AS lowest_peak
FROM excursion_alert
WHERE end_time IS NOT NULL
GROUP BY severity
HAVING COUNT(*) >= 1
ORDER BY FIELD(severity, 'Critical', 'High', 'Medium', 'Low');

-- Q4: Transit time and on-time delivery per vehicle
SELECT 'Q4: Transit performance per vehicle' AS query_title;
SELECT vehicle_reg_no,
       COUNT(*) AS trips,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, dispatch_time, actual_arrival)) / 60, 2) AS avg_transit_hours,
       ROUND(100 * SUM(actual_arrival <= eta) / COUNT(*), 1) AS on_time_pct
FROM shipment
WHERE status = 'Delivered'
GROUP BY vehicle_reg_no
ORDER BY on_time_pct DESC;

-- Q5: Facilities whose usable stock is below the reorder level
SELECT 'Q5: Below reorder level (usable stock only)' AS query_title;
SELECT f.facility_name,
       p.product_name,
       SUM(i.quantity) AS usable_qty,
       p.reorder_level
FROM inventory i
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
JOIN batch b        ON b.batch_id = i.batch_id
JOIN product p      ON p.product_id = b.product_id
WHERE i.stock_status = 'Available'
  AND b.status = 'Active'
  AND b.expiry_date > CURDATE()
GROUP BY f.facility_id, f.facility_name, p.product_id, p.product_name, p.reorder_level
HAVING SUM(i.quantity) < p.reorder_level
ORDER BY f.facility_name, p.product_name;

-- Q6: Rank facilities by value of unusable stock (RANK window function)
SELECT 'Q6: Facilities ranked by unusable stock value' AS query_title;
SELECT f.facility_name,
       ROUND(SUM(i.quantity * p.unit_price), 2) AS unusable_value,
       RANK() OVER (ORDER BY SUM(i.quantity * p.unit_price) DESC) AS value_rank
FROM inventory i
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
JOIN batch b        ON b.batch_id = i.batch_id
JOIN product p      ON p.product_id = b.product_id
WHERE i.quantity > 0
  AND (i.stock_status = 'Quarantined'
       OR b.expiry_date <= CURDATE()
       OR b.status <> 'Active')
GROUP BY f.facility_id, f.facility_name
ORDER BY value_rank;

-- Q7: Rolling 1-hour average temperature around the unit 4 excursion
SELECT 'Q7: Rolling average temperature, unit 4 (CTE + window)' AS query_title;
WITH a AS (
    SELECT start_time
    FROM excursion_alert
    WHERE unit_id = 4
    ORDER BY start_time
    LIMIT 1
)
SELECT l.recorded_at,
       l.temperature,
       ROUND(AVG(l.temperature) OVER (
           ORDER BY l.recorded_at
           ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 2) AS rolling_avg_1h
FROM temperature_log l, a
WHERE l.unit_id = 4
  AND l.recorded_at BETWEEN a.start_time - INTERVAL 1 HOUR
                        AND a.start_time + INTERVAL 4 HOUR
ORDER BY l.recorded_at;

-- Q8: Supply chain hierarchy (recursive CTE)
SELECT 'Q8: Facility hierarchy (recursive CTE)' AS query_title;
WITH RECURSIVE tree AS (
    SELECT facility_id, facility_name, facility_type, 0 AS depth,
           CAST(facility_name AS CHAR(500)) AS trail
    FROM facility
    WHERE parent_facility_id IS NULL
    UNION ALL
    SELECT f.facility_id, f.facility_name, f.facility_type, t.depth + 1,
           CONCAT(t.trail, ' > ', f.facility_name)
    FROM facility f
    JOIN tree t ON f.parent_facility_id = t.facility_id
)
SELECT CONCAT(REPEAT('-- ', depth), facility_name) AS facility,
       facility_type,
       depth,
       trail
FROM tree
ORDER BY trail;

-- Q9: Recall trace for one batch: where is it, where has it been shipped
SELECT 'Q9: Recall trace for batch CVS-2026-A01' AS query_title;
SELECT 'Stored' AS record_type,
       f.facility_name AS location,
       u.unit_name AS detail,
       i.quantity AS qty,
       i.stock_status AS status
FROM batch b
JOIN inventory i    ON i.batch_id = b.batch_id
JOIN storage_unit u ON u.unit_id = i.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
WHERE b.batch_no = 'CVS-2026-A01' AND i.quantity > 0
UNION ALL
SELECT 'Shipped',
       CONCAT(fs.facility_name, ' -> ', fd.facility_name),
       CONCAT('Shipment #', s.shipment_id),
       si.quantity,
       s.status
FROM batch b
JOIN shipment_item si ON si.batch_id = b.batch_id
JOIN shipment s       ON s.shipment_id = si.shipment_id
JOIN facility fs      ON fs.facility_id = s.source_facility_id
JOIN facility fd      ON fd.facility_id = s.destination_facility_id
WHERE b.batch_no = 'CVS-2026-A01';

-- Q10: Temperature compliance per storage unit
SELECT 'Q10: Compliance percentage per storage unit' AS query_title;
SELECT f.facility_name,
       u.unit_name,
       COUNT(*) AS readings,
       SUM(l.temperature BETWEEN u.min_temp AND u.max_temp) AS in_range,
       ROUND(100 * SUM(l.temperature BETWEEN u.min_temp AND u.max_temp) / COUNT(*), 2) AS compliance_pct
FROM temperature_log l
JOIN storage_unit u ON u.unit_id = l.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
GROUP BY u.unit_id, f.facility_name, u.unit_name
ORDER BY compliance_pct ASC;

-- Q11: Value of goods in shipments that had a temperature problem (subquery)
SELECT 'Q11: Value at risk in breached shipments (subquery)' AS query_title;
SELECT s.shipment_id,
       fs.facility_name AS source,
       fd.facility_name AS destination,
       s.temp_status,
       SUM(si.quantity) AS units,
       ROUND(SUM(si.quantity * p.unit_price), 2) AS value_at_risk
FROM shipment s
JOIN facility fs      ON fs.facility_id = s.source_facility_id
JOIN facility fd      ON fd.facility_id = s.destination_facility_id
JOIN shipment_item si ON si.shipment_id = s.shipment_id
JOIN batch b          ON b.batch_id = si.batch_id
JOIN product p        ON p.product_id = b.product_id
WHERE s.temp_status = 'Breached'
   OR s.shipment_id IN (SELECT shipment_id
                        FROM excursion_alert
                        WHERE shipment_id IS NOT NULL)
GROUP BY s.shipment_id, fs.facility_name, fd.facility_name, s.temp_status
ORDER BY value_at_risk DESC;

-- Q12: Products that have never been shipped (correlated NOT EXISTS)
SELECT 'Q12: Products never shipped (NOT EXISTS)' AS query_title;
SELECT p.product_name, p.category
FROM product p
WHERE NOT EXISTS (
    SELECT 1
    FROM shipment_item si
    JOIN batch b ON b.batch_id = si.batch_id
    WHERE b.product_id = p.product_id
);

-- Q13: Latest reading per storage unit (ROW_NUMBER window function)
SELECT 'Q13: Latest reading per storage unit' AS query_title;
WITH ranked AS (
    SELECT l.unit_id, l.recorded_at, l.temperature,
           ROW_NUMBER() OVER (PARTITION BY l.unit_id ORDER BY l.recorded_at DESC) AS rn
    FROM temperature_log l
    WHERE l.unit_id IS NOT NULL
)
SELECT f.facility_name,
       u.unit_name,
       r.recorded_at,
       r.temperature,
       CASE WHEN r.temperature BETWEEN u.min_temp AND u.max_temp
            THEN 'In range' ELSE 'OUT OF RANGE' END AS state
FROM ranked r
JOIN storage_unit u ON u.unit_id = r.unit_id
JOIN facility f     ON f.facility_id = u.facility_id
WHERE r.rn = 1
ORDER BY f.facility_name, u.unit_name;
