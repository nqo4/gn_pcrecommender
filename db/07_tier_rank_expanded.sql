-- ============================================================
-- 07. CPU/GPU tier_rank 확장 재배치
--
-- *** 중요: 이 스크립트는 06_tier_rank.sql로 이미 채워진 tier_rank를
-- 통째로 초기화하고 새 번호로 다시 매긴다(부분 추가가 아니라 전체 재배치).
-- 실행 순서: 이 스크립트 하나만 실행하면 된다(06번을 다시 돌릴 필요 없음 —
-- 06번의 매칭 패턴을 그대로 가져와서 새 번호로 다시 썼다).
--
-- 새 번호 체계:
--   GPU: 1~30 (기존 14단계 앞에 구형 GPU 8단계, 사이에 RTX30 6단계 삽입)
--   CPU: 1~41 (기존 25단계 앞에 구형/보급형 16단계 삽입)
--
-- *** core/algorithm.py의 CPU_TIER_BUCKETS/GPU_TIER_BUCKETS도 이 번호에
-- 맞춰 같이 바꿔야 한다(별도 파일로 함께 전달함) — SQL만 실행하고 코드를
-- 안 바꾸면 등급 버킷(entry/mainstream/high/flagship) 경계가 깨진다. ***
--
-- 순위 근거: 각 세대/시리즈 간 상대 성능은 실제 벤치마크 자료(Tom's
-- Hardware GPU Hierarchy, Puget Systems, UserBenchmark 등)를 참고해
-- "대표 모델" 기준으로 정리한 근사치다. 세부 SKU 단위의 정밀한 순위가
-- 아니므로, 실제 카탈로그 확인 후 팀에서 미세 조정이 필요할 수 있다.
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- 기존 tier_rank 전체 초기화(재배치를 위해)
UPDATE vga_products SET tier_rank = NULL;
UPDATE cpu_products SET tier_rank = NULL;

-- ============================================================
-- GPU tier_rank 1~30 (구체적 -> 일반적 순서, 구형 GPU/RTX30 포함)
-- ============================================================

-- 최신 세대(기존 06번과 동일 패턴, 번호만 +8~+16 상향)
UPDATE vga_products SET tier_rank = 30 WHERE name LIKE '%RTX 5090%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 29 WHERE name LIKE '%RTX 4090%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 28 WHERE name LIKE '%RTX 5080%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 27 WHERE name LIKE '%RTX 3090 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 26 WHERE (name LIKE '%RTX 4080 SUPER%' OR name LIKE '%RTX 4080%') AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 25 WHERE name LIKE '%RTX 3090%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 24 WHERE name LIKE '%RTX 3080 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 23 WHERE name LIKE '%RTX 5070 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 22 WHERE name LIKE '%RTX 4070 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 21 WHERE name LIKE '%RTX 3080%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 20 WHERE name LIKE '%RTX 5070%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 19 WHERE name LIKE '%RTX 4070 SUPER%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 18 WHERE name LIKE '%RTX 3070 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 17 WHERE name LIKE '%RTX 4070%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 16 WHERE name LIKE '%RTX 3070%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 15 WHERE name LIKE '%RTX 5060 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 14 WHERE name LIKE '%RTX 4060 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 13 WHERE name LIKE '%RTX 3060 Ti%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 12 WHERE name LIKE '%RTX 5060%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 11 WHERE name LIKE '%RTX 3060%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 10 WHERE name LIKE '%RTX 4060%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 9  WHERE name LIKE '%RTX 5050%' AND tier_rank IS NULL;

-- 구형(20/16/10 시리즈) — 새로 추가되는 부분
UPDATE vga_products SET tier_rank = 8  WHERE name LIKE '%RTX 3050%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 7  WHERE (name LIKE '%GTX 1660 Ti%' OR name LIKE '%GTX1660Ti%') AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 6  WHERE (name LIKE '%GTX 1660 SUPER%' OR name LIKE '%GTX 1660 Super%') AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 5  WHERE name LIKE '%GTX 1660%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 4  WHERE name LIKE '%GTX 1650%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 3  WHERE name LIKE '%GTX 1060%' AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 2  WHERE (name LIKE '%GTX 1050 Ti%' OR name LIKE '%GTX1050Ti%') AND tier_rank IS NULL;
UPDATE vga_products SET tier_rank = 1  WHERE name LIKE '%GTX 1050%' AND tier_rank IS NULL;

