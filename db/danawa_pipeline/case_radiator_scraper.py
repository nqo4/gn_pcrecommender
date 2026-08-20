# -*- coding: utf-8 -*-
"""
케이스 상품 상세페이지에서 "라디에이터 지원크기" 호환성 정보를 긁어오는
전용 스크래퍼. (요약 스펙 한 줄에는 이 정보가 없고, 자바스크립트로
나중에 로딩되는 영역이라 requests만으로는 못 가져와서 Selenium 사용)

기존 spec_scraper.py와는 완전히 독립된 스크립트입니다.
(spec_scraper.py를 건드리지 않아서, 이 스크립트가 실패해도
지금까지 완성된 다른 카테고리/필드에는 영향이 없습니다.)

danawa_spec_summary 테이블에 spec_key를
'라디에이터(상단)', '라디에이터(측면)', '라디에이터(하단)' 로 저장합니다.
(기존 category='case' 데이터와 같은 테이블/구조를 그대로 사용)

사용법:
    pip install selenium
    (danawa_crawler.py와 같은 폴더의 chromedriver 필요)
    python case_radiator_scraper.py --limit 5      # 테스트
    python case_radiator_scraper.py                 # 전체
"""

import argparse
import os
import re
import time

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
import mysql.connector

REQUEST_DELAY = 2.0
PAGE_LOAD_TIMEOUT = 15
DEBUG_HTML_DUMP = False  # 처음엔 True로 두고 구조 확인 권장

DB_CONFIG = {
    "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
    "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
    "user": os.environ.get("DANAWA_DB_USER", "root"),
    "password": os.environ.get("DANAWA_DB_PASSWORD", "JH84952"),
    "database": os.environ.get("DANAWA_DB_NAME", "dw_db"),
    "charset": "utf8mb4",
}

DETAIL_URL = "https://prod.danawa.com/info/?pcode={pcode}"

# 찾고 싶은 라벨들 (다나와 "호환성" 표에서 확인된 표기 기준)
TARGET_LABELS = ["라디에이터(상단)", "라디에이터(측면)", "라디에이터(하단)", "수랭쿨러 규격"]


def build_driver():
    chrome_option = Options()
    chrome_option.add_argument("--headless=new")
    chrome_option.add_argument("--window-size=1920x1080")
    chrome_option.add_argument("--disable-gpu")
    chrome_option.add_argument("lang=ko-KR")
    chrome_option.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    )
    return webdriver.Chrome(options=chrome_option)


def fetch_radiator_info(driver, pcode: str):
    """케이스 상세페이지를 브라우저로 열어서 렌더링이 끝난 뒤,
    '호환성' 표 안의 라디에이터 관련 항목을 th/td, dt/dd 양쪽 다 시도해서 찾는다.
    """
    url = DETAIL_URL.format(pcode=pcode)
    driver.get(url)

    # 페이지 주요 콘텐츠가 뜰 때까지 대기 (body 존재로 최소한의 렌더링 대기)
    try:
        WebDriverWait(driver, PAGE_LOAD_TIMEOUT).until(
            EC.presence_of_element_located((By.TAG_NAME, "body"))
        )
    except Exception:
        pass

    # "호환성" 관련 섹션이 스크롤/탭 전환 없이 이미 로딩됐는지 확인하기 위해
    # 페이지 소스 전체에서 라벨을 텍스트로 직접 검색 (구조를 100% 확신 못 하므로
    # th/td, dt/dd, div 텍스트 전부 XPath로 넓게 탐색)
    result = {}
    for label in TARGET_LABELS:
        try:
            # <th>...라벨...</th> 를 찾고, 바로 다음 형제인 <td>에서 값 텍스트 추출
            # (라벨이 th 안의 <a> 태그 등으로 감싸져 있을 수 있어 contains(text())가 아니라
            #  전체 텍스트(.)에 라벨이 포함되는지로 판단)
            ths = driver.find_elements(
                By.XPATH, f"//th[contains(., '{label}')]"
            )
            for th in ths:
                try:
                    td = th.find_element(By.XPATH, "following-sibling::td[1]")
                    val = td.text.strip()
                    if val:
                        result[label] = val
                        break
                except Exception:
                    continue
        except Exception:
            continue

    if DEBUG_HTML_DUMP and not result:
        with open(f"debug_radiator_{pcode}.html", "w", encoding="utf8") as f:
            f.write(driver.page_source)
        if "라디에이터" in driver.page_source:
            idx = driver.page_source.find("라디에이터")
            print(f"    [진단] {pcode}: 렌더링된 페이지에 '라디에이터' 있음, 주변: "
                  f"...{driver.page_source[max(0, idx-150):idx+250]}...")
        else:
            print(f"    [진단] {pcode}: 렌더링 후에도 '라디에이터' 문자열 없음 "
                  f"(이 상품은 수랭 미지원 케이스일 가능성)")

    return result


