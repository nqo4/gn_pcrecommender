-- ============================================================
-- 03. 부품 상세 정보 컬럼 추가 (v2: 컬럼별로 ALTER TABLE 분리)
--
-- 02_부품별_가격정보.sql 로 만들어진 카탈로그 테이블(*_products)에
-- 다나와 상세페이지에서만 얻을 수 있는 스펙 컬럼들을 추가.
-- (가격 비교 CSV에는 없는 정보라 spec_scraper.py로 상세페이지를 따로 긁어서 채움)
--
-- 실행 순서: 02_부품별_가격정보.sql 다음, spec_scraper.py --all 실행 전/후 아무 때나
--            (컬럼만 추가하는 단계라 spec_scraper 순서와 무관 - 실제 값 채우기는 04에서 함)
-- 주의: MySQL은 ADD COLUMN IF NOT EXISTS를 지원하지 않아 IF NOT EXISTS를 제거함.
-- 따라서 이 스크립트는 "처음 한 번만" 실행해야 함(멱등 아님).
-- 재실행 시 "Duplicate column name" 에러가 나면 이미 추가된 컬럼이라는 뜻이니
-- 해당 줄만 무시하고 넘어가면 됨.
-- ============================================================
USE DW_db;

-- ---------- CPU ----------
-- has_igpu/power_min_w/power_max_w는 02에서 이미 컬럼과 함께 테이블이 만들어지므로 여기선 socket만 추가
ALTER TABLE cpu_products ADD COLUMN socket VARCHAR(30) NULL;
ALTER TABLE cpu_products ADD COLUMN tier_rank INT NULL;      -- 성능 등급 (13/14세대+울트라 라인업 정리 후 채움)

-- ---------- VGA ----------
ALTER TABLE vga_products ADD COLUMN length_mm SMALLINT UNSIGNED NULL;
ALTER TABLE vga_products ADD COLUMN recommended_psu_w SMALLINT UNSIGNED NULL;
ALTER TABLE vga_products ADD COLUMN power_connector VARCHAR(50) NULL;
ALTER TABLE vga_products ADD COLUMN tier_rank INT NULL;

-- ---------- RAM ----------
ALTER TABLE ram_products ADD COLUMN capacity_gb SMALLINT UNSIGNED NULL;  -- 단일 모듈/키트 총용량
ALTER TABLE ram_products ADD COLUMN ram_type VARCHAR(10) NULL;           -- DDR4 / DDR5

-- ---------- SSD ----------
ALTER TABLE ssd_products ADD COLUMN capacity_gb INT UNSIGNED NULL;       -- 예: 500, 1000, 2000

-- ---------- HDD ----------
ALTER TABLE hdd_products ADD COLUMN capacity_gb INT UNSIGNED NULL;       -- 예: 1000, 2000, 4000

-- ---------- MBoard ----------
ALTER TABLE mboard_products ADD COLUMN socket VARCHAR(30) NULL;
ALTER TABLE mboard_products ADD COLUMN form_factor VARCHAR(20) NULL;        -- ATX / M-ATX / ITX 등
ALTER TABLE mboard_products ADD COLUMN ram_type VARCHAR(10) NULL;           -- DDR4 / DDR5
ALTER TABLE mboard_products ADD COLUMN ram_slot_count TINYINT UNSIGNED NULL;

-- ---------- Cooler ----------
ALTER TABLE cooler_products ADD COLUMN support_sockets VARCHAR(300) NULL;   -- 예: "LGA1700,AM5,AM4"
ALTER TABLE cooler_products ADD COLUMN height_mm SMALLINT UNSIGNED NULL;
ALTER TABLE cooler_products ADD COLUMN cooler_type VARCHAR(20) NULL;        -- 공랭 / 수랭 구분
ALTER TABLE cooler_products ADD COLUMN radiator_length_mm SMALLINT UNSIGNED NULL;
ALTER TABLE cooler_products ADD COLUMN radiator_thickness_mm SMALLINT UNSIGNED NULL;
ALTER TABLE cooler_products ADD COLUMN tdp_rating_w SMALLINT UNSIGNED NULL; -- 감당 가능 TDP(W)

