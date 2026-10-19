USE coldchain;

DROP TRIGGER IF EXISTS trg_temperature_check;
DROP TRIGGER IF EXISTS trg_shipment_item_check;
DROP TRIGGER IF EXISTS trg_shipment_check;

DELIMITER $$

-- Trigger 1: detect temperature excursions automatically
CREATE TRIGGER trg_temperature_check
AFTER INSERT ON temperature_log
FOR EACH ROW
BEGIN
    DECLARE v_min DECIMAL(5,2);
    DECLARE v_max DECIMAL(5,2);
    DECLARE v_limit INT;
    DECLARE v_alert_id INT;
    DECLARE v_start DATETIME;
    DECLARE v_peak DECIMAL(5,2);
    DECLARE v_dev DECIMAL(5,2);
    DECLARE v_peak_dev DECIMAL(5,2);
    DECLARE v_sev VARCHAR(10);

    -- Safe range and allowed excursion time
    IF NEW.unit_id IS NOT NULL THEN
        SELECT min_temp, max_temp INTO v_min, v_max
        FROM storage_unit WHERE unit_id = NEW.unit_id;

        SELECT MIN(p.max_excursion_minutes) INTO v_limit
        FROM inventory i
        JOIN batch b ON b.batch_id = i.batch_id
        JOIN product p ON p.product_id = b.product_id
        WHERE i.unit_id = NEW.unit_id AND i.quantity > 0;
    ELSE
        SELECT MAX(p.min_temp), MIN(p.max_temp), MIN(p.max_excursion_minutes)
        INTO v_min, v_max, v_limit
        FROM shipment_item si
        JOIN batch b ON b.batch_id = si.batch_id
        JOIN product p ON p.product_id = b.product_id
        WHERE si.shipment_id = NEW.shipment_id;
    END IF;

    IF v_limit IS NULL THEN
        SET v_limit = 30;
    END IF;

    IF v_min IS NOT NULL AND v_max IS NOT NULL THEN

        -- Is there already an open alert for this unit or shipment?
        SELECT MAX(alert_id) INTO v_alert_id
        FROM excursion_alert
        WHERE end_time IS NULL
          AND status <> 'Resolved'
          AND ( (NEW.unit_id IS NOT NULL AND unit_id = NEW.unit_id)
             OR (NEW.shipment_id IS NOT NULL AND shipment_id = NEW.shipment_id) );

        IF NEW.temperature < v_min OR NEW.temperature > v_max THEN

            -- How far outside the range, and how severe
            IF NEW.temperature > v_max THEN
                SET v_dev = NEW.temperature - v_max;
            ELSE
                SET v_dev = v_min - NEW.temperature;
            END IF;

            IF v_dev >= 6 THEN
                SET v_sev = 'Critical';
            ELSEIF v_dev >= 4 THEN
                SET v_sev = 'High';
            ELSEIF v_dev >= 2 THEN
                SET v_sev = 'Medium';
            ELSE
                SET v_sev = 'Low';
            END IF;

            IF v_alert_id IS NULL THEN
                INSERT INTO excursion_alert
                    (unit_id, shipment_id, start_time, peak_temp, severity)
                VALUES
                    (NEW.unit_id, NEW.shipment_id, NEW.recorded_at, NEW.temperature, v_sev);
                SET v_start = NEW.recorded_at;
            ELSE
                SELECT start_time, peak_temp INTO v_start, v_peak
                FROM excursion_alert WHERE alert_id = v_alert_id;

                IF v_peak > v_max THEN
                    SET v_peak_dev = v_peak - v_max;
                ELSE
                    SET v_peak_dev = v_min - v_peak;
                END IF;

                IF v_dev > v_peak_dev THEN
                    UPDATE excursion_alert
                    SET peak_temp = NEW.temperature, severity = v_sev
                    WHERE alert_id = v_alert_id;
                END IF;
            END IF;

            -- Too long outside the range: quarantine the affected stock
            IF TIMESTAMPDIFF(MINUTE, v_start, NEW.recorded_at) > v_limit THEN
                IF NEW.unit_id IS NOT NULL THEN
                    UPDATE inventory
                    SET stock_status = 'Quarantined'
                    WHERE unit_id = NEW.unit_id AND stock_status = 'Available';
                ELSE
                    UPDATE shipment
                    SET temp_status = 'Breached'
                    WHERE shipment_id = NEW.shipment_id AND temp_status = 'OK';
                END IF;
            END IF;

        ELSEIF v_alert_id IS NOT NULL THEN
            -- Back in range: close the open alert
            UPDATE excursion_alert
            SET end_time = NEW.recorded_at
            WHERE alert_id = v_alert_id;
        END IF;
    END IF;
END$$

-- Trigger 2: block unsafe items from entering a shipment
CREATE TRIGGER trg_shipment_item_check
BEFORE INSERT ON shipment_item
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_expiry DATE;
    DECLARE v_qty INT;
    DECLARE v_quarantined INT;

    SELECT status, expiry_date INTO v_status, v_expiry
    FROM batch WHERE batch_id = NEW.batch_id;

    SELECT SUM(quantity) INTO v_qty
    FROM inventory
    WHERE unit_id = NEW.source_unit_id AND batch_id = NEW.batch_id;

    SELECT COUNT(*) INTO v_quarantined
    FROM inventory
    WHERE unit_id = NEW.source_unit_id AND batch_id = NEW.batch_id
      AND stock_status = 'Quarantined';

    IF v_expiry <= CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot ship an expired batch';
    ELSEIF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot ship a batch that is not Active';
    ELSEIF v_quarantined > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock in this storage unit is quarantined after a temperature excursion';
    ELSEIF v_qty IS NULL OR v_qty < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient stock in the source storage unit';
    END IF;
END$$

-- Trigger 3: basic shipment sanity checks
CREATE TRIGGER trg_shipment_check
BEFORE INSERT ON shipment
FOR EACH ROW
BEGIN
    IF NEW.source_facility_id = NEW.destination_facility_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Source and destination facility must be different';
    ELSEIF NEW.dispatch_time IS NOT NULL AND NEW.eta IS NOT NULL
           AND NEW.eta <= NEW.dispatch_time THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ETA must be later than dispatch time';
    END IF;
END$$

DELIMITER ;
