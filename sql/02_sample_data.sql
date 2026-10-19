-- Sample data for Cold Chain Tracker (MySQL 8.0+)
-- Safe to re-run: it clears the tables first.

USE coldchain;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE excursion_alert;
TRUNCATE TABLE temperature_log;
TRUNCATE TABLE shipment_item;
TRUNCATE TABLE shipment;
TRUNCATE TABLE inventory;
TRUNCATE TABLE batch;
TRUNCATE TABLE product;
TRUNCATE TABLE storage_unit;
TRUNCATE TABLE facility;
TRUNCATE TABLE user_account;
SET FOREIGN_KEY_CHECKS = 1;

-- Users (demo passwords are stored as SHA-256 hashes)
INSERT INTO user_account (username, password_hash, full_name, email, role) VALUES
('admin',    SHA2('admin123',256),   'Jignesh Admin',  'admin@coldchain.in',    'Admin'),
('manager1', SHA2('manager123',256), 'Amit Sharma',    'amit@coldchain.in',     'Warehouse Manager'),
('auditor1', SHA2('auditor123',256), 'Priya Nair',     'priya@coldchain.in',    'Quality Auditor'),
('manager2', SHA2('manager123',256), 'Rohan Joshi',    'rohan@coldchain.in',    'Warehouse Manager');

-- Facilities (parent first, so the hierarchy is valid)
INSERT INTO facility (facility_name, facility_type, parent_facility_id, city, state) VALUES
('Bharat Biologics Plant',     'Manufacturer',      NULL, 'Pune',      'Maharashtra'),
('National Central Warehouse', 'Central Warehouse', 1,    'Mumbai',    'Maharashtra'),
('Gujarat State Warehouse',    'Central Warehouse', 2,    'Ahmedabad', 'Gujarat'),
('Surat District Store',       'District Store',    3,    'Surat',     'Gujarat'),
('Vadodara District Store',    'District Store',    3,    'Vadodara',  'Gujarat'),
('Civil Hospital Surat',       'Hospital',          4,    'Surat',     'Gujarat'),
('PHC Adajan',                 'PHC',               4,    'Surat',     'Gujarat'),
('SSG Hospital Vadodara',      'Hospital',          5,    'Vadodara',  'Gujarat'),
('PHC Karelibaug',             'PHC',               5,    'Vadodara',  'Gujarat');

-- Storage units
INSERT INTO storage_unit (facility_id, unit_name, unit_type, min_temp, max_temp, sensor_id) VALUES
(2, 'Cold Room A',       'Cold Room', 2,   8,   'SNS-001'),
(2, 'Deep Freezer A',    'Freezer',  -25, -15,  'SNS-002'),
(3, 'Cold Room A',       'Cold Room', 2,   8,   'SNS-003'),
(4, 'Vaccine Fridge 1',  'Fridge',    2,   8,   'SNS-004'),
(4, 'Vaccine Fridge 2',  'Fridge',    2,   8,   'SNS-005'),
(5, 'Cold Room A',       'Cold Room', 2,   8,   'SNS-006'),
(6, 'Vaccine Fridge 1',  'Fridge',    2,   8,   'SNS-007'),
(7, 'Vaccine Fridge 1',  'Fridge',    2,   8,   'SNS-008'),
(8, 'Vaccine Fridge 1',  'Fridge',    2,   8,   'SNS-009'),
(1, 'Plant Cold Room',   'Cold Room', 2,   8,   'SNS-010');

-- Products
INSERT INTO product (product_name, category, min_temp, max_temp, max_excursion_minutes, shelf_life_days, unit_price, reorder_level) VALUES
('Covishield Vaccine',        'Vaccine',  2,   8,   30, 365, 225.00, 500),
('Hepatitis B Vaccine',       'Vaccine',  2,   8,   30, 730,  45.00, 300),
('Oral Polio Vaccine (OPV)',  'Vaccine', -25, -15,  20, 730,  20.00, 400),
('Measles-Rubella Vaccine',   'Vaccine',  2,   8,   30, 730,  60.00, 300),
('Insulin (Regular)',         'Biologic', 2,   8,   60, 730, 150.00, 200),
('Rabies Vaccine',            'Vaccine',  2,   8,   30, 730, 300.00, 100);