-- ============================================================
-- CPU tier_rank 1~41 (구체적 -> 일반적 순서, 11/12세대 + 셀러론/펜티엄 포함)
-- ============================================================

-- 최신 세대(기존 06번과 동일 패턴, 번호만 +16 상향)
UPDATE cpu_products SET tier_rank = 41 WHERE name LIKE '%14900KS%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 40 WHERE name LIKE '%14900K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 39 WHERE name LIKE '%13900K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 38 WHERE name LIKE '%14900%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 37 WHERE (name LIKE '%울트라9%285K%' OR name LIKE '%울트라 9%285K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 36 WHERE (name LIKE '%울트라9%285%' OR name LIKE '%울트라 9%285%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 35 WHERE name LIKE '%13900%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 34 WHERE name LIKE '%14700K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 33 WHERE name LIKE '%13700K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 32 WHERE name LIKE '%14700%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 31 WHERE (name LIKE '%울트라7%270K%' OR name LIKE '%울트라 7%270K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 30 WHERE (name LIKE '%울트라7%265K%' OR name LIKE '%울트라 7%265K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 29 WHERE (name LIKE '%울트라7%265%' OR name LIKE '%울트라 7%265%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 28 WHERE name LIKE '%13700%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 27 WHERE (name LIKE '%13600K%' OR name LIKE '%14600K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 26 WHERE (name LIKE '%울트라5%250K%' OR name LIKE '%울트라 5%250K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 25 WHERE (name LIKE '%울트라5%245K%' OR name LIKE '%울트라 5%245K%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 24 WHERE (name LIKE '%울트라5%245%' OR name LIKE '%울트라 5%245%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 23 WHERE (name LIKE '%울트라5%235%' OR name LIKE '%울트라 5%235%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 22 WHERE (name LIKE '%울트라5%225%' OR name LIKE '%울트라 5%225%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 21 WHERE (name LIKE '%13600%' OR name LIKE '%14600%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 20 WHERE (name LIKE '%13500%' OR name LIKE '%14500%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 19 WHERE (name LIKE '%13400%' OR name LIKE '%14400%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 18 WHERE name LIKE '%14100%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 17 WHERE name LIKE '%13100%' AND tier_rank IS NULL;

-- 구형(12세대/11세대 + 셀러론/펜티엄) — 새로 추가되는 부분
-- 근거: "12900K가 13900(비K)와 비슷한 수준"이라는 세대 간 상대성능 기준.
-- 12세대 K모델이 11세대 K모델보다 위, 같은 등급이면 12세대가 11세대보다 위.
UPDATE cpu_products SET tier_rank = 16 WHERE name LIKE '%12900KS%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 15 WHERE name LIKE '%12900K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 14 WHERE name LIKE '%11900K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 13 WHERE name LIKE '%12900%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 12 WHERE name LIKE '%11900%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 11 WHERE name LIKE '%12700K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 10 WHERE name LIKE '%11700K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 9  WHERE name LIKE '%12700%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 8  WHERE name LIKE '%11700%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 7  WHERE name LIKE '%12600K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 6  WHERE name LIKE '%11600K%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 5  WHERE name LIKE '%12400%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 4  WHERE name LIKE '%11400%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 3  WHERE name LIKE '%12100%' AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 2  WHERE (name LIKE '%펜티엄%' OR name LIKE '%Pentium%') AND tier_rank IS NULL;
UPDATE cpu_products SET tier_rank = 1  WHERE (name LIKE '%셀러론%' OR name LIKE '%Celeron%') AND tier_rank IS NULL;

-- ============================================================
-- 결과 확인
-- ============================================================
SELECT COUNT(*) AS gpu_tier_filled FROM vga_products WHERE tier_rank IS NOT NULL;
SELECT COUNT(*) AS gpu_total FROM vga_products;
SELECT COUNT(*) AS cpu_tier_filled FROM cpu_products WHERE tier_rank IS NOT NULL;
SELECT COUNT(*) AS cpu_total FROM cpu_products;

-- 여전히 매칭 안 된 상품 목록(추가 패턴 보정용)
SELECT name FROM vga_products WHERE tier_rank IS NULL;
SELECT name FROM cpu_products WHERE tier_rank IS NULL;
