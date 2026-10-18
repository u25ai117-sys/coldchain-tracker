from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.db import get_connection

BASE_DIR = Path(__file__).resolve().parent

app = FastAPI(title="Cold Chain Tracker")
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT VERSION();")
    version = cur.fetchone()[0]
    cur.close()
    conn.close()
    return templates.TemplateResponse(
        request=request, name="index.html", context={"db_version": version}
    )


@app.get("/health")
def health():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT 1;")
    cur.fetchone()
    cur.close()
    conn.close()
    return {"status": "ok", "database": "connected"}
