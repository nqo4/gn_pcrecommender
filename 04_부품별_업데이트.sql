-- ============================================================
-- 04. 부품별 상세 스펙 값 채우기
-- 전제조건: 01,02,03 실행 완료 + spec_scraper.py --all 실행 완료
--          (danawa_spec_summary, product_media 테이블에 데이터 있어야 함)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- from: cpu_socket_update.sql
-- ============================================================
-- ============================================================
-- CPU 소켓 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category cpu 완료
-- 실제 형태: spec_key는 NULL, spec_value가 "인텔(소켓775)", "AMD(소켓AM4)" 형식.
--            같은 상품에 "AMD 라데온 Vega 3" 같은 무관한 행도 섞여있으므로
--            "(소켓" 문자열이 포함된 행만 골라서 사용.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

UPDATE IGNORE cpu_products p
JOIN (
    SELECT
        s.product_id,
        -- 괄호 안에서 "소켓" 글자를 뗀 나머지.
        -- 숫자만 남으면(인텔) 앞에 LGA를 붙이고, 문자가 섞여있으면(AMD, AM4/AM5/TR4 등) 그대로 사용.
        CASE
            WHEN REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', '') REGEXP '^[0-9]+$'
                THEN CONCAT('LGA', REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
            ELSE UPPER(REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
        END AS socket_value,
        s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'cpu'
      AND s.spec_value LIKE '%(소켓%'
) spec ON spec.product_id = p.product_id
-- 한 상품에 소켓 행이 여러 개 나올 수 있어(예: 하위호환 소켓 안내) spec_order가 가장 앞선 것 하나만 사용
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'cpu' AND spec_value LIKE '%(소켓%'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.socket = spec.socket_value
WHERE p.socket IS NULL;

SELECT 'cpu socket 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE socket IS NOT NULL;

-- 확인: 어떤 소켓 값들이 채워졌는지
SELECT socket, COUNT(*) AS cnt FROM cpu_products GROUP BY socket ORDER BY cnt DESC;

-- ============================================================
-- from: mboard_socket_formfactor_update.sql
-- ============================================================
-- ============================================================
-- MBoard 소켓 / 폼팩터 / RAM 규격 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category mboard 완료
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 소켓 (CPU와 동일한 "제조사(소켓XXXX)" 형식)
UPDATE IGNORE mboard_products p
JOIN (
    SELECT
        s.product_id,
        CASE
            WHEN REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', '') REGEXP '^[0-9]+$'
                THEN CONCAT('LGA', REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
            ELSE UPPER(REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
        END AS socket_value,
        s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value LIKE '%(소켓%'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_value LIKE '%(소켓%'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.socket = spec.socket_value
WHERE p.socket IS NULL;

-- 2) 폼팩터 ("ATX (30.5x24.4cm)" -> "ATX", "M-ITX (17.0x17.0cm)" -> "M-ITX")
UPDATE IGNORE mboard_products p
JOIN (
    SELECT s.product_id, TRIM(SUBSTRING_INDEX(s.spec_value, '(', 1)) AS ff, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value REGEXP '^(E-ATX|ATX|M-ATX|M-ITX|ITX|Pico-ITX)[[:space:]]*\\('
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard'
      AND spec_value REGEXP '^(E-ATX|ATX|M-ATX|M-ITX|ITX|Pico-ITX)[[:space:]]*\\('
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.form_factor = spec.ff
WHERE p.form_factor IS NULL;

-- 3) RAM 규격 (DDR4 / DDR5, "노트북용" 접미사는 무시하고 앞 부분만 사용)
UPDATE IGNORE mboard_products p
JOIN (
    SELECT s.product_id, REGEXP_SUBSTR(s.spec_value, '^(DDR4|DDR5|LPDDR4|LPDDR5)') AS rtype, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value REGEXP '^(DDR4|DDR5|LPDDR4|LPDDR5)'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_value REGEXP '^(DDR4|DDR5|LPDDR4|LPDDR5)'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.ram_type = spec.rtype
WHERE p.ram_type IS NULL;

SELECT 'mboard socket 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE socket IS NOT NULL;
SELECT 'mboard form_factor 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE form_factor IS NOT NULL;
SELECT 'mboard ram_type 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE ram_type IS NOT NULL;

SELECT socket, COUNT(*) cnt FROM mboard_products GROUP BY socket ORDER BY cnt DESC;
SELECT form_factor, COUNT(*) cnt FROM mboard_products GROUP BY form_factor ORDER BY cnt DESC;
SELECT ram_type, COUNT(*) cnt FROM mboard_products GROUP BY ram_type ORDER BY cnt DESC;

-- ============================================================
-- from: cooler_spec_update.sql
-- ============================================================
-- ============================================================
-- Cooler 지원 소켓 / 높이 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category cooler 완료
-- 실제 형태:
--   지원 소켓: spec_key = "인텔 소켓" 또는 "AMD 소켓", spec_value = "LGA1200, LGA115x, LGA1366" (콤마구분)
--   높이:      spec_key = "높이", spec_value = "125mm"
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 지원 소켓: 인텔/AMD 소켓 행을 한 상품당 하나의 콤마 문자열로 합침
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id,
           GROUP_CONCAT(DISTINCT spec_value SEPARATOR ', ') AS sockets
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key IN ('인텔 소켓', 'AMD 소켓')
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.support_sockets = spec.sockets
WHERE p.support_sockets IS NULL;

-- 2) 높이 (mm)
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MIN(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS h
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '높이'
      AND spec_value REGEXP '^[0-9]+(\\.[0-9]+)?mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.height_mm = spec.h
WHERE p.height_mm IS NULL;

SELECT 'cooler support_sockets 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE support_sockets IS NOT NULL;
SELECT 'cooler height_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE height_mm IS NOT NULL;

-- 참고: 일체형 수랭 쿨러는 "높이"가 아니라 라디에이터 규격으로 표시되는 경우가 많아
-- height_mm이 비어있을 수 있음(수랭은 원래 "쿨러 높이 ≤ 케이스 최대 쿨러높이" 체크 대상이 아님).

-- ============================================================
-- from: cooler_radiator_type_fill.sql
-- ============================================================
-- ============================================================
-- 쿨러: 라디에이터 길이/두께(수랭용) + 공랭/수랭 구분(cooler_type) 채우기
-- cooler_type 컬럼은 add_compat_columns.sql에서 이미 만들어져 있었지만
-- 지금까지 안 채워져 있었음(값 없는 빈 컬럼) - 이번에 채움.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- radiator_length_mm, radiator_thickness_mm 컬럼은 03_부품_상세정보.sql에서 이미 생성됨 (여기선 값만 채움)

-- ---------- 1) 라디에이터 길이(mm) ----------
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS len
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '라디에이터 길이'
      AND spec_value REGEXP '^[0-9]+mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_length_mm = spec.len
WHERE p.radiator_length_mm IS NULL;

-- ---------- 2) 라디에이터 두께(mm) ----------
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS th
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '라디에이터 두께'
      AND spec_value REGEXP '^[0-9]+mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_thickness_mm = spec.th
WHERE p.radiator_thickness_mm IS NULL;

-- ---------- 3) 공랭/수랭 구분 ----------
-- 라디에이터 길이가 있으면 무조건 수랭. 그 외엔 spec 텍스트의 '공랭'/'수랭'/'[수랭]' 표기로 판단.
UPDATE IGNORE cooler_products p
SET p.cooler_type = '수랭'
WHERE p.radiator_length_mm IS NOT NULL
  AND p.cooler_type IS NULL;

UPDATE IGNORE cooler_products p
JOIN (
    SELECT DISTINCT product_id
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND (spec_value LIKE '%수랭%')
) spec ON spec.product_id = p.product_id
SET p.cooler_type = '수랭'
WHERE p.cooler_type IS NULL;

UPDATE IGNORE cooler_products p
JOIN (
    SELECT DISTINCT product_id
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_value LIKE '%공랭%'
) spec ON spec.product_id = p.product_id
SET p.cooler_type = '공랭'
WHERE p.cooler_type IS NULL;

-- 그래도 안 채워진 나머지는, 높이(height_mm)는 있는데 라디에이터 정보가 전혀 없는 경우이므로 공랭으로 간주
UPDATE cooler_products
SET cooler_type = '공랭'
WHERE cooler_type IS NULL AND height_mm IS NOT NULL;

SELECT 'cooler radiator_length_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE radiator_length_mm IS NOT NULL;
SELECT 'cooler radiator_thickness_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE radiator_thickness_mm IS NOT NULL;
SELECT cooler_type, COUNT(*) AS cnt FROM cooler_products GROUP BY cooler_type;
SELECT product_id, name FROM cooler_products WHERE cooler_type IS NULL;

-- ============================================================
-- from: vga_spec_update.sql
-- ============================================================
-- ============================================================
-- VGA 길이 / 권장 파워용량 / 전원 커넥터 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category vga 완료
-- 실제 형태:
--   길이:      spec_key = "가로(길이)", spec_value = "148mm"
--   권장파워:  spec_key는 보통 NULL, spec_value = "450W 이상", "750W 이상" 등
--   전원커넥터: spec_key = "전원 포트", spec_value = "8핀 x1" 등
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 길이 (mm)
UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MIN(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS l
    FROM danawa_spec_summary
    WHERE category = 'vga'
      AND spec_key = '가로(길이)'
      AND spec_value REGEXP '^[0-9]+(\\.[0-9]+)?mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.length_mm = spec.l
WHERE p.length_mm IS NULL;

-- 2) 권장 파워 용량 (W) - "450W 이상" 형태에서 숫자만
UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS w
    FROM danawa_spec_summary
    WHERE category = 'vga'
      AND spec_value REGEXP '^[0-9]+W[[:space:]]*이상$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.recommended_psu_w = spec.w
WHERE p.recommended_psu_w IS NULL;

-- 3) 전원 커넥터 (예: "8핀 x1", "8핀 x2")
UPDATE IGNORE vga_products p
JOIN (
    SELECT s.product_id, s.spec_value AS conn, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'vga' AND s.spec_key = '전원 포트'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'vga' AND spec_key = '전원 포트'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.power_connector = spec.conn
WHERE p.power_connector IS NULL;

SELECT 'vga length_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE length_mm IS NOT NULL;
SELECT 'vga recommended_psu_w 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE recommended_psu_w IS NOT NULL;
SELECT 'vga power_connector 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE power_connector IS NOT NULL;

-- ============================================================
-- from: ram_type_update.sql
-- ============================================================
-- ============================================================
-- RAM 규격(DDR4/DDR5) 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category ram 완료
-- 실제 형태: spec_key는 NULL, spec_value가 정확히 "DDR4" 또는 "DDR5"
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
UPDATE IGNORE ram_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS rtype
    FROM danawa_spec_summary
    WHERE category = 'ram' AND spec_value IN ('DDR4', 'DDR5', 'LPDDR4', 'LPDDR5')
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ram_type = spec.rtype
WHERE p.ram_type IS NULL;

SELECT 'ram ram_type 채워진 개수' AS info, COUNT(*) AS cnt FROM ram_products WHERE ram_type IS NOT NULL;
SELECT ram_type, COUNT(*) cnt FROM ram_products GROUP BY ram_type ORDER BY cnt DESC;

-- ============================================================
-- from: power_spec_update.sql
-- ============================================================
-- ============================================================
-- Power(파워) 정격출력 / 폼팩터 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category power 완료
-- 실제 형태:
--   정격출력: spec_key = "출력 용량(W)" 인 경우가 많지만, spec_key가 NULL이고
--             spec_value가 순수하게 "500W" 형태인 행도 많음 -> 둘 다 커버.
--             ("출력 용량(VA)"는 다른 단위라 제외, "대기전력 1W 미만"처럼
--              부가 텍스트가 붙은 값은 정규식으로 자동 제외됨)
--   폼팩터:   spec_key는 보통 NULL, spec_value가 "ATX 파워", "M-ATX(SFX) 파워",
--             "Flex-ATX 파워"처럼 반드시 "파워"로 끝남 (인증 변경이력 텍스트와 구분되는 지점)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 정격 출력 (W)
UPDATE IGNORE power_products p
JOIN (
    SELECT product_id,
           MAX(CAST(REPLACE(spec_value, 'W', '') AS UNSIGNED)) AS w
    FROM danawa_spec_summary
    WHERE category = 'power'
      AND (spec_key = '출력 용량(W)' OR spec_key IS NULL)
      AND spec_value REGEXP '^[0-9]+W$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.rated_w = spec.w
WHERE p.rated_w IS NULL;

-- 2) 폼팩터 ("...파워"로 끝나는 행만 사용 - 인증서 변경이력 등 노이즈 자동 배제)
UPDATE IGNORE power_products p
JOIN (
    SELECT s.product_id,
           CASE
               WHEN s.spec_value LIKE '%SFX%'      THEN 'SFX'
               WHEN s.spec_value LIKE '%TFX%'       THEN 'TFX'
               WHEN s.spec_value LIKE '%Flex-ATX%' OR s.spec_value LIKE '%FLEX%' THEN 'FLEX'
               ELSE 'ATX'
           END AS ff,
           s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'power'
      AND s.spec_value LIKE '%파워'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'power' AND spec_value LIKE '%파워'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.form_factor = spec.ff
WHERE p.form_factor IS NULL;

SELECT 'power rated_w 채워진 개수' AS info, COUNT(*) AS cnt FROM power_products WHERE rated_w IS NOT NULL;
SELECT 'power form_factor 채워진 개수' AS info, COUNT(*) AS cnt FROM power_products WHERE form_factor IS NOT NULL;
SELECT form_factor, COUNT(*) cnt FROM power_products GROUP BY form_factor ORDER BY cnt DESC;

-- ============================================================
-- from: case_spec_update.sql
-- ============================================================
-- ============================================================
-- Case 지원 폼팩터 / 최대 쿨러높이 / 최대 VGA길이 / 지원 파워규격 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category case 완료
-- 실제 형태:
--   지원 폼팩터: spec_key = "지원보드규격", spec_value = "ATX, M-ATX" 등 (이미 콤마로 합쳐진 문자열)
--   최대쿨러높이: spec_key = "CPU쿨러 높이", spec_value = "최대 200mm"
--   지원 파워규격: spec_key = "지원파워규격", spec_value = "표준-ATX", "M-ATX(SFX)" 등
--   최대VGA길이: 정확한 spec_key를 확인 못해서, "그래픽카드"가 들어간 key + mm값 있는 행을 넓게 잡음
--                (혹시 0건이면 discovery_spec_keys.sql의 VGA 관련 case 쿼리 결과를 다시 보내주세요)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 지원 보드 폼팩터 (한 상품에 여러 행이 있을 수 있어 spec_order가 가장 앞선 것 사용)
UPDATE IGNORE case_products p
JOIN (
    SELECT s.product_id, s.spec_value AS ff, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'case' AND s.spec_key = '지원보드규격'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'case' AND spec_key = '지원보드규격'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.support_form_factors = spec.ff
WHERE p.support_form_factors IS NULL;

-- 2) 최대 CPU쿨러 장착 높이 (mm)
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MIN(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS h
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = 'CPU쿨러 높이'
      AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.max_cooler_height_mm = spec.h
WHERE p.max_cooler_height_mm IS NULL;

-- 3) 지원 파워 규격 (원문 그대로 저장, ATX/SFX 여부는 매칭 단계에서 문자열로 판단)
UPDATE IGNORE case_products p
JOIN (
    SELECT s.product_id, s.spec_value AS pf, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'case' AND s.spec_key = '지원파워규격'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'case' AND spec_key = '지원파워규격'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.support_psu_form_factors = spec.pf
WHERE p.support_psu_form_factors IS NULL;

-- 4) 최대 VGA 길이 (mm) - 정확한 spec_key 미확인이라 넓게 잡음
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS l
    FROM danawa_spec_summary
    WHERE category = 'case'
      AND (spec_key LIKE '%그래픽카드%' OR spec_key LIKE '%VGA%')
      AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.max_vga_length_mm = spec.l
WHERE p.max_vga_length_mm IS NULL;

SELECT 'case support_form_factors 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE support_form_factors IS NOT NULL;
SELECT 'case max_cooler_height_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE max_cooler_height_mm IS NOT NULL;
SELECT 'case support_psu_form_factors 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE support_psu_form_factors IS NOT NULL;
SELECT 'case max_vga_length_mm 채워진 개수 (0건이면 discovery 결과 다시 확인 필요)' AS info, COUNT(*) AS cnt FROM case_products WHERE max_vga_length_mm IS NOT NULL;


-- ============================================================
-- (별도 실행) CPU 내장그래픽 유무 / PBP-MTP(최소-최대 전력) 채우기
-- 전제조건:
--   1) 위 danawa_only_load.sql 이 먼저 실행되어 cpu_products 가 존재해야 함
--   2) spec_scraper.py --category cpu 를 실행해서 danawa_spec_summary 테이블에
--      CPU 상세페이지 요약정보(다나와 meta description의 "요약정보 : ..." 한 줄)가 쌓여 있어야 함
--      예) "인텔(소켓1700)/.../내장그래픽:탑재/.../PBP-MTP: 125-253W/..."
--          "AMD(소켓AM5)/.../내장그래픽:탑재/.../TDP: 65W/PPT: 88W/..."
--   * 인텔은 PBP-MTP 하나에 "최소-최대W" 형태로, AMD는 TDP(최소)/PPT(최대)로 따로 표기되는
--     경우가 있어서 두 패턴을 모두 처리하도록 만들었습니다.
-- ============================================================
USE DW_db;

