-- ============================================================
-- 07. 쿨러 팬 크기 / 팬 개수 추가
-- 웹 서버 쪽 요청: 수랭쿨러 옵션에서 라디에이터 길이 대신
-- 팬 크기(mm)와 팬 개수를 받아오도록 변경
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- 컬럼 추가 (처음 실행 시에만, 재실행 시 Duplicate 에러 나면 무시하면 됨)
ALTER TABLE cooler_products ADD COLUMN fan_size_mm SMALLINT UNSIGNED NULL;   -- 팬 크기 (120mm, 140mm 등)
ALTER TABLE cooler_products ADD COLUMN fan_count TINYINT UNSIGNED NULL;      -- 팬 개수

-- 팬 크기 채우기
UPDATE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS fan_size
    FROM danawa_spec_summary
    WHERE category='cooler' AND spec_key = '팬 크기'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.fan_size_mm = t.fan_size
WHERE p.fan_size_mm IS NULL;

-- 팬 개수 채우기
UPDATE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS fan_cnt
    FROM danawa_spec_summary
    WHERE category='cooler' AND spec_key = '팬 개수'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.fan_count = t.fan_cnt
WHERE p.fan_count IS NULL;

-- 팬 개수가 안 채워진 수랭쿨러는 라디에이터 길이로 역산 보완
-- (120mm 팬 기준: ~240mm=2개, ~280mm=2개, ~360mm급(287~410mm)=3개, 410mm+=4개)
UPDATE cooler_products
SET fan_count = CASE
    WHEN radiator_length_mm IS NULL THEN NULL
    WHEN radiator_length_mm < 260 THEN 2      -- 240mm급
    WHEN radiator_length_mm < 287 THEN 2      -- 280mm급
    WHEN radiator_length_mm < 410 THEN 3      -- 360mm급 (실측 편차로 395mm까지도 흔함)
    ELSE 4                                     -- 420mm+ 급
END
WHERE fan_count IS NULL AND radiator_length_mm IS NOT NULL;

-- 이전 실행에서 경계값 문제로 이미 "4개"로 잘못 채워졌던 360mm급(380~409mm) 보정
UPDATE cooler_products
SET fan_count = 3
WHERE fan_count = 4 AND radiator_length_mm BETWEEN 380 AND 409;

-- 결과 확인
SELECT
  (SELECT COUNT(*) FROM cooler_products WHERE fan_size_mm IS NOT NULL) AS fan_size_filled,
  (SELECT COUNT(*) FROM cooler_products WHERE fan_count IS NOT NULL) AS fan_count_filled,
  (SELECT COUNT(*) FROM cooler_products) AS cooler_total;

SELECT name, cooler_type, fan_size_mm, fan_count, radiator_length_mm
FROM cooler_products
WHERE fan_size_mm IS NOT NULL OR fan_count IS NOT NULL
LIMIT 20;
