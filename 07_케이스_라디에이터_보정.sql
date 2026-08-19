-- ============================================================
-- 08. 케이스 라디에이터 지원크기 채우기
-- 전제조건: case_radiator_scraper.py 실행 완료
--          (danawa_spec_summary에 spec_key='라디에이터(상단/측면/하단)' 데이터 있어야 함)
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
