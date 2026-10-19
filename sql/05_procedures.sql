USE coldchain;

DROP PROCEDURE IF EXISTS sp_create_shipment;
DROP PROCEDURE IF EXISTS sp_receive_shipment;

DELIMITER $$

-- Create a shipment, picking stock by FEFO, all-or-nothing
CREATE PROCEDURE sp_create_shipment(
    IN  p_source     INT,
    IN  p_dest       INT,
    IN  p_user       INT,
    IN  p_vehicle    VARCHAR(20),
    IN  p_driver     VARCHAR(100),
    IN  p_sensor     VARCHAR(30),
    IN  p_product    INT,
    IN  p_quantity   INT,
    IN  p_eta_hours  INT,
    OUT p_shipment_id INT
)
BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_unit INT;
    DECLARE v_batch INT;
    DECLARE v_qty INT;
    DECLARE v_remaining INT;
    DECLARE v_take INT;

    -- Usable stock at the source facility, earliest expiry first (FEFO)
    DECLARE cur CURSOR FOR
        SELECT i.unit_id, i.batch_id, i.quantity
        FROM inventory i
        JOIN storage_unit u ON u.unit_id = i.unit_id
        JOIN batch b ON b.batch_id = i.batch_id
        WHERE u.facility_id = p_source
          AND b.product_id = p_product
          AND b.status = 'Active'
          AND b.expiry_date > CURDATE()
          AND i.stock_status = 'Available'
          AND i.quantity > 0
        ORDER BY b.expiry_date ASC, b.batch_id ASC
        FOR UPDATE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_remaining = p_quantity;

    START TRANSACTION;

    INSERT INTO shipment
        (source_facility_id, destination_facility_id, created_by,
         vehicle_reg_no, driver_name, sensor_id, dispatch_time, eta, status)
    VALUES
        (p_source, p_dest, p_user, p_vehicle, p_driver, p_sensor,
         NOW(), DATE_ADD(NOW(), INTERVAL p_eta_hours HOUR), 'In Transit');

    SET p_shipment_id = LAST_INSERT_ID();

    OPEN cur;
    alloc_loop: LOOP
        FETCH cur INTO v_unit, v_batch, v_qty;
        IF v_done = 1 OR v_remaining <= 0 THEN
            LEAVE alloc_loop;
        END IF;

        SET v_take = LEAST(v_qty, v_remaining);

        INSERT INTO shipment_item (shipment_id, batch_id, source_unit_id, quantity)
        VALUES (p_shipment_id, v_batch, v_unit, v_take);

        UPDATE inventory
        SET quantity = quantity - v_take
        WHERE unit_id = v_unit AND batch_id = v_batch;

        SET v_remaining = v_remaining - v_take;
    END LOOP;
    CLOSE cur;

    IF v_remaining > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient usable stock for this product at the source facility';
    END IF;

    COMMIT;
END$$

-- Receive a shipment into a storage unit at the destination
CREATE PROCEDURE sp_receive_shipment(
    IN p_shipment_id INT,
    IN p_dest_unit   INT
)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_dest INT;
    DECLARE v_temp VARCHAR(10);
    DECLARE v_unit_facility INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status, destination_facility_id, temp_status
    INTO v_status, v_dest, v_temp
    FROM shipment
    WHERE shipment_id = p_shipment_id
    FOR UPDATE;

    SELECT facility_id INTO v_unit_facility
    FROM storage_unit WHERE unit_id = p_dest_unit;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Shipment not found';
    ELSEIF v_status <> 'In Transit' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only shipments that are In Transit can be received';
    ELSEIF v_unit_facility IS NULL OR v_unit_facility <> v_dest THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Storage unit does not belong to the destination facility';
    END IF;

    -- Breached shipments arrive quarantined
    INSERT INTO inventory (unit_id, batch_id, quantity, stock_status)
    SELECT p_dest_unit, batch_id, quantity,
           IF(v_temp = 'Breached', 'Quarantined', 'Available')
    FROM shipment_item
    WHERE shipment_id = p_shipment_id
    ON DUPLICATE KEY UPDATE
        quantity = inventory.quantity + VALUES(quantity),
        stock_status = IF(VALUES(stock_status) = 'Quarantined',
                          'Quarantined', inventory.stock_status);

    UPDATE shipment
    SET status = 'Delivered', actual_arrival = NOW()
    WHERE shipment_id = p_shipment_id;

    COMMIT;
END$$

DELIMITER ;
