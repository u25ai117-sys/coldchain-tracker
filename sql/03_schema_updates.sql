USE coldchain;

ALTER TABLE inventory
    ADD COLUMN stock_status ENUM('Available','Quarantined') NOT NULL DEFAULT 'Available';

ALTER TABLE shipment
    ADD COLUMN temp_status ENUM('OK','Breached') NOT NULL DEFAULT 'OK';