-- ---------- Power ----------
ALTER TABLE power_products ADD COLUMN rated_w SMALLINT UNSIGNED NULL;
ALTER TABLE power_products ADD COLUMN form_factor VARCHAR(20) NULL;        -- ATX / SFX / SFX-L 등

-- ---------- Case ----------
ALTER TABLE case_products ADD COLUMN support_form_factors VARCHAR(100) NULL;   -- 예: "ATX,M-ATX,ITX"
ALTER TABLE case_products ADD COLUMN max_cooler_height_mm SMALLINT UNSIGNED NULL;
ALTER TABLE case_products ADD COLUMN max_vga_length_mm SMALLINT UNSIGNED NULL;
ALTER TABLE case_products ADD COLUMN support_psu_form_factors VARCHAR(50) NULL; -- 예: "ATX,SFX"
ALTER TABLE case_products ADD COLUMN radiator_top_mm  VARCHAR(50) NULL;        -- 상단 라디에이터 지원 규격
ALTER TABLE case_products ADD COLUMN radiator_side_mm VARCHAR(50) NULL;
ALTER TABLE case_products ADD COLUMN radiator_rear_mm VARCHAR(50) NULL;

-- ============================================================
-- 신규 요청 필드 (기존 스크립트에 없던 것들, 이번에 추가)
-- ============================================================

-- ---------- CPU ----------
-- tier_rank는 03 앞부분에서 이미 추가함(성능 등급). 여기선 코어/스레드 수만 추가(크롤링만, 매칭 미사용)
ALTER TABLE cpu_products ADD COLUMN core_count TINYINT UNSIGNED NULL;
ALTER TABLE cpu_products ADD COLUMN thread_count TINYINT UNSIGNED NULL;

-- ---------- VGA ----------
-- tier_rank, length_mm, recommended_psu_w, power_connector는 이미 위에서 추가됨
ALTER TABLE vga_products ADD COLUMN avg_power_w SMALLINT UNSIGNED NULL;   -- 실사용 전력(사용전력 항목에서 파싱)
ALTER TABLE vga_products ADD COLUMN vram_gb TINYINT UNSIGNED NULL;       -- VRAM 용량(크롤링만, 매칭 미사용)

-- ---------- MBoard ----------
ALTER TABLE mboard_products ADD COLUMN ram_speed_max_mhz SMALLINT UNSIGNED NULL;  -- 지원 메모리 속도 상한(MHz)
ALTER TABLE mboard_products ADD COLUMN sata3_port_count TINYINT UNSIGNED NULL;    -- SATA3 포트 개수
ALTER TABLE mboard_products ADD COLUMN vga_slot_type VARCHAR(30) NULL;           -- VGA 연결방식(예: PCIe5.0x16)
ALTER TABLE mboard_products ADD COLUMN m2_slot_info VARCHAR(300) NULL;          -- M.2 슬롯 정보(폼팩터/프로토콜/PCIe버전/개수, 콤마구분)

-- ---------- RAM ----------
ALTER TABLE ram_products ADD COLUMN speed_mhz SMALLINT UNSIGNED NULL;            -- 상품명에서 파싱
ALTER TABLE ram_products ADD COLUMN heatsink_height_mm SMALLINT UNSIGNED NULL;   -- 쿨러 간섭 체크용

-- ---------- Power(PSU) ----------
ALTER TABLE power_products ADD COLUMN plus_grade VARCHAR(20) NULL;         -- 80PLUS 등급(브론즈/실버/골드/플래티넘/티타늄)
ALTER TABLE power_products ADD COLUMN atx_version VARCHAR(20) NULL;        -- ATX3.0 / ATX3.1 등
ALTER TABLE power_products ADD COLUMN has_12vhpwr TINYINT(1) NULL;         -- 12VHPWR 커넥터 지원 여부(0/1)
ALTER TABLE power_products ADD COLUMN sata_power_connector_count TINYINT UNSIGNED NULL;  -- SATA 전원 커넥터 개수

-- ---------- HDD ----------
ALTER TABLE hdd_products ADD COLUMN recording_type VARCHAR(10) NULL;       -- CMR / SMR

SELECT '컬럼 추가 완료. 다음으로 spec_scraper.py --all 실행 후 04_부품별_업데이트.sql 을 실행하세요.' AS next_step;