-- 1) 내장그래픽 유무
UPDATE cpu_products p
JOIN (
    SELECT product_id,
           CASE
               WHEN MAX(CASE WHEN spec_value LIKE '%미탑재%' THEN 1 ELSE 0 END) = 1 THEN 'N'
               WHEN MAX(CASE WHEN spec_value LIKE '%탑재%' THEN 1 ELSE 0 END) = 1 THEN 'Y'
               ELSE NULL
           END AS igpu
    FROM danawa_spec_summary
    WHERE category = 'cpu'
      AND spec_key LIKE '%내장그래픽%'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.has_igpu = spec.igpu;

-- 2) 전력(PBP-MTP 방식: 인텔 "125-253W" 형태 -> 최소/최대 분리)
UPDATE cpu_products p
JOIN (
    SELECT product_id,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', 1) AS UNSIGNED) AS pmin,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', -1) AS UNSIGNED) AS pmax
    FROM danawa_spec_summary
    WHERE category = 'cpu'
      AND spec_key LIKE '%PBP%'
      AND spec_value REGEXP '^[0-9]+[[:space:]]*-[[:space:]]*[0-9]+'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = spec.pmin,
    p.power_max_w = spec.pmax
WHERE p.power_min_w IS NULL;

-- 3) 전력(AMD 방식: TDP=최소, PPT=최대 가 별도 항목으로 표기되는 경우)
UPDATE cpu_products p
JOIN (
    SELECT t.product_id,
           CAST(REGEXP_REPLACE(t.spec_value, '[^0-9]', '') AS UNSIGNED) AS tdp,
           CAST(REGEXP_REPLACE(pp.spec_value, '[^0-9]', '') AS UNSIGNED) AS ppt
    FROM danawa_spec_summary t
    JOIN danawa_spec_summary pp
      ON pp.category = 'cpu' AND pp.product_id = t.product_id AND pp.spec_key LIKE '%PPT%'
    WHERE t.category = 'cpu'
      AND t.spec_key LIKE '%TDP%'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = spec.tdp,
    p.power_max_w = spec.ppt
WHERE p.power_min_w IS NULL;

SELECT 'cpu has_igpu 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE has_igpu IS NOT NULL;
SELECT 'cpu power_min_w/power_max_w 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE power_min_w IS NOT NULL;

-- 확인용: 실제 저장된 스펙 문구가 위 패턴과 다르면 아래로 먼저 눈으로 확인하세요.
-- SELECT spec_key, spec_value FROM danawa_spec_summary WHERE category='cpu' LIMIT 50;


-- ============================================================
-- (별도 실행) 메인보드 RAM 소켓(슬롯) 개수 채우기
-- 전제조건:
--   1) 위 danawa_only_load.sql 이 먼저 실행되어 mboard_products 가 존재해야 함
--   2) spec_scraper.py --category mboard 를 실행해서 danawa_spec_summary 테이블에
--      메인보드 상세페이지 스펙(요약 한 줄)이 쌓여 있어야 함
--      (가격 크롤링 CSV에는 슬롯 개수 정보가 아예 없기 때문에 상세페이지를 따로 긁어야 합니다)
-- ============================================================
USE DW_db;

