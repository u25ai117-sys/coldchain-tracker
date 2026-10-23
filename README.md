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

## How to run

1. Install Python 3.10+ and MySQL 8.0+.

2. Create a virtual environment and install packages:

        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt

3. Create the database:

        mysql -u root -p -e "CREATE DATABASE coldchain CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

4. Create a file named .env in the project root:

        DB_HOST=localhost
        DB_PORT=3306
        DB_NAME=coldchain
        DB_USER=root
        DB_PASSWORD='your_mysql_root_password'
        SECRET_KEY=any_long_random_string
        DB_ADMIN_PASSWORD='Admin@2026'
        DB_MANAGER_PASSWORD='Manager@2026'
        DB_AUDITOR_PASSWORD='Auditor@2026'

5. Load the database scripts in this order:

        mysql -u root -p coldchain < sql/01_schema.sql
        mysql -u root -p coldchain < sql/03_schema_updates.sql
        mysql -u root -p coldchain < sql/02_sample_data.sql
        mysql -u root -p coldchain < sql/04_triggers.sql
        mysql -u root -p coldchain < sql/05_procedures.sql
        mysql -u root -p coldchain < sql/06_views.sql
        mysql -u root -p coldchain < sql/08_indexing.sql
        mysql -u root -p coldchain < sql/09_security.sql

6. Generate temperature readings (this fires the alert trigger):

        python data/simulate_temperatures.py

7. Start the app and open http://127.0.0.1:8000

        uvicorn app.main:app --reload

## Demo logins
| Username | Password | Role |
|---|---|---|
| admin | admin123 | Admin |
| manager1 | manager123 | Warehouse Manager |
| auditor1 | auditor123 | Quality Auditor |

These are demo credentials for a local project only. Sample data is fictional.

## Analytical queries
Thirteen queries (JOINs, GROUP BY and HAVING, window functions, recursive CTE,
subqueries) are in sql/07_queries.sql.
