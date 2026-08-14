-- ============================================================
-- 확장 스펙 컬럼 채우기 (2차) — add_extended_spec_columns.sql 실행 후 사용.
-- 전제조건: 각 카테고리에 spec_scraper.py가 실행되어 danawa_spec_summary에
-- 데이터가 쌓여 있어야 함.
--
-- spec_key 이름/값 형식은 실제 크롤링 덤프(spec_dump.sql)로 직접 확인한
-- 것이다(추측 아님). 숫자 추출은 REGEXP_SUBSTR(spec_value, '[0-9]+')로
-- 통일했다 — REGEXP_REPLACE(spec_value, '[^0-9]', '')는 값에 숫자가 두 번
-- 나오면 이어붙는 버그가 있어서(db/add_cooler_tdp_column.sql 등에서 이미
-- 겪음) 처음부터 안전한 방식으로 썼다.
--
-- *** 수정(실DB 테스트 중 발견: mysql CLI로 직접 실행하면 "Illegal mix of
-- collations" 에러) *** danawa_spec_summary는 utf8mb4_0900_ai_ci로 만들어져
-- 있는데, mysql CLI 클라이언트의 기본 연결 문자셋이 (환경에 따라, 특히
-- 한국어 로캘 Windows에서) euckr 등 다른 값이면 이 파일의 한글 spec_key
-- 리터럴('시네벤치R23(싱글)' 등)이 다른 콜레이션으로 해석되어 비교 연산이
-- 실패한다. db/db.py·db/load_real_data.py는 mysql.connector에 charset=
-- 'utf8mb4'를 코드로 명시해서 이 문제를 안 겪지만, mysql CLI로 직접 실행할
-- 땐(`mysql ... < 이파일.sql`) 클라이언트 설정에 좌우된다 — SET NAMES로
-- 이 세션 안에서 확정해서 어떤 클라이언트 기본값으로 접속하든 안전하게 한다.
-- ============================================================
USE DW_db;
SET NAMES utf8mb4;
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- CPU: 시네벤치 점수, 메모리 규격
-- ============================================================
UPDATE IGNORE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'cpu' AND spec_key = '시네벤치R23(싱글)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.cinebench_single = spec.v
WHERE p.cinebench_single IS NULL;

UPDATE IGNORE cpu_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'cpu' AND spec_key = '시네벤치R23(멀티)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.cinebench_multi = spec.v
WHERE p.cinebench_multi IS NULL;

UPDATE IGNORE cpu_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'cpu' AND spec_key = '메모리 규격'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.memory_support = spec.v
WHERE p.memory_support IS NULL;

-- ============================================================
-- VGA: 출력단자, 사용전력
-- ============================================================
UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'vga' AND spec_key = '출력단자'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.output_ports = spec.v
WHERE p.output_ports IS NULL;

UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'vga' AND spec_key = '사용전력'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.power_draw_w = spec.v
WHERE p.power_draw_w IS NULL;

-- ============================================================
-- 메인보드: SATA3, PCIe버전, PCIex16, M.2, VGA 연결
-- ============================================================
UPDATE IGNORE mboard_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_key = 'SATA3'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.sata3_count = spec.v
WHERE p.sata3_count IS NULL;

UPDATE IGNORE mboard_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_key = 'PCIe버전'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.pcie_version = spec.v
WHERE p.pcie_version IS NULL;

UPDATE IGNORE mboard_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_key = 'PCIex16'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.pcie_x16_count = spec.v
WHERE p.pcie_x16_count IS NULL;

UPDATE IGNORE mboard_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_key = 'M.2'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.m2_slot_count = spec.v
WHERE p.m2_slot_count IS NULL;

UPDATE IGNORE mboard_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_key = 'VGA 연결'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.vga_connection = spec.v
WHERE p.vga_connection IS NULL;

-- ============================================================
-- RAM: 램개수(스틱 단위 확인용), 방열판 높이(예전엔 조회 때마다 서브쿼리로
-- 구했던 값 — 이제 컬럼으로 승격)
-- ============================================================
UPDATE IGNORE ram_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'ram' AND spec_key = '램개수'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.stick_count = spec.v
WHERE p.stick_count IS NULL;

UPDATE IGNORE ram_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'ram' AND spec_key = '높이'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.heatsink_height_mm = spec.v
WHERE p.heatsink_height_mm IS NULL;

-- ============================================================
-- 파워: 깊이, 전압변동, ETA/LAMBDA 인증, 12VHPWR(12+4) 커넥터
-- ============================================================
UPDATE IGNORE power_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'power' AND spec_key = '깊이'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.depth_mm = spec.v
WHERE p.depth_mm IS NULL;

UPDATE IGNORE power_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'power' AND spec_key = '전압변동'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.voltage_regulation = spec.v
WHERE p.voltage_regulation IS NULL;

UPDATE IGNORE power_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'power' AND spec_key = 'ETA인증'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.eta_certification = spec.v
WHERE p.eta_certification IS NULL;

UPDATE IGNORE power_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'power' AND spec_key = 'LAMBDA인증'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.lambda_certification = spec.v
WHERE p.lambda_certification IS NULL;

-- *** core/psu_rules.py의 has_atx3_support()가 지금 상품명 텍스트로 추측하는
-- 걸 이 컬럼(진짜 스펙 출처)로 대체할 수 있다 — 이 컬럼이 NOT NULL이면
-- 네이티브 12VHPWR/12V-2x6 지원이 확정적이다. ***
UPDATE IGNORE power_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'power' AND spec_key = 'PCIe 16핀(12+4)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.pcie_16pin_connector = spec.v
WHERE p.pcie_16pin_connector IS NULL;

-- ============================================================
-- 케이스: 외형 치수, 패널 타입, 쿨링팬 개수, 파워 위치/장착 길이
-- ============================================================
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '너비(W)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ext_width_mm = spec.v
WHERE p.ext_width_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '깊이(D)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ext_depth_mm = spec.v
WHERE p.ext_depth_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '높이(H)'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ext_height_mm = spec.v
WHERE p.ext_height_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '측면 패널 타입'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.panel_type = spec.v
WHERE p.panel_type IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '쿨링팬'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.fan_count = spec.v
WHERE p.fan_count IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '파워 위치'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.psu_position = spec.v
WHERE p.psu_position IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)) AS v
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '파워 장착 길이'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.psu_max_length_mm = spec.v
WHERE p.psu_max_length_mm IS NULL;

