-- ============================================================
-- 10. 키워드 테이블을 실제 상품에 적용 (반복 실행용)
--
-- *** DB 담당자는 이 파일만 계속 다시 실행하면 된다 ***
-- 09번(테이블 생성+초기 키워드)은 한 번만 실행하고, 이후 새 키워드를
-- cpu_tier_keywords/gpu_tier_keywords에 INSERT할 때마다 이 파일을 다시
-- 돌리면 된다 — 이미 tier_rank가 있는 상품은 안 건드리고(WHERE
-- tier_rank IS NULL), 새로 매칭되는 것만 채운다.
--
-- 매칭 규칙: 한 상품명에 여러 키워드가 동시에 들어맞을 수 있으므로(예:
-- "i5-13600K"는 "13600"에도, "13600K"에도 걸림), 가장 긴(=가장 구체적인)
-- 키워드를 우선 적용한다(ROW_NUMBER() ... ORDER BY LENGTH(keyword) DESC).
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- GPU ----------
UPDATE vga_products p
JOIN (
    SELECT product_id, tier_rank FROM (
        SELECT p2.product_id, k.tier_rank,
               ROW_NUMBER() OVER (PARTITION BY p2.product_id ORDER BY LENGTH(k.keyword) DESC) AS rn
        FROM vga_products p2
        JOIN gpu_tier_keywords k ON p2.name LIKE CONCAT('%', k.keyword, '%')
        WHERE p2.tier_rank IS NULL
    ) ranked WHERE rn = 1
) matched ON matched.product_id = p.product_id
SET p.tier_rank = matched.tier_rank
WHERE p.tier_rank IS NULL;

-- ---------- CPU ----------
UPDATE cpu_products p
JOIN (
    SELECT product_id, tier_rank FROM (
        SELECT p2.product_id, k.tier_rank,
               ROW_NUMBER() OVER (PARTITION BY p2.product_id ORDER BY LENGTH(k.keyword) DESC) AS rn
        FROM cpu_products p2
        JOIN cpu_tier_keywords k ON p2.name LIKE CONCAT('%', k.keyword, '%')
        WHERE p2.tier_rank IS NULL
    ) ranked WHERE rn = 1
) matched ON matched.product_id = p.product_id
SET p.tier_rank = matched.tier_rank
WHERE p.tier_rank IS NULL;

-- ============================================================
-- 결과 확인
-- ============================================================
SELECT COUNT(*) AS gpu_tier_filled FROM vga_products WHERE tier_rank IS NOT NULL;
SELECT COUNT(*) AS gpu_total FROM vga_products;
SELECT COUNT(*) AS cpu_tier_filled FROM cpu_products WHERE tier_rank IS NOT NULL;
SELECT COUNT(*) AS cpu_total FROM cpu_products;

-- 여전히 매칭 안 된 상품 — 이 목록을 보고 09번 테이블에 키워드를 추가하면 된다
SELECT name FROM vga_products WHERE tier_rank IS NULL;
SELECT name FROM cpu_products WHERE tier_rank IS NULL;
