import os
from flask import Flask, jsonify
from sqlalchemy import create_engine, text

app = Flask(__name__)

DB_URI = os.environ.get(
    "DATABASE_URL",
    "mysql+pymysql://appuser:password@10.0.2.10:3306/appdb",
)

def get_db_engine():
    return create_engine(DB_URI, pool_pre_ping=True)


@app.route("/")
def health_check():
    return jsonify({"status": "ok", "message": "Flask app is running"})


@app.route("/db-check")
def db_check():
    engine = get_db_engine()
    with engine.connect() as connection:
        result = connection.execute(text("SELECT 1"))
        return jsonify({"status": "ok", "db_result": [row[0] for row in result]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
