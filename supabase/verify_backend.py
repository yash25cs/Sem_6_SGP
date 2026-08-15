"""Verification helper for the live Supabase backend.

Reads credentials from dart_define.json, signs in as a test account, and runs
whichever sub-command was asked for. Kept out of the app tree on purpose.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

# Keep local Supabase configuration outside Git. The default works from the
# repository root, while CI or another machine can override it explicitly.
DF = os.environ.get(
    "STUDYTRAIL_DART_DEFINES",
    os.path.join(os.path.dirname(__file__), "..", "studytrail_flutter", "dart_define.json"),
)
with open(DF) as fh:
    cfg = json.load(fh)
URL = cfg["SUPABASE_URL"].rstrip("/")
KEY = cfg["SUPABASE_ANON_KEY"]


def call(method, path, token=None, body=None, prefer=None):
    headers = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        try:
            return exc.code, json.loads(raw)
        except json.JSONDecodeError:
            return exc.code, raw


def signin(email, password):
    status, body = call(
        "POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password}
    )
    if status != 200 or not body or "access_token" not in body:
        sys.exit(f"sign-in failed ({status}): {body}")
    return body["access_token"]


def uid_of(token):
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))["sub"]


REPRESENTATION = "return=representation"


def seed_deck(token):
    me = uid_of(token)
    _, subjects = call("GET", "/rest/v1/subjects?select=id,name&name=eq.DBMS", token)
    subject_id = subjects[0]["id"] if subjects else None

    # Reuse the deck if a previous run already made it, so this is idempotent.
    _, existing = call(
        "GET", "/rest/v1/flashcard_decks?select=id&name=eq.DBMS%20Unit%201", token
    )
    if existing:
        deck_id = existing[0]["id"]
    else:
        status, deck = call(
            "POST",
            "/rest/v1/flashcard_decks",
            token,
            body={"user_id": me, "subject_id": subject_id, "name": "DBMS Unit 1"},
            prefer=REPRESENTATION,
        )
        if status not in (200, 201):
            sys.exit(f"deck insert failed ({status}): {deck}")
        deck_id = deck[0]["id"] if isinstance(deck, list) else deck["id"]
    print("deck:", deck_id)

    # PostgREST bulk insert requires every object to carry identical keys, so
    # due_at is set on all three rather than only the future-dated one.
    now = "2026-01-01T00:00:00Z"
    future = "2027-01-01T00:00:00Z"
    cards = [
        {"user_id": me, "deck_id": deck_id, "front": "What is 1NF?",
         "back": "Atomic columns.", "due_at": now},
        {"user_id": me, "deck_id": deck_id, "front": "What is 3NF?",
         "back": "No transitive deps.", "due_at": now},
        {"user_id": me, "deck_id": deck_id, "front": "What is BCNF?",
         "back": "Every determinant is a key.", "due_at": future},
    ]
    status, body = call("POST", "/rest/v1/flashcards", token, body=cards, prefer=REPRESENTATION)
    if status not in (200, 201):
        sys.exit(f"card insert failed ({status}): {body}")
    print("cards inserted:", len(body))

    _, stats = call("GET", "/rest/v1/deck_stats?select=deck_id,total,due", token)
    print("deck_stats:", json.dumps(stats))


def show(token):
    for label, path in [
        ("profile", "/rest/v1/profiles?select=email,full_name,level,xp"),
        ("goals", "/rest/v1/goals?select=name,exam_date,pace,is_active"),
        ("subjects", "/rest/v1/subjects?select=name"),
        ("decks", "/rest/v1/flashcard_decks?select=id,name"),
        ("deck_stats", "/rest/v1/deck_stats?select=deck_id,total,due"),
        ("flashcards", "/rest/v1/flashcards?select=front,due_at&order=due_at"),
        ("daily_tasks", "/rest/v1/daily_tasks?select=title,done"),
        ("chat_messages", "/rest/v1/chat_messages?select=role,text&order=created_at"),
    ]:
        _, body = call("GET", path, token)
        print(f"{label:15} {json.dumps(body)}")


def purge(token):
    """Delete this user's rows so the account is left clean."""
    for table in [
        "chat_citations",
        "chat_messages",
        "chat_threads",
        "flashcards",
        "flashcard_decks",
        "quiz_answers",
        "quiz_attempts",
        "quiz_questions",
        "quizzes",
        "milestone_tasks",
        "milestones",
        "daily_tasks",
        "materials",
        "subjects",
        "goals",
        "study_sessions",
        "activity_log",
        "user_badges",
    ]:
        status, _ = call("DELETE", f"/rest/v1/{table}?user_id=not.is.null", token)
        print(f"{table:18} -> {status}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(
            "Usage: python supabase/verify_backend.py "
            "<seed|show|purge> <test-email> <test-password>"
        )
    cmd = sys.argv[1]
    email = sys.argv[2]
    password = sys.argv[3]
    tok = signin(email, password)
    {"seed": seed_deck, "show": show, "purge": purge}[cmd](tok)
