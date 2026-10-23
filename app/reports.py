from datetime import date, datetime
from decimal import Decimal

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.common import guard, render
from app.db import query_all, query_one

router = APIRouter()

VIEWERS = ["Admin", "Quality Auditor"]


def plain(rows):
    """Make query results safe to put into JSON."""
    out = []
    for r in rows:
        item = {}
        for k, v in r.items():
            if isinstance(v, Decimal):
                v = float(v)
            elif isinstance(v, (datetime, date)):
                v = str(v)
            item[k] = v
        out.append(item)
    return out


@router.get("/reports")
def reports(request: Request):
    user, redirect = guard(request, VIEWERS)
    if redirect:
        return redirect
    role = user["role"]

    stock = plain(query_all(
        "SELECT facility_name, SUM(total_qty) AS total_qty, SUM(usable_qty) AS usable_qty "
        "FROM v_stock_by_facility GROUP BY facility_id, facility_name ORDER BY facility_id",
        role=role))

    compliance = plain(query_all(
        "SELECT CONCAT(f.facility_name, ' / ', u.unit_name) AS unit_label, "
        "COUNT(*) AS readings, "
        "ROUND(100 * SUM(l.temperature BETWEEN u.min_temp AND u.max_temp) / COUNT(*), 2) AS compliance_pct "
        "FROM temperature_log l "
        "JOIN storage_unit u ON u.unit_id = l.unit_id "
        "JOIN facility f ON f.facility_id = u.facility_id "
        "GROUP BY u.unit_id, f.facility_name, u.unit_name "
        "ORDER BY compliance_pct ASC",
        role=role))

    severity = plain(query_all(
        "SELECT severity, COUNT(*) AS alerts FROM excursion_alert "
        "GROUP BY severity ORDER BY FIELD(severity, 'Critical', 'High', 'Medium', 'Low')",
        role=role))

    expiring = plain(query_all(
        "SELECT facility_name, product_name, batch_no, expiry_date, days_left, quantity "
        "FROM v_expiring_soon ORDER BY days_left",
        role=role))

    unusable = plain(query_all(
        "SELECT f.facility_name, ROUND(SUM(i.quantity * p.unit_price), 2) AS unusable_value, "
        "RANK() OVER (ORDER BY SUM(i.quantity * p.unit_price) DESC) AS value_rank "
        "FROM inventory i "
        "JOIN storage_unit u ON u.unit_id = i.unit_id "
        "JOIN facility f ON f.facility_id = u.facility_id "
        "JOIN batch b ON b.batch_id = i.batch_id "
        "JOIN product p ON p.product_id = b.product_id "
        "WHERE i.quantity > 0 "
        "AND (i.stock_status = 'Quarantined' OR b.expiry_date <= CURDATE() OR b.status <> 'Active') "
        "GROUP BY f.facility_id, f.facility_name ORDER BY value_rank",
        role=role))

    units = query_all(
        "SELECT u.unit_id, CONCAT(f.facility_name, ' / ', u.unit_name) AS label "
        "FROM storage_unit u JOIN facility f ON f.facility_id = u.facility_id ORDER BY label",
        role=role)

    return render(request, "reports.html", stock=stock, compliance=compliance,
                  severity=severity, expiring=expiring, unusable=unusable, units=units)


@router.get("/reports/api/temperature/{unit_id}")
def temperature_series(request: Request, unit_id: int):
    user, redirect = guard(request, VIEWERS)
    if redirect:
        return JSONResponse({"error": "not allowed"}, status_code=403)
    role = user["role"]

    unit = query_one(
        "SELECT unit_name, min_temp, max_temp FROM storage_unit WHERE unit_id = %s",
        (unit_id,), role=role)
    if not unit:
        return JSONResponse({"error": "unit not found"}, status_code=404)

    rows = plain(query_all(
        "SELECT recorded_at, temperature FROM temperature_log "
        "WHERE unit_id = %s AND recorded_at >= "
        "(SELECT MAX(recorded_at) - INTERVAL 24 HOUR FROM temperature_log WHERE unit_id = %s) "
        "ORDER BY recorded_at",
        (unit_id, unit_id), role=role))

    return {
        "unit": unit["unit_name"],
        "min": float(unit["min_temp"]),
        "max": float(unit["max_temp"]),
        "labels": [r["recorded_at"][5:16] for r in rows],
        "temps": [r["temperature"] for r in rows],
    }
