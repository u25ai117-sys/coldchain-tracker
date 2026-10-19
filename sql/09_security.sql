USE coldchain;

-- Roles
CREATE ROLE IF NOT EXISTS role_admin, role_manager, role_auditor;

-- Admin: everything in this database
GRANT ALL PRIVILEGES ON coldchain.* TO role_admin;

-- Warehouse Manager: reads operational data, creates and updates shipments and stock
GRANT SELECT ON coldchain.facility        TO role_manager;
GRANT SELECT ON coldchain.storage_unit    TO role_manager;
GRANT SELECT ON coldchain.product         TO role_manager;
GRANT SELECT ON coldchain.temperature_log TO role_manager;
GRANT SELECT ON coldchain.excursion_alert TO role_manager;
GRANT SELECT, INSERT, UPDATE ON coldchain.batch         TO role_manager;
GRANT SELECT, INSERT, UPDATE ON coldchain.inventory     TO role_manager;
GRANT SELECT, INSERT, UPDATE ON coldchain.shipment      TO role_manager;
GRANT SELECT, INSERT, UPDATE ON coldchain.shipment_item TO role_manager;
GRANT SELECT (user_id, username, full_name, email, role) ON coldchain.user_account TO role_manager;
GRANT EXECUTE ON PROCEDURE coldchain.sp_create_shipment  TO role_manager;
GRANT EXECUTE ON PROCEDURE coldchain.sp_receive_shipment TO role_manager;
GRANT SELECT ON coldchain.v_expiring_soon     TO role_manager;
GRANT SELECT ON coldchain.v_active_alerts     TO role_manager;
GRANT SELECT ON coldchain.v_stock_by_facility TO role_manager;

-- Quality Auditor: reads everything operational, resolves alerts, quarantines or releases stock
GRANT SELECT ON coldchain.facility        TO role_auditor;
GRANT SELECT ON coldchain.storage_unit    TO role_auditor;
GRANT SELECT ON coldchain.product         TO role_auditor;
GRANT SELECT ON coldchain.batch           TO role_auditor;
GRANT SELECT ON coldchain.inventory       TO role_auditor;
GRANT SELECT ON coldchain.shipment        TO role_auditor;
GRANT SELECT ON coldchain.shipment_item   TO role_auditor;
GRANT SELECT ON coldchain.temperature_log TO role_auditor;
GRANT SELECT ON coldchain.excursion_alert TO role_auditor;
GRANT SELECT (user_id, username, full_name, email, role) ON coldchain.user_account TO role_auditor;
GRANT UPDATE (end_time, status, resolved_by, resolved_at, resolution_note)
      ON coldchain.excursion_alert TO role_auditor;
GRANT UPDATE (status)       ON coldchain.batch     TO role_auditor;
GRANT UPDATE (stock_status) ON coldchain.inventory TO role_auditor;
GRANT SELECT ON coldchain.v_expiring_soon     TO role_auditor;
GRANT SELECT ON coldchain.v_active_alerts     TO role_auditor;
GRANT SELECT ON coldchain.v_stock_by_facility TO role_auditor;

-- Database users, one per role
CREATE USER IF NOT EXISTS 'cc_admin'@'localhost'   IDENTIFIED BY 'Admin@2026';
CREATE USER IF NOT EXISTS 'cc_manager'@'localhost' IDENTIFIED BY 'Manager@2026';
CREATE USER IF NOT EXISTS 'cc_auditor'@'localhost' IDENTIFIED BY 'Auditor@2026';

GRANT role_admin   TO 'cc_admin'@'localhost';
GRANT role_manager TO 'cc_manager'@'localhost';
GRANT role_auditor TO 'cc_auditor'@'localhost';

-- Without this, the role is NOT active when the user logs in
SET DEFAULT ROLE role_admin   TO 'cc_admin'@'localhost';
SET DEFAULT ROLE role_manager TO 'cc_manager'@'localhost';
SET DEFAULT ROLE role_auditor TO 'cc_auditor'@'localhost';
