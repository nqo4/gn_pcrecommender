-- ============================================================
-- add_matching_guide_columns.sql로 추가한 컬럼을 danawa_spec_summary
-- 원본 데이터에서 채운다. 전제조건: add_matching_guide_columns.sql 먼저 실행.
-- ============================================================
USE dw_db;
SET NAMES utf8mb4;
SET SQL_SAFE_UPDATES = 0;

-- ------------------------------------------------------------
-- 1) 메인보드 최대 메모리 지원 속도(MHz)
-- 실제 형태: "[메모리]" 섹션 마커(spec_key NULL) 바로 다음 줄(spec_key NULL)에
-- "6400MHz (PC5-51200)" 또는 "PC4-34100 (4,200MHz)"처럼 MHz 숫자가 있다 —
-- 두 형태 다 "[0-9,]+MHz" 패턴으로 잡힌다(콤마 섞인 표기도 나중에 제거).
-- LPDDR4처럼 MHz 표기가 아예 없는 행은 매치 안 돼 NULL로 남는다(정상).
-- ------------------------------------------------------------
UPDATE mboard_products p
JOIN danawa_spec_summary marker
    ON marker.category = 'mboard' AND marker.product_id = p.product_id
   AND marker.spec_key IS NULL AND marker.spec_value = '[메모리]'
JOIN danawa_spec_summary speed
    ON speed.category = 'mboard' AND speed.product_id = p.product_id
   AND speed.spec_order = marker.spec_order + 1
SET p.max_memory_speed_mhz = CAST(REPLACE(REPLACE(REGEXP_SUBSTR(speed.spec_value, '[0-9,]+MHz'), 'MHz', ''), ',', '') AS UNSIGNED)
WHERE speed.spec_value REGEXP '[0-9,]+MHz'
  AND p.max_memory_speed_mhz IS NULL;

-- ------------------------------------------------------------
-- 3-a) 메인보드 M.2 슬롯 최대 PCIe 버전
-- "M.2 연결" spec_value가 "PCIe5.0, PCIe4.0, NVMe, SATA"처럼 콤마 나열이라,
-- 가장 높은 버전 하나만 우선순위로 채운다(5.0 -> 4.0 -> 3.0 순, 버전 번호가
-- 아예 없이 "PCIe"만 있으면 구세대로 보고 NULL — 과도한 배제 방지 위해
-- 매칭 검증에서는 NULL을 "제약 없음"으로 취급한다).
-- ------------------------------------------------------------
UPDATE mboard_products p
JOIN danawa_spec_summary s ON s.category = 'mboard' AND s.product_id = p.product_id AND s.spec_key = 'M.2 연결'
SET p.m2_max_pcie_version = 5.0
WHERE s.spec_value LIKE '%PCIe5.0%' AND p.m2_max_pcie_version IS NULL;

UPDATE mboard_products p
JOIN danawa_spec_summary s ON s.category = 'mboard' AND s.product_id = p.product_id AND s.spec_key = 'M.2 연결'
SET p.m2_max_pcie_version = 4.0
WHERE s.spec_value LIKE '%PCIe4.0%' AND p.m2_max_pcie_version IS NULL;

UPDATE mboard_products p
JOIN danawa_spec_summary s ON s.category = 'mboard' AND s.product_id = p.product_id AND s.spec_key = 'M.2 연결'
SET p.m2_max_pcie_version = 3.0
WHERE s.spec_value LIKE '%PCIe3.0%' AND p.m2_max_pcie_version IS NULL;

-- ------------------------------------------------------------
-- 3-b) SSD 폼팩터/인터페이스
-- 스펙 0번째 줄(spec_order=0)이 폼팩터: "M.2 (2280)"/"M.2 (2242)"/"M.2 (2230)"
-- 또는 "6.4cm(2.5형)"(2.5인치 SATA). 1번째 줄(spec_order=1)이 인터페이스:
-- "SATA3 (6Gb"/"PCIe3.0x4 (32GT"/"PCIe4.0x4 (64GT"/"PCIe5.0x4 (128GT"/
-- "U.2 (PCIe4.0x4)" 등 — 원본 크롤링이 "6Gb/s)"의 "/"를 필드 구분자로 오인해서
-- 다음 행에 "s)"만 남기고 짤린 형태라, 여기선 그 앞부분만으로 충분히 판별된다.
-- ------------------------------------------------------------
UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 0
SET p.m2_form_factor = REGEXP_SUBSTR(s.spec_value, '[0-9]{4}')
WHERE s.spec_value LIKE 'M.2%' AND p.m2_form_factor IS NULL;

UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 0
SET p.m2_form_factor = '2.5'
WHERE s.spec_value LIKE '%2.5형%' AND p.m2_form_factor IS NULL;

UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 1
SET p.is_sata_interface = 1
WHERE s.spec_value LIKE 'SATA%' AND p.is_sata_interface IS NULL;

UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 1
SET p.is_sata_interface = 0, p.pcie_version = 5.0
WHERE s.spec_value LIKE '%PCIe5.0%' AND p.is_sata_interface IS NULL;

UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 1
SET p.is_sata_interface = 0, p.pcie_version = 4.0
WHERE s.spec_value LIKE '%PCIe4.0%' AND p.is_sata_interface IS NULL;

UPDATE ssd_products p
JOIN danawa_spec_summary s ON s.category = 'ssd' AND s.product_id = p.product_id AND s.spec_order = 1
SET p.is_sata_interface = 0, p.pcie_version = 3.0
WHERE s.spec_value LIKE '%PCIe3.0%' AND p.is_sata_interface IS NULL;

-- ------------------------------------------------------------
-- 4) PSU SATA 전원 커넥터 개수 — spec_key='SATA', spec_value가 "6개" 형태.
-- ------------------------------------------------------------
UPDATE power_products p
JOIN danawa_spec_summary s ON s.category = 'power' AND s.product_id = p.product_id AND s.spec_key = 'SATA'
SET p.sata_connector_count = CAST(REGEXP_SUBSTR(s.spec_value, '[0-9]+') AS UNSIGNED)
WHERE p.sata_connector_count IS NULL;

-- ------------------------------------------------------------
-- 5) GPU VRAM(GB) — 별도 spec_key가 없고 상품명에 항상 포함돼 있다
-- (예: "...RTX 4070 SUPER GAMING OC D6X 12GB"). D6/D6X/D7 등 메모리 타입
-- 표기 뒤, 실제 용량 숫자만 "GB" 바로 앞에서 뽑는다.
-- ------------------------------------------------------------
UPDATE vga_products
SET vram_gb = CAST(REGEXP_SUBSTR(name, '[0-9]+(?=GB)') AS UNSIGNED)
WHERE name REGEXP '[0-9]+GB' AND vram_gb IS NULL;

SELECT 'mboard max_memory_speed_mhz' info, COUNT(*) cnt FROM mboard_products WHERE max_memory_speed_mhz IS NOT NULL
UNION ALL SELECT 'mboard m2_max_pcie_version', COUNT(*) FROM mboard_products WHERE m2_max_pcie_version IS NOT NULL
UNION ALL SELECT 'ssd m2_form_factor', COUNT(*) FROM ssd_products WHERE m2_form_factor IS NOT NULL
UNION ALL SELECT 'ssd is_sata_interface', COUNT(*) FROM ssd_products WHERE is_sata_interface IS NOT NULL
UNION ALL SELECT 'power sata_connector_count', COUNT(*) FROM power_products WHERE sata_connector_count IS NOT NULL
UNION ALL SELECT 'vga vram_gb', COUNT(*) FROM vga_products WHERE vram_gb IS NOT NULL;
