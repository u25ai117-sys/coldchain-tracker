-- Cold Chain Vaccine and Medicine Logistics Tracker
-- Schema (MySQL 8.0+)

USE coldchain;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS excursion_alert;
DROP TABLE IF EXISTS temperature_log;
DROP TABLE IF EXISTS shipment_item;
DROP TABLE IF EXISTS shipment;
DROP TABLE IF EXISTS inventory;
DROP TABLE IF EXISTS batch;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS storage_unit;
DROP TABLE IF EXISTS facility;
DROP TABLE IF EXISTS user_account;
SET FOREIGN_KEY_CHECKS = 1;

-- 1. Users and roles
CREATE TABLE user_account (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    full_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(100) NOT NULL UNIQUE,
    role           ENUM('Admin','Warehouse Manager','Quality Auditor') NOT NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Facilities (self-referencing hierarchy)
CREATE TABLE facility (
    facility_id         INT AUTO_INCREMENT PRIMARY KEY,
    facility_name       VARCHAR(100) NOT NULL,
    facility_type       ENUM('Manufacturer','Central Warehouse','District Store','Hospital','PHC') NOT NULL,
    parent_facility_id  INT NULL,
    city                VARCHAR(60)  NOT NULL,
    state               VARCHAR(60)  NOT NULL,
    created_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (facility_name, city),
    FOREIGN KEY (parent_facility_id) REFERENCES facility(facility_id)
);

-- 3. Storage units (fridges, freezers)
CREATE TABLE storage_unit (
    unit_id      INT AUTO_INCREMENT PRIMARY KEY,
    facility_id  INT NOT NULL,
    unit_name    VARCHAR(60) NOT NULL,
    unit_type    ENUM('Fridge','Freezer','Cold Room') NOT NULL,
    min_temp     DECIMAL(5,2) NOT NULL,
    max_temp     DECIMAL(5,2) NOT NULL,
    sensor_id    VARCHAR(30)  NOT NULL UNIQUE,
    UNIQUE (facility_id, unit_name),
    CHECK (min_temp < max_temp),
    FOREIGN KEY (facility_id) REFERENCES facility(facility_id)
);

-- 4. Products
CREATE TABLE product (
    product_id             INT AUTO_INCREMENT PRIMARY KEY,
    product_name           VARCHAR(100) NOT NULL UNIQUE,
    category               ENUM('Vaccine','Biologic','Medicine') NOT NULL,
    min_temp               DECIMAL(5,2) NOT NULL,
    max_temp               DECIMAL(5,2) NOT NULL,
    max_excursion_minutes  INT NOT NULL DEFAULT 30,
    shelf_life_days        INT NOT NULL,
    unit_price             DECIMAL(10,2) NOT NULL,
    reorder_level          INT NOT NULL DEFAULT 100,
    CHECK (min_temp < max_temp),
    CHECK (max_excursion_minutes >= 0),
    CHECK (shelf_life_days > 0),
    CHECK (unit_price >= 0),
    CHECK (reorder_level >= 0)
);

-- 5. Batches
CREATE TABLE batch (
    batch_id           INT AUTO_INCREMENT PRIMARY KEY,
    product_id         INT NOT NULL,
    batch_no           VARCHAR(40) NOT NULL,
    mfg_date           DATE NOT NULL,
    expiry_date        DATE NOT NULL,
    quantity_produced  INT NOT NULL,
    status             ENUM('Active','Quarantined','Expired','Recalled') NOT NULL DEFAULT 'Active',
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (product_id, batch_no),
    CHECK (expiry_date > mfg_date),
    CHECK (quantity_produced > 0),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- 6. Inventory (batch stored in a unit)
CREATE TABLE inventory (
    unit_id       INT NOT NULL,
    batch_id      INT NOT NULL,
    quantity      INT NOT NULL,
    last_updated  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (unit_id, batch_id),
    CHECK (quantity >= 0),
    FOREIGN KEY (unit_id)  REFERENCES storage_unit(unit_id),
    FOREIGN KEY (batch_id) REFERENCES batch(batch_id)
);

-- 7. Shipments
CREATE TABLE shipment (
    shipment_id             INT AUTO_INCREMENT PRIMARY KEY,
    source_facility_id      INT NOT NULL,
    destination_facility_id INT NOT NULL,
    created_by              INT NOT NULL,
    vehicle_reg_no          VARCHAR(20) NOT NULL,
    driver_name             VARCHAR(100) NOT NULL,
    sensor_id               VARCHAR(30) NOT NULL,
    dispatch_time           DATETIME NULL,
    eta                     DATETIME NULL,
    actual_arrival          DATETIME NULL,
    status                  ENUM('Created','In Transit','Delivered','Cancelled') NOT NULL DEFAULT 'Created',
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_facility_id)      REFERENCES facility(facility_id),
    FOREIGN KEY (destination_facility_id) REFERENCES facility(facility_id),
    FOREIGN KEY (created_by)              REFERENCES user_account(user_id)
);

-- 8. Shipment items
CREATE TABLE shipment_item (
    shipment_id     INT NOT NULL,
    batch_id        INT NOT NULL,
    source_unit_id  INT NOT NULL,
    quantity        INT NOT NULL,
    PRIMARY KEY (shipment_id, batch_id),
    CHECK (quantity > 0),
    FOREIGN KEY (shipment_id)    REFERENCES shipment(shipment_id),
    FOREIGN KEY (batch_id)       REFERENCES batch(batch_id),
    FOREIGN KEY (source_unit_id) REFERENCES storage_unit(unit_id)
);

-- 9. Temperature log (from a storage unit OR a shipment)
CREATE TABLE temperature_log (
    log_id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    sensor_id    VARCHAR(30)  NOT NULL,
    unit_id      INT NULL,
    shipment_id  INT NULL,
    recorded_at  DATETIME     NOT NULL,
    temperature  DECIMAL(5,2) NOT NULL,
    humidity     DECIMAL(5,2) NULL,
    FOREIGN KEY (unit_id)     REFERENCES storage_unit(unit_id),
    FOREIGN KEY (shipment_id) REFERENCES shipment(shipment_id)
);

-- 10. Excursion alerts
CREATE TABLE excursion_alert (
    alert_id         INT AUTO_INCREMENT PRIMARY KEY,
    unit_id          INT NULL,
    shipment_id      INT NULL,
    batch_id         INT NULL,
    start_time       DATETIME NOT NULL,
    end_time         DATETIME NULL,
    peak_temp        DECIMAL(5,2) NOT NULL,
    severity         ENUM('Low','Medium','High','Critical') NOT NULL,
    status           ENUM('Open','Under Review','Resolved') NOT NULL DEFAULT 'Open',
    resolved_by      INT NULL,
    resolved_at      DATETIME NULL,
    resolution_note  VARCHAR(255) NULL,
    FOREIGN KEY (unit_id)     REFERENCES storage_unit(unit_id),
    FOREIGN KEY (shipment_id) REFERENCES shipment(shipment_id),
    FOREIGN KEY (batch_id)    REFERENCES batch(batch_id),
    FOREIGN KEY (resolved_by) REFERENCES user_account(user_id)
);