-- Batches (dates are relative to today, so expiry data never goes stale)
INSERT INTO batch (product_id, batch_no, mfg_date, expiry_date, quantity_produced, status) VALUES
(1, 'CVS-2026-A01', DATE_SUB(CURDATE(), INTERVAL 60 DAY),  DATE_ADD(CURDATE(), INTERVAL 305 DAY), 50000, 'Active'),
(1, 'CVS-2026-A02', DATE_SUB(CURDATE(), INTERVAL 30 DAY),  DATE_ADD(CURDATE(), INTERVAL 335 DAY), 50000, 'Active'),
(2, 'HEP-2026-B01', DATE_SUB(CURDATE(), INTERVAL 90 DAY),  DATE_ADD(CURDATE(), INTERVAL 640 DAY), 20000, 'Active'),
(2, 'HEP-2025-B09', DATE_SUB(CURDATE(), INTERVAL 400 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY),  10000, 'Active'),
(3, 'OPV-2026-C01', DATE_SUB(CURDATE(), INTERVAL 45 DAY),  DATE_ADD(CURDATE(), INTERVAL 685 DAY), 30000, 'Active'),
(4, 'MR-2026-D01',  DATE_SUB(CURDATE(), INTERVAL 120 DAY), DATE_ADD(CURDATE(), INTERVAL 610 DAY), 25000, 'Active'),
(4, 'MR-2025-D07',  DATE_SUB(CURDATE(), INTERVAL 700 DAY), DATE_ADD(CURDATE(), INTERVAL 40 DAY),   8000, 'Active'),
(5, 'INS-2026-E01', DATE_SUB(CURDATE(), INTERVAL 75 DAY),  DATE_ADD(CURDATE(), INTERVAL 655 DAY), 15000, 'Active'),
(6, 'RAB-2026-F01', DATE_SUB(CURDATE(), INTERVAL 50 DAY),  DATE_ADD(CURDATE(), INTERVAL 680 DAY),  6000, 'Active'),
(1, 'CVS-2025-A00', DATE_SUB(CURDATE(), INTERVAL 380 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY),    5000, 'Expired');

-- Inventory (unit_id, batch_id, quantity)
INSERT INTO inventory (unit_id, batch_id, quantity) VALUES
(1, 1, 20000), (1, 2, 30000), (1, 3, 12000), (1, 4, 6000),
(1, 6, 15000), (1, 7, 5000),  (1, 8, 9000),  (1, 9, 4000), (1, 10, 3000),
(2, 5, 18000),
(3, 1, 8000),  (3, 3, 5000),  (3, 4, 2000),  (3, 6, 6000), (3, 8, 3000),
(4, 1, 3000),  (4, 3, 1500),  (4, 6, 2000),
(5, 8, 800),   (5, 9, 600),
(6, 1, 2500),  (6, 4, 700),   (6, 6, 1800),
(7, 1, 600),   (7, 3, 300),   (7, 9, 120),
(8, 3, 150),   (8, 6, 200),
(9, 1, 500),   (9, 8, 100),   (9, 9, 80);

-- Shipments (times are relative to now)
INSERT INTO shipment (source_facility_id, destination_facility_id, created_by, vehicle_reg_no, driver_name, sensor_id, dispatch_time, eta, actual_arrival, status) VALUES
(2, 3, 2, 'MH-01-AB-1234', 'Ramesh Patil', 'TRK-001', DATE_SUB(NOW(), INTERVAL 150 HOUR), DATE_SUB(NOW(), INTERVAL 139 HOUR), DATE_SUB(NOW(), INTERVAL 138 HOUR), 'Delivered'),
(3, 4, 2, 'GJ-05-XY-4321', 'Suresh Desai', 'TRK-002', DATE_SUB(NOW(), INTERVAL 100 HOUR), DATE_SUB(NOW(), INTERVAL 94 HOUR),  DATE_SUB(NOW(), INTERVAL 93 HOUR),  'Delivered'),
(4, 6, 4, 'GJ-05-CD-7788', 'Mahesh Shah',  'TRK-003', DATE_SUB(NOW(), INTERVAL 60 HOUR),  DATE_SUB(NOW(), INTERVAL 57 HOUR),  DATE_SUB(NOW(), INTERVAL 58 HOUR),  'Delivered'),
(3, 5, 4, 'GJ-01-EF-9900', 'Kiran Mehta',  'TRK-004', DATE_SUB(NOW(), INTERVAL 40 HOUR),  DATE_SUB(NOW(), INTERVAL 35 HOUR),  DATE_SUB(NOW(), INTERVAL 36 HOUR),  'Delivered'),
(4, 7, 2, 'GJ-05-CD-7788', 'Mahesh Shah',  'TRK-005', DATE_SUB(NOW(), INTERVAL 3 HOUR),   DATE_ADD(NOW(), INTERVAL 1 HOUR),   NULL,                               'In Transit'),
(2, 4, 2, 'MH-01-AB-1234', 'Ramesh Patil', 'TRK-006', NULL,                               NULL,                               NULL,                               'Created');

-- Shipment items (shipment_id, batch_id, source_unit_id, quantity)
INSERT INTO shipment_item (shipment_id, batch_id, source_unit_id, quantity) VALUES
(1, 1, 1, 8000), (1, 3, 1, 5000), (1, 4, 1, 2000), (1, 6, 1, 6000), (1, 8, 1, 3000),
(2, 1, 3, 3000), (2, 3, 3, 1500), (2, 6, 3, 2000),
(3, 1, 4, 600),  (3, 3, 4, 300),
(4, 1, 3, 2500), (4, 4, 3, 700),  (4, 6, 3, 1800),
(5, 1, 4, 400),
(6, 2, 1, 5000);
