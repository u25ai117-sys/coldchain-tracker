from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse
from mysql.connector import Error

from app.common import flash, guard, render
from app.db import execute, query_all, query_one

router = APIRouter()

ADMIN = ["Admin"]
WRITERS = ["Admin", "Warehouse Manager"]

FACILITY_TYPES = ["Manufacturer", "Central Warehouse", "District Store", "Hospital", "PHC"]
CATEGORIES = ["Vaccine", "Biologic", "Medicine"]
BATCH_STATUSES = ["Active", "Quarantined", "Expired", "Recalled"]


def opts(values):
    return [(v, v) for v in values]


def clean(value):
    if value is None:
        return None
    value = str(value).strip()
    return value if value != "" else None


def attempt(request, role, sql, params, ok_msg, ok_url, fail_url):
    """Run a write; show the database's own message if it refuses."""
    try:
        execute(sql, params, role=role)
        flash(request, ok_msg)
        return RedirectResponse(ok_url, status_code=303)
    except Error as e:
        flash(request, "Database refused the change: " + str(e.msg), "danger")
        return RedirectResponse(fail_url, status_code=303)


# ---------- field definitions ----------

def facility_fields(role, exclude=None):
    rows = query_all("SELECT facility_id, facility_name FROM facility ORDER BY facility_name", role=role)
    parents = [(r["facility_id"], r["facility_name"]) for r in rows if r["facility_id"] != exclude]
    return [
        {"name": "facility_name", "label": "Facility name", "type": "text", "required": True},
        {"name": "facility_type", "label": "Type", "type": "select", "options": opts(FACILITY_TYPES), "required": True},
        {"name": "parent_facility_id", "label": "Parent facility", "type": "select", "options": parents, "required": False},
        {"name": "city", "label": "City", "type": "text", "required": True},
        {"name": "state", "label": "State", "type": "text", "required": True},
    ]


def product_fields(role, exclude=None):
    return [
        {"name": "product_name", "label": "Product name", "type": "text", "required": True},
        {"name": "category", "label": "Category", "type": "select", "options": opts(CATEGORIES), "required": True},
        {"name": "min_temp", "label": "Minimum safe temperature (C)", "type": "number", "step": "0.1", "required": True},
        {"name": "max_temp", "label": "Maximum safe temperature (C)", "type": "number", "step": "0.1", "required": True},
        {"name": "max_excursion_minutes", "label": "Allowed excursion (minutes)", "type": "number", "required": True},
        {"name": "shelf_life_days", "label": "Shelf life (days)", "type": "number", "required": True},
        {"name": "unit_price", "label": "Unit price", "type": "number", "step": "0.01", "required": True},
        {"name": "reorder_level", "label": "Reorder level", "type": "number", "required": True},
    ]


def batch_fields(role, exclude=None):
    rows = query_all("SELECT product_id, product_name FROM product ORDER BY product_name", role=role)
    products = [(r["product_id"], r["product_name"]) for r in rows]
    return [
        {"name": "product_id", "label": "Product", "type": "select", "options": products, "required": True},
        {"name": "batch_no", "label": "Batch number", "type": "text", "required": True},
        {"name": "mfg_date", "label": "Manufacturing date", "type": "date", "required": True},
        {"name": "expiry_date", "label": "Expiry date", "type": "date", "required": True},
        {"name": "quantity_produced", "label": "Quantity produced", "type": "number", "required": True},
        {"name": "status", "label": "Status", "type": "select", "options": opts(BATCH_STATUSES), "required": True},
    ]


# ---------- generic CRUD pages ----------

def register(base, table, id_col, title, singular, columns, list_sql,
             fields_fn, write_roles, delete_roles):

    @router.get(base)
    def list_view(request: Request):
        user, redirect = guard(request)
        if redirect:
            return redirect
        role = user["role"]
        rows = query_all(list_sql, role=role)
        return render(request, "list.html", title=title, base=base, id_key=id_col,
                      columns=columns, rows=rows,
                      can_add=role in write_roles, can_edit=role in write_roles,
                      can_delete=role in delete_roles)

    @router.get(base + "/new")
    def new_view(request: Request):
        user, redirect = guard(request, write_roles)
        if redirect:
            return redirect
        return render(request, "form.html", title="Add " + singular, action=base + "/new",
                      cancel=base, fields=fields_fn(user["role"]), item=None)

    @router.post(base + "/new")
    async def create(request: Request):
        user, redirect = guard(request, write_roles)
        if redirect:
            return redirect
        form = await request.form()
        names = [f["name"] for f in fields_fn(user["role"])]
        values = [clean(form.get(n)) for n in names]
        sql = "INSERT INTO %s (%s) VALUES (%s)" % (
            table, ", ".join(names), ", ".join(["%s"] * len(names)))
        return attempt(request, user["role"], sql, values,
                       singular + " added.", base, base + "/new")

    @router.get(base + "/{item_id}/edit")
    def edit_view(request: Request, item_id: int):
        user, redirect = guard(request, write_roles)
        if redirect:
            return redirect
        item = query_one("SELECT * FROM %s WHERE %s = %%s" % (table, id_col),
                         (item_id,), role=user["role"])
        if not item:
            flash(request, "Record not found.", "danger")
            return RedirectResponse(base, status_code=303)
        return render(request, "form.html", title="Edit " + singular,
                      action="%s/%d/edit" % (base, item_id), cancel=base,
                      fields=fields_fn(user["role"], item_id), item=item)

    @router.post(base + "/{item_id}/edit")
    async def update(request: Request, item_id: int):
        user, redirect = guard(request, write_roles)
        if redirect:
            return redirect
        form = await request.form()
        names = [f["name"] for f in fields_fn(user["role"], item_id)]
        values = [clean(form.get(n)) for n in names] + [item_id]
        sql = "UPDATE %s SET %s WHERE %s = %%s" % (
            table, ", ".join(n + " = %s" for n in names), id_col)
        return attempt(request, user["role"], sql, values, singular + " updated.",
                       base, "%s/%d/edit" % (base, item_id))

    @router.post(base + "/{item_id}/delete")
    def delete(request: Request, item_id: int):
        user, redirect = guard(request, delete_roles)
        if redirect:
            return redirect
        sql = "DELETE FROM %s WHERE %s = %%s" % (table, id_col)
        return attempt(request, user["role"], sql, (item_id,),
                       singular + " deleted.", base, base)