UPDATE mboard_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(
                   REGEXP_REPLACE(
                       REGEXP_SUBSTR(spec_value, '[0-9]+[[:space:]]*(개|[Ss]lot)'),
                       '[^0-9]', ''
                   ) AS UNSIGNED
               )
           ) AS slots
    FROM danawa_spec_summary
    WHERE category = 'mboard'
      AND (
            spec_key LIKE '%슬롯%' OR spec_key LIKE '%메모리%'
            OR spec_value LIKE '%슬롯%' OR spec_value LIKE '%[Ss]lot%'
          )
      AND REGEXP_SUBSTR(spec_value, '[0-9]+[[:space:]]*(개|[Ss]lot)') IS NOT NULL
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ram_slot_count = spec.slots;

SELECT 'mboard ram_slot_count 채워진 개수' AS info, COUNT(*) AS cnt
FROM mboard_products WHERE ram_slot_count IS NOT NULL;

-- 위 REGEXP_SUBSTR 패턴이 실제 spec_value 형식과 안 맞아서 0건이면,
-- 아래 쿼리로 실제 저장된 스펙 문구를 먼저 확인한 뒤 패턴을 맞춰서 다시 실행하세요.
-- SELECT spec_key, spec_value FROM danawa_spec_summary WHERE category='mboard' LIMIT 50;

