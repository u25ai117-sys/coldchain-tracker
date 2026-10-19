from pathlib import Path

from fastapi import Request
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates

BASE_DIR = Path(__file__).resolve().parent
templates = Jinja2Templates(directory=BASE_DIR / "templates")


def current_user(request: Request):
    return request.session.get("user")


def flash(request: Request, message: str, kind: str = "success"):
    request.session["flash"] = {"message": message, "kind": kind}


def render(request: Request, name: str, **context):
    context["user"] = current_user(request)
    context["flash"] = request.session.pop("flash", None)
    return templates.TemplateResponse(request=request, name=name, context=context)


def guard(request: Request, roles=None):
    """Returns (user, None) if allowed, or (None, redirect_response) if not."""
    user = current_user(request)
    if not user:
        return None, RedirectResponse("/login", status_code=303)
    if roles and user["role"] not in roles:
        flash(request, "Your role is not allowed to do that.", "danger")
        return None, RedirectResponse("/dashboard", status_code=303)
    return user, None
