# Cold Chain Vaccine and Medicine Logistics Tracker

A database-driven system that tracks vaccine and medicine batches from
manufacturer to health facility, logs temperature readings, detects
excursions automatically, and blocks unsafe shipments.

Course: Database Management Systems (AI203), SVNIT Surat

## Features
- Role-based login (Admin, Warehouse Manager, Quality Auditor), enforced in the app and in MySQL
- CRUD for facilities, products, batches, and inventory
- Shipments dispatched by FEFO (first expired, first out) inside a transaction
- Triggers that raise temperature alerts, quarantine stock, and block unsafe shipments
- Alert review and resolution, plus reports with charts

## Tech stack
MySQL 8.0, Python, FastAPI, Jinja2, Bootstrap 5, Chart.js

## Folder structure
- sql/          schema, triggers, procedures, views, queries, security
- app/          FastAPI application
- data/         temperature sensor simulator
- docs/         report, ER diagram
- screenshots/  UI and test screenshots



## Note
These are demo credentials for a local project only. Sample data is fictional.

## Analytical queries
Thirteen queries (JOINs, GROUP BY and HAVING, window functions, recursive CTE,
subqueries) are in sql/07_queries.sql.
