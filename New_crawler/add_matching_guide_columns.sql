-- ============================================================
-- "PC 용도별 부품 매칭 로직" 문서(실사용자 제공)의 알고리즘 규칙 중,
-- 아직 core/algorithm.py에 반영 안 돼 있던 항목들을 위한 신규 컬럼.
--
--   1. RAM-메인보드 속도 매칭(2절) — mboard_products.max_memory_speed_mhz
--   3. M.2 SSD 매칭(7절) — ssd_products.m2_form_factor/is_sata_interface/
--      pcie_version, mboard_products.m2_max_pcie_version
--   4. SATA 매칭(8절, PSU 커넥터 개수만) — power_products.sata_connector_count
--      (케이스 드라이브 베이 개수는 원본 크롤링 데이터 자체에 없어 반영 불가)
--   5. 3D렌더링 GPU VRAM 최소치 — vga_products.vram_gb
--
-- (2. 케이스-라디에이터 매칭은 case_products.radiator_top/side/rear/front_mm이
-- 이미 있어서 새 컬럼 불필요 — core/algorithm.py 로직만 이 컬럼을 쓰도록 변경)
-- ============================================================
USE dw_db;

ALTER TABLE mboard_products ADD COLUMN max_memory_speed_mhz SMALLINT UNSIGNED NULL;
ALTER TABLE mboard_products ADD COLUMN m2_max_pcie_version DECIMAL(2,1) NULL;

ALTER TABLE ssd_products ADD COLUMN m2_form_factor VARCHAR(10) NULL;
ALTER TABLE ssd_products ADD COLUMN is_sata_interface TINYINT(1) NULL;
ALTER TABLE ssd_products ADD COLUMN pcie_version DECIMAL(2,1) NULL;

ALTER TABLE power_products ADD COLUMN sata_connector_count TINYINT UNSIGNED NULL;

ALTER TABLE vga_products ADD COLUMN vram_gb TINYINT UNSIGNED NULL;

ALTER TABLE usage_profiles ADD COLUMN required_vram_gb TINYINT UNSIGNED NULL;

SELECT '완료 — 부품매칭가이드 관련 컬럼 8개 추가됨(*_v 뷰는 별도로 재생성 필요 — db/create_price_views.sql)' AS info;
