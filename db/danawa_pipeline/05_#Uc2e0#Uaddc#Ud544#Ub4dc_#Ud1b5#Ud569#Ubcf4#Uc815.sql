-- ============================================================
-- 05. CPU 코어/스레드 수, GPU VRAM 용량 채우기 (통합 최종본)
-- 전제조건: 01~04 실행 완료 + spec_scraper.py --all 실행 완료
--          (danawa_spec_summary 테이블에 데이터 있어야 함)
-- 이 파일 하나로 cpu_core_thread_fix~fix5, vga_vram_fix~fix3
-- 전부 대체합니다.
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- CPU 코어 수 (4가지 표기 패턴 순서대로 처리)
-- ============================================================

-- 1) 기본 패턴: "4코어"
UPDATE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '^[0-9]+') AS UNSIGNED)) AS cores
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^[0-9]+코어$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.core_count = t.cores
WHERE p.core_count IS NULL;

-- 2) 텍스트 표기: "듀얼 코어", "쿼드 코어" 등
UPDATE cpu_products p
JOIN (
    SELECT product_id,
        MAX(CASE
            WHEN spec_value = '싱글 코어' THEN 1
            WHEN spec_value = '듀얼 코어' THEN 2
            WHEN spec_value = '쿼드 코어' THEN 4
            WHEN spec_value = '헥사 코어' THEN 6
            WHEN spec_value = '옥타 코어' THEN 8
            ELSE NULL
        END) AS cores
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value IN ('싱글 코어','듀얼 코어','쿼드 코어','헥사 코어','옥타 코어')
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.core_count = t.cores
WHERE p.core_count IS NULL;

-- 3) 하이브리드(P+E코어) 표기: "P8+E4코어" -> 합산
UPDATE cpu_products p
JOIN (
    SELECT product_id,
        MAX(
            CAST(REGEXP_SUBSTR(SUBSTRING_INDEX(SUBSTRING_INDEX(spec_value,'+',1),'P',-1), '[0-9]+') AS UNSIGNED)
            +
            CAST(REGEXP_SUBSTR(SUBSTRING_INDEX(spec_value,'E',-1), '[0-9]+') AS UNSIGNED)
        ) AS cores
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^P[0-9]+\\+E[0-9]+코어$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.core_count = t.cores
WHERE p.core_count IS NULL;

-- 4) P코어만 있는 신형 표기: "P4코어" (E코어 없음)
UPDATE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS cores
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^P[0-9]+코어$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.core_count = t.cores
WHERE p.core_count IS NULL;

-- ============================================================
-- CPU 스레드 수 (3가지 표기 패턴 순서대로 처리)
-- ============================================================

-- 1) 기본 패턴: "4스레드"
UPDATE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '^[0-9]+') AS UNSIGNED)) AS threads
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^[0-9]+스레드$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.thread_count = t.threads
WHERE p.thread_count IS NULL;

-- 2) 하이브리드 표기: "16+4스레드" -> 합산
UPDATE cpu_products p
JOIN (
    SELECT product_id,
        MAX(
            CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(spec_value,'스레드',1),'+',1) AS UNSIGNED)
            +
            CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(spec_value,'스레드',1),'+',-1) AS UNSIGNED)
        ) AS threads
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^[0-9]+\\+[0-9]+스레드$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.thread_count = t.threads
WHERE p.thread_count IS NULL;

-- 3) 이형 표기: "8쓰레드" (스레드 아닌 쓰레드로 표기된 경우)
UPDATE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '^[0-9]+') AS UNSIGNED)) AS threads
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_value REGEXP '^[0-9]+쓰레드$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.thread_count = t.threads
WHERE p.thread_count IS NULL;

-- ============================================================
-- GPU VRAM 용량: 상품명에서 "N GB" 파싱
-- ============================================================
UPDATE vga_products
SET vram_gb = CAST(REPLACE(REGEXP_SUBSTR(name, '[0-9]+GB'), 'GB', '') AS UNSIGNED)
WHERE name REGEXP '[0-9]+GB' AND vram_gb IS NULL;

-- ============================================================
-- 메인보드 신규 필드: SATA3 포트 개수, VGA 연결방식, M.2 슬롯 정보
-- ============================================================

-- SATA3 포트 개수
UPDATE mboard_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS sata_cnt
    FROM danawa_spec_summary
    WHERE category='mboard' AND spec_key = 'SATA3'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.sata3_port_count = t.sata_cnt
WHERE p.sata3_port_count IS NULL;

-- VGA 연결방식 (예: "PCIe5.0 x16")
UPDATE mboard_products p
JOIN (
    SELECT product_id, MAX(spec_value) AS vga_slot
    FROM danawa_spec_summary
    WHERE category='mboard' AND spec_key = 'VGA 연결'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.vga_slot_type = t.vga_slot
WHERE p.vga_slot_type IS NULL;

-- M.2 슬롯 정보: 개수(M.2) + 연결방식(M.2 연결)을 합쳐서 저장 (예: "3개 (PCIe4.0, PCIe, SATA)")
UPDATE mboard_products p
JOIN (
    SELECT
        cnt.product_id,
        CONCAT(cnt.slot_cnt, '개', IFNULL(CONCAT(' (', conn.conn_types, ')'), '')) AS m2info
    FROM (
        SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS slot_cnt
        FROM danawa_spec_summary
        WHERE category='mboard' AND spec_key = 'M.2'
        GROUP BY product_id
    ) cnt
    LEFT JOIN (
        SELECT product_id, MAX(spec_value) AS conn_types
        FROM danawa_spec_summary
        WHERE category='mboard' AND spec_key = 'M.2 연결'
        GROUP BY product_id
    ) conn ON conn.product_id = cnt.product_id
) t ON t.product_id = p.product_id
SET p.m2_slot_info = t.m2info
WHERE p.m2_slot_info IS NULL;

-- ============================================================
-- RAM 신규 필드: 속도(MHz) - 상품명에서 "DDR4-3200" 형식 파싱
-- ============================================================
UPDATE ram_products
SET speed_mhz = CAST(
    SUBSTRING_INDEX(REGEXP_SUBSTR(name, 'DDR[0-9]+-[0-9]+'), '-', -1)
    AS UNSIGNED
)
WHERE name REGEXP 'DDR[0-9]+-[0-9]+' AND speed_mhz IS NULL;

-- ============================================================
-- 최종 확인
-- ============================================================
SELECT
  (SELECT COUNT(*) FROM cpu_products WHERE core_count IS NOT NULL) AS cpu_core_filled,
  (SELECT COUNT(*) FROM cpu_products WHERE thread_count IS NOT NULL) AS cpu_thread_filled,
  (SELECT COUNT(*) FROM cpu_products) AS cpu_total,
  (SELECT COUNT(*) FROM vga_products WHERE vram_gb IS NOT NULL) AS vga_vram_filled,
  (SELECT COUNT(*) FROM vga_products) AS vga_total,
  (SELECT COUNT(*) FROM mboard_products WHERE sata3_port_count IS NOT NULL) AS mb_sata3_filled,
  (SELECT COUNT(*) FROM mboard_products WHERE vga_slot_type IS NOT NULL) AS mb_vgaslot_filled,
  (SELECT COUNT(*) FROM mboard_products WHERE m2_slot_info IS NOT NULL) AS mb_m2_filled,
  (SELECT COUNT(*) FROM ram_products WHERE speed_mhz IS NOT NULL) AS ram_speed_filled;

SELECT '05 코어/스레드/VRAM/메인보드/RAM 보정 완료' AS next_step;
