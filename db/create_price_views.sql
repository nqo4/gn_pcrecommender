-- ============================================================
-- 최신가 뷰 — 각 상품의 "그 상품 기준 가장 최근 crawl_date"의 최저가.
-- *_prices(id, product_id, crawl_date, option_name, price) 구조 기준.
--
-- [갱신 1] 예전엔 카테고리 전역 MAX(crawl_date)와 정확히 일치하는 행만
--   남겼는데, 크롤이 부분적으로만 돌았거나 같은 배치가 몇 초에 걸쳐
--   저장돼 시각이 갈리면 그 시각에 안 잡힌 상품이 뷰에서 통째로
--   사라졌다. 상품별 MAX(crawl_date) 기준으로 바꿔 견고하게 했다.
-- [갱신 2] USE DW_db 제거 — 대상 DB는 실행하는 쪽에서 지정한다
--   (db/db.py init_db는 DANAWA_DB_NAME으로, mysql CLI는 mysql ... <DB명>).
--   이 파일이 뷰 정의의 유일한 정의처다(예전엔 schema.sql에도 중복돼
--   있었다). 실DB엔 데이터 적재 후 한 번, 목업 DB엔 init_db가 자동 실행.
-- ============================================================

DROP VIEW IF EXISTS cpu_products_v;
CREATE VIEW cpu_products_v AS
SELECT p.*, latest.price AS price_krw
FROM cpu_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM cpu_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM cpu_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS vga_products_v;
CREATE VIEW vga_products_v AS
SELECT p.*, latest.price AS price_krw
FROM vga_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM vga_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM vga_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS mboard_products_v;
CREATE VIEW mboard_products_v AS
SELECT p.*, latest.price AS price_krw
FROM mboard_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM mboard_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM mboard_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS ram_products_v;
CREATE VIEW ram_products_v AS
SELECT p.*, latest.price AS price_krw
FROM ram_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM ram_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM ram_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS ssd_products_v;
CREATE VIEW ssd_products_v AS
SELECT p.*, latest.price AS price_krw
FROM ssd_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM ssd_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM ssd_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS hdd_products_v;
CREATE VIEW hdd_products_v AS
SELECT p.*, latest.price AS price_krw
FROM hdd_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM hdd_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM hdd_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS cooler_products_v;
CREATE VIEW cooler_products_v AS
SELECT p.*, latest.price AS price_krw
FROM cooler_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM cooler_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM cooler_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS power_products_v;
CREATE VIEW power_products_v AS
SELECT p.*, latest.price AS price_krw
FROM power_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM power_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM power_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS case_products_v;
CREATE VIEW case_products_v AS
SELECT p.*, latest.price AS price_krw
FROM case_products p
JOIN (
    SELECT pp.product_id, MIN(pp.price) AS price
    FROM case_prices pp
    JOIN (
        SELECT product_id, MAX(crawl_date) AS max_date
        FROM case_prices GROUP BY product_id
    ) md ON md.product_id = pp.product_id AND md.max_date = pp.crawl_date
    GROUP BY pp.product_id
) latest ON latest.product_id = p.product_id;

SELECT '가격 뷰 9개 생성 완료(상품별 최신 crawl_date 기준)' AS info;
