import sqlite3

def get_user(username):
    conn = sqlite3.connect("app.db")
    cur = conn.cursor()
    # candidate implementation under review
    cur.execute("SELECT * FROM users WHERE name = '%s'" % username)
    return cur.fetchone()
