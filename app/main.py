import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, Form, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from app.db import query_all, query_one

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent

app = FastAPI(title="Cold Chain Tracker")
app.add_middleware(SessionMiddleware, secret_key=os.getenv("SECRET_KEY"))
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")


def current_user(request: Request):
    return request.session.get("user")


@app.get("/")
def home(request: Request):
    if current_user(request):
        return RedirectResponse("/dashboard", status_code=303)
    return RedirectResponse("/login", status_code=303)


@app.get("/login")
def login_page(request: Request):
    return templates.TemplateResponse(
        request=request, name="login.html", context={"error": None}
    )


@app.post("/login")
def login(request: Request, username: str = Form(...), password: str = Form(...)):
    # The login check uses the service account, because no role may read password hashes.
    user = query_one(
        "SELECT user_id, username, full_name, role FROM user_account "
        "WHERE username = %s AND password_hash = SHA2(%s, 256) AND is_active = TRUE",
        (username, password),
    )
    if not user:
        return templates.TemplateResponse(
            request=request,
            name="login.html",
            context={"error": "Invalid username or password"},
            status_code=401,
        )
    request.session["user"] = {
        "user_id": user["user_id"],
        "username": user["username"],
        "full_name": user["full_name"],
        "role": user["role"],
    }
    return RedirectResponse("/dashboard", status_code=303)


@app.get("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse("/login", status_code=303)


@app.get("/dashboard")
def dashboard(request: Request):
    user = current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=303)

    role = user["role"]  # every query below runs as this role's MySQL user
    stats = {
        "in_transit": query_one(
            "SELECT COUNT(*) AS n FROM shipment WHERE status = 'In Transit'", role=role
        )["n"],
        "open_alerts": query_one(
            "SELECT COUNT(*) AS n FROM v_active_alerts", role=role
        )["n"],
        "expiring": query_one(
            "SELECT COUNT(*) AS n FROM v_expiring_soon", role=role
        )["n"],
        "quarantined": query_one(
            "SELECT COUNT(*) AS n FROM inventory WHERE stock_status = 'Quarantined'",
            role=role,
        )["n"],
    }
    alerts = query_all(
        "SELECT alert_id, location, start_time, duration_min, peak_temp, severity, status "
        "FROM v_active_alerts ORDER BY start_time DESC LIMIT 5",
        role=role,
    )
    db_user = query_one("SELECT CURRENT_USER() AS u", role=role)["u"]

    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={"user": user, "stats": stats, "alerts": alerts, "db_user": db_user,
                 "flash": request.session.pop("flash", None)},
    )


@app.get("/health")
def health():
    row = query_one("SELECT 1 AS ok")
    return {"status": "ok", "database": "connected" if row else "error"}


from app.crud import router as crud_router  # noqa: E402

app.include_router(crud_router)

from app.shipments import router as shipments_router  # noqa: E402
from app.alerts import router as alerts_router  # noqa: E402

app.include_router(shipments_router)
app.include_router(alerts_router)
