-- ============================================================
-- 09a. tier_rank 초기화 (09/10번 키워드 테이블 방식 적용 전 필수)
--
-- 이유: 이전 06_tier_rank.sql로 28개 모델에 구버전 번호(CPU 1~25, GPU 1~14)가
-- 이미 채워져 있음. 09/10번(신버전 CPU 1~41, GPU 1~30 체계)은
-- WHERE tier_rank IS NULL 조건이라 기존 값을 안 건드리고 넘어가므로,
-- 미리 초기화하지 않으면 구버전/신버전 번호가 한 컬럼에 섞여버림.
-- ============================================================
USE dw_db;
UPDATE vga_products SET tier_rank = NULL;
UPDATE cpu_products SET tier_rank = NULL;
SELECT 'tier_rank 초기화 완료 (전부 NULL) - 이제 09, 10번 순서대로 실행하세요.' AS next_step;