-- 알려진 한계 (이번 스크립트로 해결 안 됨):
--   - Case의 라디에이터 지원 규격(상단/측면/후면, radiator_top/side/rear_mm)은
--     현재 크롤링된 danawa_spec_summary 데이터 안에 해당 정보 자체가 없습니다.
--     (case 카테고리 스펙에는 지원보드규격/VGA 길이/CPU쿨러 높이/지원파워규격만 존재)
--     추가로 채우려면 상품명이나 별도 소스에서 라디에이터 지원 여부를 파싱하는
--     별도 로직이 필요하며, 지금 단계에서는 NULL로 남겨둡니다.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- 1) RAM 용량 실제 반영 ----------
-- ram_options은 fill_missing_specs_v2.sql이 이미 만들어 둔 테이블(없으면 아래 블록에서 재생성)
DROP TABLE IF EXISTS ram_options;
CREATE TABLE ram_options (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    capacity_gb SMALLINT UNSIGNED NOT NULL,
    KEY idx_product (product_id)
);

INSERT INTO ram_options (product_id, capacity_gb)
SELECT DISTINCT
    product_id,
    CASE
        WHEN REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') LIKE '%TB'
            THEN CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED) * 1000
        ELSE CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED)
    END AS capacity_gb
FROM ram_prices
WHERE REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') IS NOT NULL;

