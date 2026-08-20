"""
danawa_spec_summary 테이블을 파이썬으로 백업한다(mysqldump 없이).
테이블 구조(CREATE TABLE)와 데이터(INSERT문)를 하나의 .sql 파일로 만든다.

사용법:
    python backup_spec_summary.py
"""
import os
import mysql.connector

DB_CONFIG = {
    "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
    "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
    "user": os.environ.get("DANAWA_DB_USER", "root"),
    "password": os.environ.get("DANAWA_DB_PASSWORD", ""),
    "database": os.environ.get("DANAWA_DB_NAME", "dw_db"),
    "charset": "utf8mb4",
}

OUTPUT_FILE = "spec_summary_backup.sql"
BATCH_SIZE = 500  # 한 INSERT문에 몇 행씩 묶을지


def escape(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{text}'"


if __name__ == "__main__":
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()

    # 1) 테이블 구조 백업
    cursor.execute("SHOW CREATE TABLE danawa_spec_summary")
    create_stmt = cursor.fetchone()[1]

    # 2) 전체 데이터 백업
    cursor.execute("SELECT COUNT(*) FROM danawa_spec_summary")
    total = cursor.fetchone()[0]
    print(f"총 {total}개 행 백업 시작...")

    cursor.execute("SELECT * FROM danawa_spec_summary")
    columns = [desc[0] for desc in cursor.description]
    col_list = ", ".join(f"`{c}`" for c in columns)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("-- danawa_spec_summary 백업 (파이썬으로 생성, mysqldump 미사용)\n")
        f.write("DROP TABLE IF EXISTS danawa_spec_summary;\n")
        f.write(create_stmt + ";\n\n")

        batch = []
        written = 0
        for row in cursor:
            values = "(" + ", ".join(escape(v) for v in row) + ")"
            batch.append(values)
            if len(batch) >= BATCH_SIZE:
                f.write(f"INSERT INTO danawa_spec_summary ({col_list}) VALUES\n")
                f.write(",\n".join(batch))
                f.write(";\n\n")
                written += len(batch)
                print(f"  {written}/{total} 진행 중...")
                batch = []
        if batch:
            f.write(f"INSERT INTO danawa_spec_summary ({col_list}) VALUES\n")
            f.write(",\n".join(batch))
            f.write(";\n\n")
            written += len(batch)

    print(f"완료: {written}개 행을 {OUTPUT_FILE}에 저장했습니다.")
    cursor.close()
    conn.close()
