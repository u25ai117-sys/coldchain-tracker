from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse
from mysql.connector import Error

from app.common import flash, guard, render
from app.db import get_connection, query_all, query_one

router = APIRouter()

WRITERS = ["Admin", "Warehouse Manager"]


def call_proc(role, name, args):
    """Call a stored procedure as the logged-in role's database user."""
    conn = get_connection(role)
    try:
        cur = conn.cursor()
        result = cur.callproc(name, args)
        conn.commit()
        cur.close()
        return result
    finally:
        conn.close()


@router.get("/shipments")
def shipment_list(request: Request):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    rows = query_all(
        "SELECT s.shipment_id, fs.facility_name AS source, fd.facility_name AS destination, "
        "s.vehicle_reg_no, s.driver_name, s.status, s.temp_status, s.dispatch_time, s.eta, "
        "s.actual_arrival, "
        "(SELECT COALESCE(SUM(si.quantity), 0) FROM shipment_item si "
        " WHERE si.shipment_id = s.shipment_id) AS units "
        "FROM shipment s "
        "JOIN facility fs ON fs.facility_id = s.source_facility_id "
        "JOIN facility fd ON fd.facility_id = s.destination_facility_id "
        "ORDER BY s.shipment_id DESC",
        role=user["role"],
    )
    return render(request, "shipments.html", rows=rows)


@router.get("/shipments/new")
def shipment_new(request: Request):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    role = user["role"]
    facilities = query_all(
        "SELECT facility_id, facility_name FROM facility ORDER BY facility_name", role=role)
    products = query_all(
        "SELECT product_id, product_name FROM product ORDER BY product_name", role=role)
    return render(request, "shipment_new.html", facilities=facilities, products=products)


@router.post("/shipments/new")
async def shipment_create(request: Request):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    form = await request.form()
    try:
        args = [
            int(form.get("source")),
            int(form.get("destination")),
            user["user_id"],
            form.get("vehicle").strip(),
            form.get("driver").strip(),
            form.get("sensor").strip(),
            int(form.get("product")),
            int(form.get("quantity")),
            int(form.get("eta_hours")),
        ]
        if args[7] <= 0 or args[8] <= 0 or not all(args[3:6]):
            raise ValueError
    except (TypeError, ValueError, AttributeError):
        flash(request, "Please fill every field with valid values.", "danger")
        return RedirectResponse("/shipments/new", status_code=303)

    try:
        result = call_proc(user["role"], "sp_create_shipment", args + [0])
    except Error as e:
        flash(request, "Database refused the shipment: " + str(e.msg), "danger")
        return RedirectResponse("/shipments/new", status_code=303)

    new_id = result[-1]
    flash(request, "Shipment #%s created and dispatched. Stock was picked by FEFO." % new_id)
    return RedirectResponse("/shipments/%s" % new_id, status_code=303)


@router.get("/shipments/{shipment_id}")
def shipment_detail(request: Request, shipment_id: int):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    role = user["role"]
    shipment = query_one(
        "SELECT s.*, fs.facility_name AS source, fd.facility_name AS destination, "
        "u.full_name AS created_by_name "
        "FROM shipment s "
        "JOIN facility fs ON fs.facility_id = s.source_facility_id "
        "JOIN facility fd ON fd.facility_id = s.destination_facility_id "
        "JOIN user_account u ON u.user_id = s.created_by "
        "WHERE s.shipment_id = %s",
        (shipment_id,), role=role)
    if not shipment:
        flash(request, "Shipment not found.", "danger")
        return RedirectResponse("/shipments", status_code=303)

    items = query_all(
        "SELECT p.product_name, b.batch_no, b.expiry_date, si.quantity, "
        "CONCAT(f.facility_name, ' / ', su.unit_name) AS from_unit "
        "FROM shipment_item si "
        "JOIN batch b ON b.batch_id = si.batch_id "
        "JOIN product p ON p.product_id = b.product_id "
        "JOIN storage_unit su ON su.unit_id = si.source_unit_id "
        "JOIN facility f ON f.facility_id = su.facility_id "
        "WHERE si.shipment_id = %s ORDER BY b.expiry_date",
        (shipment_id,), role=role)
    temps = query_one(
        "SELECT COUNT(*) AS readings, MIN(temperature) AS min_t, "
        "MAX(temperature) AS max_t, ROUND(AVG(temperature), 2) AS avg_t "
        "FROM temperature_log WHERE shipment_id = %s",
        (shipment_id,), role=role)
    alerts = query_all(
        "SELECT alert_id, start_time, end_time, peak_temp, severity, status "
        "FROM excursion_alert WHERE shipment_id = %s ORDER BY start_time",
        (shipment_id,), role=role)
    dest_units = []
    if shipment["status"] == "In Transit":
        dest_units = query_all(
            "SELECT unit_id, unit_name FROM storage_unit "
            "WHERE facility_id = %s ORDER BY unit_name",
            (shipment["destination_facility_id"],), role=role)
    return render(request, "shipment_detail.html", s=shipment, items=items,
                  temps=temps, alerts=alerts, dest_units=dest_units)


@router.post("/shipments/{shipment_id}/receive")
async def shipment_receive(request: Request, shipment_id: int):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    form = await request.form()
    back = "/shipments/%d" % shipment_id
    try:
        unit_id = int(form.get("unit_id"))
    except (TypeError, ValueError):
        flash(request, "Choose a storage unit.", "danger")
        return RedirectResponse(back, status_code=303)
    try:
        call_proc(user["role"], "sp_receive_shipment", [shipment_id, unit_id])
    except Error as e:
        flash(request, "Database refused the receipt: " + str(e.msg), "danger")
        return RedirectResponse(back, status_code=303)
    flash(request, "Shipment received into stock.")
    return RedirectResponse(back, status_code=303)
