# Screenshot checklist (take all in one session, from reset data)

Reset first:
  mysql -u root -p coldchain < sql/02_sample_data.sql
  python data/simulate_temperatures.py

Terminal (run PS1='$ ' first):
- 04_alert_table, 04_quarantine_status
- 04_test_expired_batch, 04_test_quarantined_stock, 04_test_same_facility
- 05_fefo_shipment, 05_rollback_proof, 05_receive_shipment, 05_receive_errors
- 05_views, 05_concurrency_wait, 05_concurrency_result
- 06_q2, 06_q6, 06_q7, 06_q8, 06_q9, 06_q10
- 06_explain_before, 06_explain_after, 06_index_after
- 07_manager_denied_hash, 07_manager_denied_delete, 07_auditor_denied_insert, 07_auditor_allowed_update, 07_grants

Browser:
- 08_login, 08_login_error, 08_dashboard_admin, 08_dashboard_manager, 08_dashboard_auditor
- 09_facilities_admin, 09_facility_added, 09_delete_refused_fk
- 09_batch_check_error, 09_batch_duplicate_error, 09_product_check_error
- 09_facilities_manager_readonly, 09_inventory_receive, 09_role_blocked
