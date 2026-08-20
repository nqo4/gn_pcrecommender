-- ============================================================
-- 01. 부품 제외 처리 정책 (개인용 PC에 맞지 않는 부품 필터링 기준)
--
-- 목적: "어떤 부품을 왜 빼는지"를 한 곳(이 파일)에서만 관리.
--       기존에는 이 조건들이 danawa_only_load.sql 안에 카테고리마다
--       하드코딩되어 있어서 수정할 때마다 여러 군데를 찾아 고쳐야 했음.
--       이제부터는 이 파일에 keyword(테이블 행)를 추가/삭제하는 것만으로
--       모든 카테고리 로딩 스크립트(02)에 자동 반영됨.
--
-- 실행 순서: 이 파일을 가장 먼저 실행 (DB를 새로 만들기 때문에 danawa_only_load류
--            스크립트보다 먼저 와야 함). 그 다음 02_부품별_가격정보.sql 실행.
--
-- 제외 기준 두 종류:
--   1) exclusion_keywords : 상품명에 특정 문자열이 포함되면 제외 (LIKE '%keyword%')
--   2) exclusion_regex    : 단순 키워드로 못 잡는 패턴(정규식)으로 제외
--      예) SSD 삼성 OEM/노트북 납품용 라인(PM981/PM9A1/BM9C1 등)은
--          이름에 "해외"라고 안 써있지만 정식 소매 유통이 없는 사실상 그레이마켓 제품이라
--          정규식으로 따로 잡아야 함.
--
-- category 값은 'ALL'(모든 카테고리 공통) 또는
-- cpu/vga/ram/ssd/hdd/mboard/cooler/power/case 중 하나.
-- (모니터는 사용하지 않아 카탈로그에서 완전히 제외 - 대상에 없음)
-- ============================================================

DROP DATABASE IF EXISTS dw_db;
CREATE DATABASE dw_db DEFAULT CHARACTER SET utf8mb4;
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- 1) 키워드 기반 제외 ----------
DROP TABLE IF EXISTS exclusion_keywords;
CREATE TABLE exclusion_keywords (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    category VARCHAR(10) NOT NULL,   -- 'ALL' 또는 cpu/vga/ram/ssd/hdd/mboard/cooler/power/case
    keyword  VARCHAR(50) NOT NULL,
    reason   VARCHAR(30) NOT NULL    -- 필터 사유(참고용): common/xeon/overseas/used/notebook/server
);

-- ===== 공통 (전체 카테고리) : 중고 / 노트북 / 해외 / 유통상태 이상 =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('ALL', '중고',     'used'),
('ALL', '노트북',   'notebook'),
('ALL', '리퍼',     'used'),
('ALL', '전시상품', 'used'),
('ALL', '해외구매', 'overseas'),
('ALL', '병행수입', 'overseas'),
('ALL', '탈거',     'used');

-- ===== CPU : 제온(서버용 인텔) =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('cpu', '제온', 'xeon'),
('cpu', 'Xeon', 'xeon');
-- 참고: AMD 전체(라이젠/스레드리퍼/EPYC 등) 제외는 "인텔만 취급"하는 별도의
-- 브랜드 범위 규칙이라 02 파일에 그대로 남겨둠 (서버 필터와는 성격이 다름).

-- ===== VGA : 데이터센터/워크스테이션용 GPU =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('vga', 'A100', 'server'), ('vga', 'A800', 'server'), ('vga', 'A30', 'server'), ('vga', 'A40', 'server'),
('vga', 'H100', 'server'), ('vga', 'H200', 'server'), ('vga', 'H800', 'server'),
('vga', 'B100', 'server'), ('vga', 'B200', 'server'),
('vga', 'L40', 'server'), ('vga', 'L4 ', 'server'),
('vga', 'RTX PRO', 'server'), ('vga', 'Quadro', 'server'), ('vga', 'Tesla', 'server'),
('vga', 'NVL', 'server'), ('vga', 'SXM', 'server'), ('vga', '워크스테이션', 'server');

-- ===== RAM : 서버/워크스테이션용(ECC, 레지스터드 등) =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('ram', '서버용',     'server'),
('ram', 'ECC',        'server'),
('ram', '레지스터드', 'server'),
('ram', 'RDIMM',      'server'),
('ram', 'LRDIMM',     'server'),
('ram', 'Registered', 'server');

-- ===== MBoard : 서버 칩셋/서버보드 =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('mboard', 'C621',   'server'),
('mboard', 'C622',   'server'),
('mboard', 'SP3',    'server'),
('mboard', 'SP5',    'server'),
('mboard', '서버용', 'server'),
('mboard', '서버보드', 'server');

-- ===== Power : 서버용 이중화(리던던트) 파워 =====
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('power', '리던던트',  'server'),
('power', 'redundant', 'server'),
('power', 'Redundant', 'server'),
('power', '서버용',    'server'),
('power', 'CRPS',      'server');

-- ===== Case : 랙마운트/서버케이스 =====
-- 주의: 영문 substring 'rack'은 "Bracket" 같은 단어에 오탐되므로 쓰지 않고
-- 정확한 한글 키워드로만 잡음 (예전에 실제로 오탐 발견되어 교체한 이력 있음).
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('case', '랙마운트',   'server'),
('case', '서버케이스', 'server'),
('case', '랙케이스',   'server'),
('case', '19인치 랙',  'server');

-- ===== SSD / HDD / Cooler : 서버/회사용 (신규 추가) =====
-- 지금까지는 이 3개 카테고리에 서버/회사용 키워드 필터가 전혀 없었음.
-- 브랜드가 이미 좁게 스코프(삼성/WD/DEEPCOOL)되어 있어 사고 위험은 낮지만,
-- 요청하신 "서버/회사용" 기준을 전 카테고리에 동일하게 적용하기 위해 추가.
INSERT INTO exclusion_keywords (category, keyword, reason) VALUES
('ssd',    '서버용',     'server'),
('ssd',    '데이터센터', 'server'),
('ssd',    '엔터프라이즈', 'server'),
('hdd',    '서버용',     'server'),
('hdd',    '엔터프라이즈', 'server'),
('hdd',    'Ultrastar',  'server'),
('hdd',    'WD Gold',    'server'),
('cooler', '서버용',     'server'),
('cooler', '랙마운트',   'server');

-- ---------- 2) 정규식 기반 제외 (단순 키워드로 못 잡는 특수 케이스) ----------
DROP TABLE IF EXISTS exclusion_regex;
CREATE TABLE exclusion_regex (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    category VARCHAR(10) NOT NULL,
    pattern  VARCHAR(200) NOT NULL,
    reason   VARCHAR(200) NOT NULL
);

-- SSD: 삼성 OEM/노트북 납품용 라인(PM981/PM9A1/PM9B1/PM9C1/PM9E1/PM893, BM9C1/BM9H1 등).
-- 정식 소매 유통이 없어 사실상 그레이마켓으로만 풀리는 제품 (이름에 "해외"라고 안 써있음).
INSERT INTO exclusion_regex (category, pattern, reason) VALUES
('ssd', 'PM8[0-9]{2}|PM9[A-Z0-9]{2,3}|BM9[A-Z0-9]{2,3}', '삼성 OEM/노트북 납품용 라인(정식 소매 유통 없음)');

-- ---------- 3) 확인용 쿼리 ----------
SELECT category, COUNT(*) AS keyword_cnt FROM exclusion_keywords GROUP BY category ORDER BY category;
SELECT * FROM exclusion_regex;

SELECT '제외 정책 테이블 생성 완료. 다음으로 02_부품별_가격정보.sql 을 실행하세요.' AS next_step;