UPDATE ram_products p
JOIN (
    SELECT product_id, MIN(capacity_gb) AS capacity_gb
    FROM ram_options
    GROUP BY product_id
) o ON o.product_id = p.product_id
SET p.capacity_gb = o.capacity_gb
WHERE p.capacity_gb IS NULL;

SELECT 'RAM capacity_gb 채움' AS step, COUNT(*) AS filled
FROM ram_products WHERE capacity_gb IS NOT NULL;

-- ---------- 2) SSD 용량 실제 반영 ----------
DROP TABLE IF EXISTS ssd_options;
CREATE TABLE ssd_options (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    capacity_gb INT UNSIGNED NOT NULL,
    KEY idx_product (product_id)
);

INSERT INTO ssd_options (product_id, capacity_gb)
SELECT DISTINCT
    product_id,
    CASE
        WHEN REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') LIKE '%TB'
            THEN CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED) * 1000
        ELSE CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED)
    END AS capacity_gb
FROM ssd_prices
WHERE REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') IS NOT NULL;

UPDATE ssd_products p
JOIN (
    SELECT product_id, MIN(capacity_gb) AS capacity_gb
    FROM ssd_options
    GROUP BY product_id
) o ON o.product_id = p.product_id
SET p.capacity_gb = o.capacity_gb
WHERE p.capacity_gb IS NULL;

