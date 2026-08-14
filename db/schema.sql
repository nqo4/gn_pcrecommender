-- ============================================================
-- 개인 PC 사양 추천 시스템 — DB 스키마 (MySQL)
-- 출처: https://github.com/neungjichai/Danawa-DB (New_crawler/danawa_only_load.sql
--       의 최종 products 테이블 + add_compat_columns.sql)를 그대로 가져왔다.
--
-- *** 원본과 다른 점 ***
-- 1) staging/unpivot/date_map 등 CSV 적재 중간 테이블은 뺐다 — 원본은
--    crawl_data/*.csv를 LOAD DATA INFILE로 읽는데, 이 CSV는 실제 크롤링
--    결과물이라 이 프로젝트엔 없다. 최종 products/prices 테이블 구조만
--    그대로 가져오고, 목업 데이터를 여기 바로 INSERT한다.
-- 2) 저장소에 없는 컬럼을 일부 추가했다(아래 "★ 저장소에 없어서 추가" 표시) —
--    원본 add_compat_columns.sql은 쿨러 냉각 용량(TDP 감당치), 라디에이터
--    크기, RAM/SSD/HDD 용량 컬럼이 없어서 수랭 매칭·용량 기반 검색이
--    불가능했다. 기획서 5.1절 조건을 실제로 계산하려면 필요해서 추가했다.
-- 3) [갱신] 실데이터 파이프라인과 코드가 쓰는 스키마에 맞췄다:
--    - cpu/vga_products.tier_rank (New_crawler/performance_tier.sql이 ALTER로
--      추가하는 컬럼 — core/algorithm.py가 후보 필터링에 직접 사용)
--    - cooler_products.tdp_rating_w (예전 이름 max_tdp_w는 코드 어디서도 안
--      쓰고, db/add_cooler_tdp_column.sql·core/algorithm.py가 이 이름을 씀)
--    - game_requirements: New_crawler/game_requirements_schema.sql 구조 그대로
--      (api/server.py가 game_name/cpu_tier_rank/storage_gb를 조회함)
--    - usage_profiles.required_ssd_gb/required_hdd_gb (update_usage_profiles_v2.sql)
--    - danawa_spec_summary (spec_scraper.py 구조 — algorithm.py가 RAM 방열판
--      높이 등을 여기서 직접 조회하므로 목업 DB에도 테이블 자체는 있어야 함)
-- ============================================================

-- [갱신] CREATE DATABASE/USE 문은 제거 — 대상 DB는 db/db.py의 init_db가
-- DANAWA_DB_NAME 환경변수(기본 DW_db)로 만들고 선택한다. 실크롤링 데이터가
-- 든 DW_db를 실수로 날리지 않도록, 목업 테스트는 DANAWA_DB_NAME을 다른
-- 이름으로 주고 돌리면 된다. (mysql CLI로 직접 실행할 땐
--  mysql ... <DB명> < schema.sql 처럼 DB를 지정해서 실행)

-- ---------------- CPU ----------------
DROP TABLE IF EXISTS cpu_products;
CREATE TABLE cpu_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    has_igpu     VARCHAR(10)  NULL,
    power_min_w  SMALLINT UNSIGNED NULL,
    power_max_w  SMALLINT UNSIGNED NULL,
    socket       VARCHAR(30)  NULL,         -- add_compat_columns.sql
    tier_rank    INT NULL                   -- performance_tier.sql (기획서 6.2 성능 등급)
);

DROP TABLE IF EXISTS cpu_prices;
CREATE TABLE cpu_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- VGA ----------------
DROP TABLE IF EXISTS vga_products;
CREATE TABLE vga_products (
    product_id        BIGINT UNSIGNED PRIMARY KEY,
    name              VARCHAR(500),
    company           VARCHAR(50),
    usage_type        VARCHAR(20),
    length_mm         SMALLINT UNSIGNED NULL,   -- add_compat_columns.sql
    recommended_psu_w SMALLINT UNSIGNED NULL,   -- add_compat_columns.sql
    power_connector   VARCHAR(50) NULL,         -- add_compat_columns.sql
    tier_rank         INT NULL                  -- performance_tier.sql (기획서 6.1 성능 등급)
);

DROP TABLE IF EXISTS vga_prices;
CREATE TABLE vga_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 메인보드 ----------------
DROP TABLE IF EXISTS mboard_products;
CREATE TABLE mboard_products (
    product_id      BIGINT UNSIGNED PRIMARY KEY,
    name            VARCHAR(500),
    company         VARCHAR(50),
    usage_type      VARCHAR(20),
    ram_slot_count  TINYINT UNSIGNED NULL,
    socket          VARCHAR(30) NULL,           -- add_compat_columns.sql
    form_factor     VARCHAR(20) NULL,           -- add_compat_columns.sql
    ram_type        VARCHAR(10) NULL            -- add_compat_columns.sql
);

DROP TABLE IF EXISTS mboard_prices;
CREATE TABLE mboard_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- RAM ----------------
DROP TABLE IF EXISTS ram_products;
CREATE TABLE ram_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    ram_type     VARCHAR(10) NULL,              -- add_compat_columns.sql
    capacity_gb  SMALLINT UNSIGNED NULL,         -- ★ 저장소에 없어서 추가(용량 검색에 필수)
    speed_mhz    SMALLINT UNSIGNED NULL          -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS ram_prices;
CREATE TABLE ram_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- SSD ----------------
DROP TABLE IF EXISTS ssd_products;
CREATE TABLE ssd_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    capacity_gb  SMALLINT UNSIGNED NULL,         -- ★ 저장소에 없어서 추가
    interface    VARCHAR(30) NULL                -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS ssd_prices;
CREATE TABLE ssd_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- HDD ----------------
DROP TABLE IF EXISTS hdd_products;
CREATE TABLE hdd_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    capacity_gb  SMALLINT UNSIGNED NULL          -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS hdd_prices;
CREATE TABLE hdd_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 쿨러 ----------------
DROP TABLE IF EXISTS cooler_products;
CREATE TABLE cooler_products (
    product_id       BIGINT UNSIGNED PRIMARY KEY,
    name             VARCHAR(500),
    company          VARCHAR(50),
    usage_type       VARCHAR(20),
    support_sockets  VARCHAR(300) NULL,          -- add_compat_columns.sql
    height_mm        SMALLINT UNSIGNED NULL,     -- add_compat_columns.sql
    cooler_type      VARCHAR(20) NULL,           -- add_compat_columns.sql
    radiator_length_mm    SMALLINT UNSIGNED NULL,  -- cooler_radiator_type_fill.sql(라디에이터 실측 길이, 예: 282/402)
    radiator_thickness_mm SMALLINT UNSIGNED NULL,  -- cooler_radiator_type_fill.sql
    tdp_rating_w          SMALLINT UNSIGNED NULL   -- add_cooler_tdp_column.sql(CPU 발열 감당 검증에 필수)
);

DROP TABLE IF EXISTS cooler_prices;
CREATE TABLE cooler_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 파워(PSU) ----------------
DROP TABLE IF EXISTS power_products;
CREATE TABLE power_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    rated_w      SMALLINT UNSIGNED NULL,         -- add_compat_columns.sql
    form_factor  VARCHAR(20) NULL                -- add_compat_columns.sql
);

DROP TABLE IF EXISTS power_prices;
CREATE TABLE power_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 케이스 ----------------
DROP TABLE IF EXISTS case_products;
CREATE TABLE case_products (
    product_id               BIGINT UNSIGNED PRIMARY KEY,
    name                     VARCHAR(500),
    company                  VARCHAR(50),
    usage_type               VARCHAR(20),
    support_form_factors     VARCHAR(100) NULL,  -- add_compat_columns.sql
    max_cooler_height_mm     SMALLINT UNSIGNED NULL,  -- add_compat_columns.sql
    max_vga_length_mm        SMALLINT UNSIGNED NULL,  -- add_compat_columns.sql
    support_psu_form_factors VARCHAR(50) NULL,   -- add_compat_columns.sql
    -- 라디에이터 지원 규격(위치별) — New_crawler/add_missing_spec_columns.sql·
    -- fill_missing_specs.sql과 동일 컬럼명/구조(예: "240,280,360"). 수랭 쿨러가
    -- 실제로 이 케이스에 들어가는지 확인하려면 필요(현재 core/algorithm.py는
    -- 아직 이 컬럼들을 안 씀 — 케이스↔라디에이터 호환 체크가 미구현 상태로
    -- 남아있는 항목, README에도 명시된 한계).
    radiator_top_mm          VARCHAR(50) NULL,
    radiator_side_mm         VARCHAR(50) NULL,
    radiator_rear_mm         VARCHAR(50) NULL,
    radiator_front_mm        VARCHAR(50) NULL
);

DROP TABLE IF EXISTS case_prices;
CREATE TABLE case_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ============================================================
-- 최신가 뷰(*_products_v)는 여기 없다 — db/create_price_views.sql이 유일한
-- 정의처다(예전엔 두 파일에 중복돼 있어 한쪽만 고치면 어긋났다).
-- db/db.py의 init_db가 schema.sql -> seed_data.sql -> create_price_views.sql
-- 순서로 실행해서 목업 DB에도 같은 뷰가 만들어진다.
-- ============================================================

-- ============================================================
-- 게임/용도 요구사양 (기획서 2.1절)
-- game_requirements는 New_crawler/game_requirements_schema.sql과 동일 구조 —
-- api/server.py가 game_name/cpu_tier_rank/gpu_tier_rank/ram_gb/storage_gb를
-- 그대로 조회하므로 목업 DB도 같은 컬럼명을 써야 한다.
-- ============================================================
DROP TABLE IF EXISTS game_requirements;
CREATE TABLE game_requirements (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    game_name           VARCHAR(100) NOT NULL UNIQUE,

    -- 권장 사양 (이 시스템의 기준 사양 - 최소사양은 사용하지 않음)
    cpu_tier_rank       INT NULL,          -- cpu_performance_tier.tier_rank 참조
    cpu_display         VARCHAR(50) NULL,  -- 원문 표기, 예: "i7-13700"
    gpu_tier_rank       INT NULL,          -- gpu_performance_tier.tier_rank 참조
    gpu_display         VARCHAR(50) NULL,  -- 예: "RTX 4070"
    ram_gb              SMALLINT UNSIGNED NULL,
    storage_gb          SMALLINT UNSIGNED NULL,

    source_url          VARCHAR(300) NULL,
    updated_at          DATE NULL,

    INDEX idx_cpu (cpu_tier_rank),
    INDEX idx_gpu (gpu_tier_rank)
);

-- required_ssd_gb/required_hdd_gb: update_usage_profiles_v2.sql에서 추가된
-- 컬럼(용도별 저장장치 요구량) — merge_requirements가 사용.
DROP TABLE IF EXISTS usage_profiles;
CREATE TABLE usage_profiles (
    id                  INT PRIMARY KEY,
    code                VARCHAR(30) NOT NULL,
    display_name        VARCHAR(50) NOT NULL,
    required_cpu_tier   TINYINT,
    required_gpu_tier   TINYINT,
    required_ram_gb     SMALLINT,
    required_ram_type   VARCHAR(10) NULL,
    required_ssd_gb     SMALLINT UNSIGNED NULL,
    required_hdd_gb     SMALLINT UNSIGNED NULL DEFAULT 0
);

-- ============================================================
-- 부품 사진/링크 (실제 저장소의 spec_scraper.py가 만드는 product_media
-- 테이블과 같은 구조 — 나중에 실제 덤프가 들어오면 코드 변경 없이
-- 그대로 연결된다. 지금은 목업 플레이스홀더 이미지로 채운다.
-- ※ image_url만 원본(VARCHAR(500))과 달리 TEXT — 목업이 base64 data URI를
--   넣는데 500자를 넘기 때문. 실제 덤프(URL)와도 호환된다.
-- ============================================================
DROP TABLE IF EXISTS product_media;
CREATE TABLE product_media (
    category    VARCHAR(20) NOT NULL,
    product_id  BIGINT UNSIGNED NOT NULL,
    image_url   TEXT NULL,
    product_url VARCHAR(300) NULL,
    PRIMARY KEY (category, product_id)
);

-- ============================================================
-- 다나와 스펙 요약 (spec_scraper.py의 CREATE TABLE과 동일 구조).
-- core/algorithm.py가 RAM 방열판 높이 등을 이 테이블에서 직접 조회하므로
-- 목업 DB에도 테이블 자체는 있어야 한다(비어 있으면 해당 값이 NULL로
-- 조회될 뿐 에러는 없다).
-- ============================================================
DROP TABLE IF EXISTS danawa_spec_summary;
CREATE TABLE danawa_spec_summary (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    category    VARCHAR(20) NOT NULL,
    product_id  BIGINT UNSIGNED NOT NULL,
    spec_key    VARCHAR(150),
    spec_value  VARCHAR(300) NOT NULL,
    spec_order  INT NOT NULL,
    scraped_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_lookup (category, product_id)
);
