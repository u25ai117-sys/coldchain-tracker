import os

import mysql.connector
from dotenv import load_dotenv

load_dotenv()

# Each application role connects to MySQL as its own database user,
# so the privileges granted in sql/09_security.sql are enforced by the database.
ROLE_LOGINS = {
    "Admin": ("cc_admin", "DB_ADMIN_PASSWORD"),
    "Warehouse Manager": ("cc_manager", "DB_MANAGER_PASSWORD"),
    "Quality Auditor": ("cc_auditor", "DB_AUDITOR_PASSWORD"),
}


def get_connection(role=None):
    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASSWORD")
    if role in ROLE_LOGINS:
        user, password_key = ROLE_LOGINS[role]
        password = os.getenv(password_key)
    return mysql.connector.connect(
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT")),
        database=os.getenv("DB_NAME"),
        user=user,
        password=password,
    )


def query_all(sql, params=None, role=None):
    conn = get_connection(role)
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        cur.close()
        return rows
    finally:
        conn.close()


def query_one(sql, params=None, role=None):
    rows = query_all(sql, params, role)
    return rows[0] if rows else None


def execute(sql, params=None, role=None):
    conn = get_connection(role)
    try:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        conn.commit()
        last_id = cur.lastrowid
        cur.close()
        return last_id
    finally:
        conn.close()