-- ============================================================
-- 검증
-- ============================================================
SELECT 'cpu cinebench_single/multi 채워진 개수' AS info,
       COUNT(cinebench_single) AS single_cnt, COUNT(cinebench_multi) AS multi_cnt FROM cpu_products;
SELECT 'vga output_ports/power_draw_w 채워진 개수' AS info,
       COUNT(output_ports) AS ports_cnt, COUNT(power_draw_w) AS power_cnt FROM vga_products;
SELECT 'mboard sata3/pcie_x16/m2 채워진 개수' AS info,
       COUNT(sata3_count) AS sata3_cnt, COUNT(pcie_x16_count) AS pcie_cnt, COUNT(m2_slot_count) AS m2_cnt FROM mboard_products;
SELECT 'ram stick_count/heatsink_height_mm 채워진 개수' AS info,
       COUNT(stick_count) AS stick_cnt, COUNT(heatsink_height_mm) AS height_cnt FROM ram_products;
SELECT 'power depth/voltage/eta/lambda/12pin 채워진 개수' AS info,
       COUNT(depth_mm) AS depth_cnt, COUNT(voltage_regulation) AS volt_cnt,
       COUNT(eta_certification) AS eta_cnt, COUNT(lambda_certification) AS lambda_cnt,
       COUNT(pcie_16pin_connector) AS pin16_cnt FROM power_products;
SELECT 'case 외형치수/패널/팬/파워위치 채워진 개수' AS info,
       COUNT(ext_width_mm) AS width_cnt, COUNT(panel_type) AS panel_cnt,
       COUNT(fan_count) AS fan_cnt, COUNT(psu_position) AS psupos_cnt FROM case_products;