SELECT 'SSD capacity_gb 채움' AS step, COUNT(*) AS filled
FROM ssd_products WHERE capacity_gb IS NOT NULL;

-- ---------- 3) HDD 용량 채움 (지금까지 로직 자체가 없었음) ----------
DROP TABLE IF EXISTS hdd_options;
CREATE TABLE hdd_options (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    capacity_gb INT UNSIGNED NOT NULL,
    KEY idx_product (product_id)
);

INSERT INTO hdd_options (product_id, capacity_gb)
SELECT DISTINCT
    product_id,
    CASE
        WHEN REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') LIKE '%TB'
            THEN CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED) * 1000
        ELSE CAST(REGEXP_SUBSTR(REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)'), '^[0-9]+') AS UNSIGNED)
    END AS capacity_gb
FROM hdd_prices
WHERE REGEXP_SUBSTR(option_name, '^[0-9]+(GB|TB)') IS NOT NULL;

UPDATE hdd_products p
JOIN (
    SELECT product_id, MIN(capacity_gb) AS capacity_gb
    FROM hdd_options
    GROUP BY product_id
) o ON o.product_id = p.product_id
SET p.capacity_gb = o.capacity_gb
WHERE p.capacity_gb IS NULL;

SELECT 'HDD capacity_gb 채움' AS step, COUNT(*) AS filled
FROM hdd_products WHERE capacity_gb IS NOT NULL;

-- ---------- 4) Cooler TDP 채움 (지금까지 로직 자체가 없었음) ----------
-- spec_dump 확인 결과 spec_key='TDP', spec_value 예: '260W' 형태로 존재 (수랭/공랭 다수 상품에 있음, 없는 상품도 있음)
UPDATE cooler_products p
JOIN (
    SELECT product_id, MIN(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS tdp_w
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = 'TDP'
      AND spec_value REGEXP '^[0-9]+W$'
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.tdp_rating_w = t.tdp_w
WHERE p.tdp_rating_w IS NULL;

SELECT 'Cooler tdp_rating_w 채움' AS step, COUNT(*) AS filled
FROM cooler_products WHERE tdp_rating_w IS NOT NULL;

SELECT '05 보정 완료. Case 라디에이터 규격(top/side/rear)은 원본 데이터에 없어 이번엔 미채움 - 필요시 별도 논의 필요.' AS next_step;

-- ============================================================
-- 신규 요청 필드 채우기
-- ============================================================

-- ---------- CPU: 코어 수 / 스레드 수 (크롤링만, 매칭 미사용) ----------
UPDATE cpu_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS cores
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_key LIKE '%코어%' AND spec_value REGEXP '^[0-9]+개'
) t ON t.product_id = p.product_id
SET p.core_count = t.cores WHERE p.core_count IS NULL;

UPDATE cpu_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS threads
    FROM danawa_spec_summary
    WHERE category='cpu' AND spec_key LIKE '%스레드%' AND spec_value REGEXP '^[0-9]+개'
) t ON t.product_id = p.product_id
SET p.thread_count = t.threads WHERE p.thread_count IS NULL;

