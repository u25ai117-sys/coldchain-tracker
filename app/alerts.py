from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse
from mysql.connector import Error

from app.common import flash, guard, render
from app.db import get_connection, query_all, query_one

router = APIRouter()

REVIEWERS = ["Admin", "Quality Auditor"]


@router.get("/alerts")
def alert_list(request: Request, status: str = "open"):
    user, redirect = guard(request, REVIEWERS)
    if redirect:
        return redirect

    where = ""
    if status == "open":
        where = "WHERE a.status <> 'Resolved' "
    elif status == "resolved":
        where = "WHERE a.status = 'Resolved' "
    else:
        status = "all"

    rows = query_all(
        "SELECT a.alert_id, a.unit_id, a.shipment_id, "
        "COALESCE(CONCAT(f.facility_name, ' / ', u.unit_name), "
        "         CONCAT('Shipment #', a.shipment_id)) AS location, "
        "a.start_time, a.end_time, "
        "TIMESTAMPDIFF(MINUTE, a.start_time, COALESCE(a.end_time, NOW())) AS duration_min, "
        "a.peak_temp, a.severity, a.status, a.resolution_note, r.full_name AS resolved_by_name "
        "FROM excursion_alert a "
        "LEFT JOIN storage_unit u ON u.unit_id = a.unit_id "
        "LEFT JOIN facility f ON f.facility_id = u.facility_id "
        "LEFT JOIN user_account r ON r.user_id = a.resolved_by "
        + where +
        "ORDER BY FIELD(a.status, 'Open', 'Under Review', 'Resolved'), a.start_time DESC",
        role=user["role"],
    )
    return render(request, "alerts.html", rows=rows, status=status)


@router.post("/alerts/{alert_id}/review")
def alert_review(request: Request, alert_id: int):
    user, redirect = guard(request, REVIEWERS)
    if redirect:
        return redirect
    try:
        conn = get_connection(user["role"])
        cur = conn.cursor()
        cur.execute(
            "UPDATE excursion_alert SET status = 'Under Review' "
            "WHERE alert_id = %s AND status = 'Open'", (alert_id,))
        changed = cur.rowcount
        conn.commit()
        cur.close()
        conn.close()
    except Error as e:
        flash(request, "Database refused the change: " + str(e.msg), "danger")
        return RedirectResponse("/alerts", status_code=303)
    if changed:
        flash(request, "Alert #%d is now under review." % alert_id)
    else:
        flash(request, "Alert #%d was not open." % alert_id, "warning")
    return RedirectResponse("/alerts", status_code=303)


@router.post("/alerts/{alert_id}/resolve")
async def alert_resolve(request: Request, alert_id: int):
    user, redirect = guard(request, REVIEWERS)
    if redirect:
        return redirect
    form = await request.form()
    decision = form.get("decision")
    note = (form.get("note") or "").strip()
    if decision not in ("accept", "discard") or not note:
        flash(request, "Choose a decision and write a short note.", "danger")
        return RedirectResponse("/alerts", status_code=303)

    alert = query_one(
        "SELECT alert_id, unit_id, status FROM excursion_alert WHERE alert_id = %s",
        (alert_id,), role=user["role"])
    if not alert or alert["status"] == "Resolved":
        flash(request, "Alert not found or already resolved.", "warning")
        return RedirectResponse("/alerts", status_code=303)

    label = "Accepted" if decision == "accept" else "Discarded"
    full_note = ("[%s] %s" % (label, note))[:250]

    conn = None
    try:
        conn = get_connection(user["role"])
        cur = conn.cursor()
        conn.start_transaction()
        cur.execute(
            "UPDATE excursion_alert SET status = 'Resolved', resolved_by = %s, "
            "resolved_at = NOW(), end_time = COALESCE(end_time, NOW()), "
            "resolution_note = %s WHERE alert_id = %s",
            (user["user_id"], full_note, alert_id))
        released = 0
        if decision == "accept" and alert["unit_id"] is not None:
            cur.execute(
                "UPDATE inventory SET stock_status = 'Available' "
                "WHERE unit_id = %s AND stock_status = 'Quarantined'",
                (alert["unit_id"],))
            released = cur.rowcount
        conn.commit()
        cur.close()
    except Error as e:
        if conn:
            conn.rollback()
        flash(request, "Database refused the change: " + str(e.msg), "danger")
        return RedirectResponse("/alerts", status_code=303)
    finally:
        if conn:
            conn.close()

    msg = "Alert #%d resolved (%s)." % (alert_id, label.lower())
    if released:
        msg += " %d stock line(s) released from quarantine." % released
    flash(request, msg)
    return RedirectResponse("/alerts", status_code=303)
