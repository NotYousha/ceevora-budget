import json
import uuid

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    """Fresh seeded SQLite tenant per test."""
    from app.seed import init_sqlite

    db = tmp_path / "t.db"
    init_sqlite(db)
    reg = tmp_path / "tenants.json"
    reg.write_text(json.dumps({"DEMO": {"dialect": "sqlite", "path": str(db)}}))
    monkeypatch.setenv("CEEVORA_TENANTS_FILE", str(reg))
    monkeypatch.setenv("WEB_DIR", str(tmp_path / "noweb"))
    from app.main import app

    return TestClient(app, raise_server_exceptions=False)


def login(client, user, tenant="DEMO", password="Demo@2027"):
    r = client.post("/api/v1/auth/login", json={"tenant": tenant, "username": user, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def idem():
    return {"Idempotency-Key": uuid.uuid4().hex}