-- ---------- VGA: 사용전력(avg_power_w), VRAM 용량 ----------
UPDATE vga_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS w
    FROM danawa_spec_summary
    WHERE category='vga' AND spec_key LIKE '%사용전력%' AND spec_value REGEXP '[0-9]+W'
) t ON t.product_id = p.product_id
SET p.avg_power_w = t.w WHERE p.avg_power_w IS NULL;

UPDATE vga_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS vram
    FROM danawa_spec_summary
    WHERE category='vga' AND spec_key LIKE '%메모리 용량%' AND spec_value REGEXP '^[0-9]+GB'
) t ON t.product_id = p.product_id
SET p.vram_gb = t.vram WHERE p.vram_gb IS NULL;

-- ---------- MBoard: SATA3 포트 개수, VGA 연결방식, M.2 슬롯 정보 ----------
UPDATE mboard_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS sata_cnt
    FROM danawa_spec_summary
    WHERE category='mboard' AND spec_key LIKE '%SATA3%' AND spec_value REGEXP '^[0-9]+개'
) t ON t.product_id = p.product_id
SET p.sata3_port_count = t.sata_cnt WHERE p.sata3_port_count IS NULL;

UPDATE mboard_products p
JOIN (
    SELECT product_id, spec_value AS vga_slot
    FROM danawa_spec_summary
    WHERE category='mboard' AND (spec_key LIKE '%VGA 연결%' OR spec_key LIKE '%PCIe%슬롯%')
    GROUP BY product_id, spec_value
) t ON t.product_id = p.product_id
SET p.vga_slot_type = t.vga_slot WHERE p.vga_slot_type IS NULL;

