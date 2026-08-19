-- ============================================================
-- 08. 케이스 라디에이터 지원크기 채우기
-- 전제조건: case_radiator_scraper.py 실행 완료
--          (danawa_spec_summary에 spec_key='라디에이터(상단/측면/하단)' 데이터 있어야 함)
--
-- *** 주의(New_crawler/fill_missing_specs.sql과의 순서 문제) ***
-- radiator_top/side/rear/front_mm 컬럼은 이미 New_crawler/fill_missing_specs.sql이
-- "팬 장착 위치 크기×개수"(spec_key='상단'/'전면'/'후면'/'내부 측면')로 근사한
-- 값을 채워두고 있다 — 이 스크립트의 UPDATE는 전부 `WHERE ... IS NULL` 가드라,
-- fill_missing_specs.sql을 먼저 돌렸다면 이 스크립트(더 정확한 실제 라디에이터
-- 지원 규격)가 그 근사값을 덮어쓰지 못하고 조용히 스킵된다. case_radiator_scraper.py
-- 데이터를 실제로 우선 적용하려면, 이 스크립트를 fill_missing_specs.sql보다
-- 먼저 실행하거나(권장) IS NULL 가드를 없애야 한다.
--
-- *** 주의(컬럼명과 실제 위치 불일치) ***
-- radiator_rear_mm 컬럼명은 "후면"을 뜻하지만, 아래는 spec_key='라디에이터(하단)'
-- (즉 "하단")을 여기에 넣는다 — 다나와 원문에 "라디에이터(하단)"이라는 표기가
-- 실제로 존재해서(케이스 카테고리 "하단" 위치), "후면"과는 다른 위치다.
-- New_crawler/fill_missing_specs.sql 쪽은 반대로 spec_key='후면'(진짜 후면 팬
-- 위치)을 이 컬럼에 넣고 있어서, 두 스크립트가 서로 다른 물리적 위치의
-- 값을 같은 컬럼에 채우고 있다 — 스키마에 "하단" 전용 컬럼이 없어서 생긴
-- 문제이니, 팀에서 radiator_bottom_mm 컬럼을 새로 만들지 결정이 필요하다.
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- 라디에이터(상단) -> radiator_top_mm
UPDATE case_products p
JOIN (
    SELECT product_id, MAX(spec_value) AS val
    FROM danawa_spec_summary
    WHERE category='case' AND spec_key = '라디에이터(상단)'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.radiator_top_mm = t.val
WHERE p.radiator_top_mm IS NULL;

-- 라디에이터(측면) -> radiator_side_mm
UPDATE case_products p
JOIN (
    SELECT product_id, MAX(spec_value) AS val
    FROM danawa_spec_summary
    WHERE category='case' AND spec_key = '라디에이터(측면)'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.radiator_side_mm = t.val
WHERE p.radiator_side_mm IS NULL;

-- 라디에이터(하단) -> radiator_rear_mm
-- 주의: 컬럼명은 "rear"(후면)이지만 실제 다나와 표기는 "하단" 기준으로 수집됨
UPDATE case_products p
JOIN (
    SELECT product_id, MAX(spec_value) AS val
    FROM danawa_spec_summary
    WHERE category='case' AND spec_key = '라디에이터(하단)'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.radiator_rear_mm = t.val
WHERE p.radiator_rear_mm IS NULL;

-- 결과 확인
SELECT
  (SELECT COUNT(*) FROM case_products WHERE radiator_top_mm IS NOT NULL) AS top_filled,
  (SELECT COUNT(*) FROM case_products WHERE radiator_side_mm IS NOT NULL) AS side_filled,
  (SELECT COUNT(*) FROM case_products WHERE radiator_rear_mm IS NOT NULL) AS bottom_filled,
  (SELECT COUNT(*) FROM case_products) AS case_total;

SELECT name, radiator_top_mm, radiator_side_mm, radiator_rear_mm
FROM case_products
WHERE radiator_top_mm IS NOT NULL OR radiator_side_mm IS NOT NULL OR radiator_rear_mm IS NOT NULL
LIMIT 20;
