-- ============================================================
-- 쿨러 카탈로그 정제: CPU 쿨러가 아닌 상품 제외
-- 다나와 "쿨러" 카테고리(cate=11236855)는 CPU 쿨러 외에도 케이스 팬,
-- RGB 조명, 팬 컨트롤러(허브), 써멀 그리스, 써멀 페이스트 가드 등을
-- 함께 포함하고 있어 그대로 두면 cooler_products에 섞여 들어감.
--
-- 판별 기준: spec_scraper.py가 긁은 스펙 요약의 첫 항목(spec_order=0)이
-- "CPU 쿨러"인 것만 실제 CPU 쿨러. 그 외(시스템 쿨러=케이스 팬, 조명기기,
-- 팬컨트롤러, 써멀컴파운드(그리스), 써멀 페이스트 가드 등)는 액세서리로
-- 보고 제외한다. 기획서 2.8절 카탈로그 정제 규칙(액세서리 배제)에 해당.
--
-- 전제조건: spec_scraper.py --category cooler 실행 완료
--   (아직 스크래핑 안 된 상품은 danawa_spec_summary에 spec_order=0 행 자체가
--    없어서 이 스크립트가 건드리지 않음 - 스크래핑 끝난 뒤 다시 실행하면 됨)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- 1) 참고: 제외 대상 미리보기 ----------
SELECT s.spec_value AS `첫_스펙_항목`, COUNT(*) AS `제외될_상품_수`
FROM danawa_spec_summary s
JOIN cooler_products p ON p.product_id = s.product_id
WHERE s.category = 'cooler' AND s.spec_order = 0 AND s.spec_value <> 'CPU 쿨러'
GROUP BY s.spec_value
ORDER BY COUNT(*) DESC;

-- ---------- 2) 쿨러 정리 ----------
DELETE FROM cooler_products
WHERE product_id IN (
    SELECT product_id FROM (
        SELECT product_id
        FROM danawa_spec_summary
        WHERE category = 'cooler' AND spec_order = 0 AND spec_value <> 'CPU 쿨러'
    ) AS excluded
);

SELECT '정리 후 cooler_products 개수' AS info, COUNT(*) AS cnt FROM cooler_products;

-- ---------- 3) 삭제된 상품의 부가 데이터 정리 ----------
DELETE s FROM danawa_spec_summary s
LEFT JOIN cooler_products p ON s.category = 'cooler' AND s.product_id = p.product_id
WHERE s.category = 'cooler' AND p.product_id IS NULL;

DELETE m FROM product_media m
LEFT JOIN cooler_products p ON m.category = 'cooler' AND m.product_id = p.product_id
WHERE m.category = 'cooler' AND p.product_id IS NULL;

DELETE pp FROM cooler_prices pp
LEFT JOIN cooler_products p ON pp.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT '완료' AS info;