UPDATE mboard_products p
JOIN (
    SELECT product_id, GROUP_CONCAT(DISTINCT spec_value ORDER BY spec_order SEPARATOR ', ') AS m2info
    FROM danawa_spec_summary
    WHERE category='mboard' AND (spec_key LIKE '%M.2%' OR spec_value LIKE '%M.2%')
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.m2_slot_info = t.m2info WHERE p.m2_slot_info IS NULL;

-- 위 3개는 다나와 실제 spec_key 표기가 확인 안 된 상태에서 짠 "최초 시도" 버전입니다.
-- 실행 후 0건이면 아래로 실제 표기를 먼저 확인해서 알려주세요:
-- SELECT DISTINCT spec_key, spec_value FROM danawa_spec_summary WHERE category='mboard' AND (spec_key LIKE '%SATA%' OR spec_key LIKE '%M.2%' OR spec_key LIKE '%PCIe%') LIMIT 50;

-- ---------- RAM: 속도(MHz), 히트싱크 높이 ----------
UPDATE ram_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(name, '[0-9]{4,5}') AS UNSIGNED) AS mhz
    FROM ram_products
    WHERE name REGEXP '[0-9]{4,5}(MHz|-)'
) t ON t.product_id = p.product_id
SET p.speed_mhz = t.mhz WHERE p.speed_mhz IS NULL;

UPDATE ram_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS h
    FROM danawa_spec_summary
    WHERE category='ram' AND spec_key LIKE '%높이%' AND spec_value REGEXP '[0-9]+mm'
) t ON t.product_id = p.product_id
SET p.heatsink_height_mm = t.h WHERE p.heatsink_height_mm IS NULL;

-- ---------- Power: 80PLUS 등급, ATX버전, 12VHPWR, SATA전원커넥터 개수 ----------
UPDATE power_products p
SET p.plus_grade = CASE
    WHEN p.name LIKE '%티타늄%' THEN '티타늄'
    WHEN p.name LIKE '%플래티넘%' THEN '플래티넘'
    WHEN p.name LIKE '%골드%' THEN '골드'
    WHEN p.name LIKE '%실버%' THEN '실버'
    WHEN p.name LIKE '%브론즈%' THEN '브론즈'
    ELSE NULL
END
WHERE p.plus_grade IS NULL;

UPDATE power_products p
SET p.atx_version = CASE
    WHEN p.name LIKE '%ATX3.1%' OR p.name LIKE '%ATX 3.1%' THEN 'ATX3.1'
    WHEN p.name LIKE '%ATX3.0%' OR p.name LIKE '%ATX 3.0%' THEN 'ATX3.0'
    ELSE NULL
END
WHERE p.atx_version IS NULL;

UPDATE power_products p
SET p.has_12vhpwr = CASE WHEN p.name LIKE '%12VHPWR%' OR p.name LIKE '%12V-2X6%' THEN 1 ELSE 0 END
WHERE p.has_12vhpwr IS NULL;

UPDATE power_products p
JOIN (
    SELECT product_id, CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED) AS cnt
    FROM danawa_spec_summary
    WHERE category='power' AND spec_key LIKE '%SATA%' AND spec_value REGEXP '^[0-9]+개'
) t ON t.product_id = p.product_id
SET p.sata_power_connector_count = t.cnt WHERE p.sata_power_connector_count IS NULL;

-- ---------- HDD: CMR/SMR ----------
UPDATE hdd_products p
JOIN (
    SELECT product_id,
           CASE WHEN MAX(CASE WHEN spec_value LIKE '%SMR%' THEN 1 ELSE 0 END)=1 THEN 'SMR'
                WHEN MAX(CASE WHEN spec_value LIKE '%CMR%' THEN 1 ELSE 0 END)=1 THEN 'CMR'
                ELSE NULL END AS rec_type
    FROM danawa_spec_summary
    WHERE category='hdd' AND (spec_value LIKE '%CMR%' OR spec_value LIKE '%SMR%')
    GROUP BY product_id
) t ON t.product_id = p.product_id
SET p.recording_type = t.rec_type WHERE p.recording_type IS NULL;
-- 요청사항: "CMR만 취급" -> 아래는 SMR로 확인된 상품을 카탈로그에서 실제로 제거하고 싶으실 때 사용
-- DELETE FROM hdd_products WHERE recording_type = 'SMR';

-- ---------- CPU/GPU tier_rank ----------
-- tier_rank(성능 등급)는 다나와에 없는 값이라 별도의 "성능 순위표"를 직접 만들어서
-- 매칭해야 합니다. 이건 이 스크립트로 자동 채울 수 없고, 순위 기준(문서/합의된 리스트)을
-- 알려주시면 performance_tier.sql 처럼 순위 매핑 스크립트를 별도로 만들어드리겠습니다.

SELECT '04 완료. 신규 필드 중 tier_rank는 별도 순위표 작업 필요, mboard 3종은 실제 spec_key 확인 필요.' AS next_step;