def ensure_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS danawa_spec_summary (
            id          BIGINT AUTO_INCREMENT PRIMARY KEY,
            category    VARCHAR(20) NOT NULL,
            product_id  BIGINT UNSIGNED NOT NULL,
            spec_key    VARCHAR(150),
            spec_value  VARCHAR(300) NOT NULL,
            spec_order  INT NOT NULL,
            scraped_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_lookup (category, product_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None, help="테스트용 개수 제한")
    parser.add_argument("--force", action="store_true", help="이미 라디에이터 정보가 있는 상품도 다시 긁기")
    args = parser.parse_args()

    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    ensure_table(cursor)
    conn.commit()

    cursor.execute("SELECT product_id, name FROM case_products")
    rows = cursor.fetchall()

    if not args.force:
        cursor.execute(
            "SELECT DISTINCT product_id FROM danawa_spec_summary "
            "WHERE category='case' AND spec_key LIKE '라디에이터(%%'"
        )
        done = {r[0] for r in cursor.fetchall()}
        rows = [r for r in rows if r[0] not in done]

    if args.limit:
        rows = rows[: args.limit]

    print(f"===== case 라디에이터 정보 수집 대상 {len(rows)}개 =====")

    driver = build_driver()
    success, empty, fail = 0, 0, 0
    log_path = "case_radiator_progress.log"

    try:
        for i, (pid, name) in enumerate(rows, 1):
            try:
                info = fetch_radiator_info(driver, str(pid))
            except Exception as e:
                fail += 1
                log_line = f"[{i}/{len(rows)}] pid={pid} name={name} -> 실패(에러): {e}"
                print(log_line)
                with open(log_path, "a", encoding="utf8") as lf:
                    lf.write(log_line + "\n")
                time.sleep(REQUEST_DELAY)
                continue

            if info:
                cursor.execute(
                    "DELETE FROM danawa_spec_summary WHERE category='case' AND product_id=%s "
                    "AND spec_key LIKE '라디에이터(%%'",
                    (pid,),
                )
                insert_vals = [
                    ("case", pid, k, v, 900 + idx) for idx, (k, v) in enumerate(info.items())
                ]
                cursor.executemany(
                    """INSERT INTO danawa_spec_summary
                       (category, product_id, spec_key, spec_value, spec_order)
                       VALUES (%s,%s,%s,%s,%s)""",
                    insert_vals,
                )
                conn.commit()
                success += 1
                log_line = f"[{i}/{len(rows)}] pid={pid} name={name} -> 성공({len(info)}개): {info}"
            else:
                empty += 1
                log_line = f"[{i}/{len(rows)}] pid={pid} name={name} -> 없음(수랭 미지원 케이스로 추정)"

            print(log_line)
            with open(log_path, "a", encoding="utf8") as lf:
                lf.write(log_line + "\n")

            time.sleep(REQUEST_DELAY)
    finally:
        driver.quit()

    print(f"\n완료: 성공 {success} / 없음 {empty} / 실패 {fail}")
    cursor.close()
    conn.close()


if __name__ == "__main__":
    main()
