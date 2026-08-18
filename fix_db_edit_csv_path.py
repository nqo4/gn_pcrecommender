"""
DB_edit\\02_부품별_가격정보.sql 안의 CSV 경로(팀원 컴퓨터 기준으로 하드코딩됨)를
이 컴퓨터의 실제 crawl_data 폴더 경로로 바꿔서 _fixed.sql 파일로 저장한다.

사용법:
    python fix_db_edit_csv_path.py "DB_edit\02_부품별_가격정보.sql" "실제crawl_data폴더경로"

예시(이전에 쓰시던 경로 기준):
    python fix_db_edit_csv_path.py "DB_edit\02_부품별_가격정보.sql" "Danawa-Crawler-fix\crawl_data"
"""
import sys

OLD_PREFIX = "C:/Users/GN/Desktop/Project_File/Danawa-Crawler-master/crawl_data"


def main():
    if len(sys.argv) != 3:
        print("사용법: python fix_db_edit_csv_path.py <sql파일> <실제crawl_data폴더>")
        sys.exit(1)

    sql_path = sys.argv[1]
    new_folder = sys.argv[2].replace("\\", "/").rstrip("/")

    with open(sql_path, encoding="utf-8") as f:
        content = f.read()

    count = content.count(OLD_PREFIX)
    if count == 0:
        print(f"경고: 파일 안에서 '{OLD_PREFIX}'를 하나도 못 찾았습니다 — 이미 수정된 파일이거나 경로 표기가 다를 수 있습니다.")
    else:
        print(f"{count}군데에서 경로를 교체합니다.")

    new_content = content.replace(OLD_PREFIX, new_folder)

    out_path = sql_path.rsplit(".", 1)[0] + "_fixed.sql"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"완료: {out_path} 생성됨")


if __name__ == "__main__":
    main()
