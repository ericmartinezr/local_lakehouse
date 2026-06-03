import io
import os
from flask import Flask, render_template, request, jsonify, redirect
import boto3
from trino.dbapi import connect as trino_connect
from trino.exceptions import TrinoQueryError

app = Flask(__name__)

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
    region_name="us-east-1",
    use_ssl=False,
)
BUCKET = "lakehouse"


def trino_execute(sql):
    conn = trino_connect(
        host="localhost", port=8080, user="admin", catalog="iceberg"
    )
    cur = conn.cursor()
    cur.execute(sql)
    if cur.description:
        columns = [desc[0] for desc in cur.description]
        rows = [list(r) for r in cur.fetchall()]
        return {"columns": columns, "rows": rows}
    else:
        return {"rows_affected": cur.rowcount}


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/upload")
def upload_page():
    return render_template("upload.html")


@app.route("/files")
def files_page():
    return render_template("files.html")


@app.route("/query")
def query_page():
    return render_template("query.html")


@app.route("/api/files")
def list_files():
    try:
        resp = s3.list_objects_v2(Bucket=BUCKET)
        contents = resp.get("Contents", [])
        files = []
        for obj in contents:
            files.append(
                {
                    "key": obj["Key"],
                    "size": obj["Size"],
                    "last_modified": obj["LastModified"].isoformat(),
                }
            )
        return jsonify(files)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400
    f = request.files["file"]
    if f.filename == "":
        return jsonify({"error": "Empty filename"}), 400
    try:
        s3.upload_fileobj(f, BUCKET, f.filename)
        return jsonify({"ok": True, "key": f.filename})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/files/<path:key>")
def download_file(key):
    try:
        url = s3.generate_presigned_url(
            "get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=300
        )
        return redirect(url)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/query", methods=["POST"])
def run_query():
    data = request.get_json()
    if not data or "sql" not in data:
        return jsonify({"error": "No SQL provided"}), 400
    try:
        result = trino_execute(data["sql"])
        return jsonify(result)
    except TrinoQueryError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/schemas")
def list_schemas():
    try:
        result = trino_execute("SHOW SCHEMAS FROM iceberg")
        schemas = [r[0] for r in result["rows"]]
        return jsonify(schemas)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/tables")
def list_tables():
    schema = request.args.get("schema", "")
    if not schema:
        return jsonify({"error": "schema parameter required"}), 400
    try:
        result = trino_execute(f"SHOW TABLES FROM iceberg.{schema}")
        tables = [r[0] for r in result["rows"]]
        return jsonify(tables)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)