register(
    base="/facilities", table="facility", id_col="facility_id",
    title="Facilities", singular="facility",
    columns=[("facility_id", "ID"), ("facility_name", "Name"), ("facility_type", "Type"),
             ("parent", "Parent"), ("city", "City"), ("state", "State")],
    list_sql="SELECT f.facility_id, f.facility_name, f.facility_type, p.facility_name AS parent, "
             "f.city, f.state FROM facility f "
             "LEFT JOIN facility p ON p.facility_id = f.parent_facility_id ORDER BY f.facility_id",
    fields_fn=facility_fields, write_roles=ADMIN, delete_roles=ADMIN,
)

register(
    base="/products", table="product", id_col="product_id",
    title="Products", singular="product",
    columns=[("product_id", "ID"), ("product_name", "Name"), ("category", "Category"),
             ("min_temp", "Min C"), ("max_temp", "Max C"),
             ("max_excursion_minutes", "Excursion min"), ("shelf_life_days", "Shelf life"),
             ("unit_price", "Price"), ("reorder_level", "Reorder")],
    list_sql="SELECT * FROM product ORDER BY product_id",
    fields_fn=product_fields, write_roles=ADMIN, delete_roles=ADMIN,
)

register(
    base="/batches", table="batch", id_col="batch_id",
    title="Batches", singular="batch",
    columns=[("batch_id", "ID"), ("product_name", "Product"), ("batch_no", "Batch no."),
             ("mfg_date", "Made"), ("expiry_date", "Expires"), ("days_left", "Days left"),
             ("quantity_produced", "Produced"), ("status", "Status")],
    list_sql="SELECT b.batch_id, p.product_name, b.batch_no, b.mfg_date, b.expiry_date, "
             "DATEDIFF(b.expiry_date, CURDATE()) AS days_left, b.quantity_produced, b.status "
             "FROM batch b JOIN product p ON p.product_id = b.product_id ORDER BY b.expiry_date",
    fields_fn=batch_fields, write_roles=WRITERS, delete_roles=ADMIN,
)


# ---------- inventory ----------

@router.get("/inventory")
def inventory_view(request: Request):
    user, redirect = guard(request)
    if redirect:
        return redirect
    role = user["role"]
    rows = query_all(
        "SELECT f.facility_name, u.unit_name, p.product_name, b.batch_no, b.expiry_date, "
        "i.quantity, i.stock_status "
        "FROM inventory i "
        "JOIN storage_unit u ON u.unit_id = i.unit_id "
        "JOIN facility f ON f.facility_id = u.facility_id "
        "JOIN batch b ON b.batch_id = i.batch_id "
        "JOIN product p ON p.product_id = b.product_id "
        "ORDER BY f.facility_name, u.unit_name, b.expiry_date", role=role)
    can_add = role in WRITERS
    units, batches = [], []
    if can_add:
        units = query_all(
            "SELECT u.unit_id, CONCAT(f.facility_name, ' / ', u.unit_name) AS label "
            "FROM storage_unit u JOIN facility f ON f.facility_id = u.facility_id "
            "ORDER BY label", role=role)
        batches = query_all(
            "SELECT b.batch_id, CONCAT(b.batch_no, ' (', p.product_name, ')') AS label "
            "FROM batch b JOIN product p ON p.product_id = b.product_id "
            "WHERE b.status = 'Active' AND b.expiry_date > CURDATE() ORDER BY label", role=role)
    return render(request, "inventory.html", rows=rows, units=units,
                  batches=batches, can_add=can_add)


@router.post("/inventory/add")
async def inventory_add(request: Request):
    user, redirect = guard(request, WRITERS)
    if redirect:
        return redirect
    form = await request.form()
    try:
        qty = int(form.get("quantity"))
        if qty <= 0:
            raise ValueError
    except (TypeError, ValueError):
        flash(request, "Quantity must be a positive whole number.", "danger")
        return RedirectResponse("/inventory", status_code=303)
    sql = ("INSERT INTO inventory (unit_id, batch_id, quantity) VALUES (%s, %s, %s) "
           "ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity)")
    return attempt(request, user["role"], sql,
                   (form.get("unit_id"), form.get("batch_id"), qty),
                   "Stock received into the storage unit.", "/inventory", "/inventory")
