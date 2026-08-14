-- ============================================================
-- 확장 스펙 컬럼 추가 (2차) — 기존 add_compat_columns.sql이 다루는
-- "호환성 필수" 컬럼과 별개로, 지금까지 danawa_spec_summary에만 있고
-- 아무 데도 안 쓰이던 항목 중 실사용자가 구조화 컬럼으로 승격하기로
-- 선택한 것들.
--
-- 실행 순서: danawa_only_load.sql + add_compat_columns.sql +
--            spec_scraper.py(대상 카테고리) 실행 완료 후, 이 파일 ->
--            fill_extended_specs.sql 순서로 실행.
-- ============================================================
USE DW_db;

-- ---------------- CPU ----------------
-- 시네벤치 점수는 향후 이름 매칭(performance_tier.sql) 대신 벤치마크 기반
-- tier_rank 산출의 근거로 쓸 수 있다.
ALTER TABLE cpu_products
    ADD COLUMN cinebench_single INT UNSIGNED NULL,
    ADD COLUMN cinebench_multi  INT UNSIGNED NULL,
    ADD COLUMN memory_support   VARCHAR(30) NULL;

-- ---------------- VGA ----------------
ALTER TABLE vga_products
    ADD COLUMN output_ports VARCHAR(100) NULL,
    ADD COLUMN power_draw_w SMALLINT UNSIGNED NULL;

-- ---------------- 메인보드 ----------------
ALTER TABLE mboard_products
    ADD COLUMN sata3_count    TINYINT UNSIGNED NULL,
    ADD COLUMN pcie_version   VARCHAR(10) NULL,
    ADD COLUMN pcie_x16_count TINYINT UNSIGNED NULL,
    ADD COLUMN m2_slot_count  TINYINT UNSIGNED NULL,
    ADD COLUMN vga_connection VARCHAR(30) NULL;

-- ---------------- RAM ----------------
-- heatsink_height_mm: core/algorithm.py가 RAM 후보 조회 때마다 danawa_spec_summary를
-- 상관 서브쿼리로 조인해서 얻던 값을 실제 컬럼으로 승격 — 조회가 단순해지고 빨라진다.
ALTER TABLE ram_products
    ADD COLUMN stick_count        TINYINT UNSIGNED NULL,
    ADD COLUMN heatsink_height_mm SMALLINT UNSIGNED NULL;

-- ---------------- 파워(PSU) ----------------
-- pcie_16pin_connector: core/psu_rules.py의 has_atx3_support()가 지금 상품명
-- 텍스트에서 "ATX 3.0"/"12VHPWR" 문구를 정규식으로 추측하는데, 이 컬럼이
-- 진짜 스펙 출처다 — 나중에 알고리즘을 이 컬럼 기준으로 바꾸면 이름 텍스트
-- 추측 없이 확정적으로 판정 가능(화재 위험까지 걸린 안전 규칙이라 중요).
ALTER TABLE power_products
    ADD COLUMN depth_mm             SMALLINT UNSIGNED NULL,
    ADD COLUMN voltage_regulation   VARCHAR(20) NULL,
    ADD COLUMN eta_certification    VARCHAR(20) NULL,
    ADD COLUMN lambda_certification VARCHAR(20) NULL,
    ADD COLUMN pcie_16pin_connector VARCHAR(30) NULL;

-- ---------------- 케이스 ----------------
-- ext_ 접두사: 케이스 "외형" 치수라는 뜻 — cooler_products.height_mm 등
-- 다른 테이블의 동명 컬럼과 의미가 다르므로 접두사로 구분했다.
ALTER TABLE case_products
    ADD COLUMN ext_width_mm      SMALLINT UNSIGNED NULL,
    ADD COLUMN ext_depth_mm      SMALLINT UNSIGNED NULL,
    ADD COLUMN ext_height_mm     SMALLINT UNSIGNED NULL,
    ADD COLUMN panel_type        VARCHAR(30) NULL,
    ADD COLUMN fan_count         TINYINT UNSIGNED NULL,
    ADD COLUMN psu_position      VARCHAR(20) NULL,
    ADD COLUMN psu_max_length_mm SMALLINT UNSIGNED NULL;

SELECT '확장 스펙 컬럼 추가 완료 — 다음은 fill_extended_specs.sql 실행' AS next_step;
