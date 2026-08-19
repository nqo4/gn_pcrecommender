-- ============================================================
-- PC 용도별 요구치 갱신 v3 (실사용자 제공 "PC 용도별 부품 매칭 로직" 문서 기준)
-- 이전 버전(update_usage_profiles_v2.sql, 이 저장소엔 파일로는 없고 db/schema.sql
-- 주석에만 남아있음) 전체 교체.
--
-- tier_rank 환산 근거 — cpu_performance_tier / gpu_performance_tier 실측값 기준:
--   문서작업   CPU "i3 전체/i5-13400급부터" -> i3-13100(tier1)부터 포함되도록 1로 완화
--              GPU "매칭 안함(내장그래픽 CPU 한정)" -> 이 스키마엔 "GPU 스테이지 생략"
--              개념이 없어 최저치(1)로만 근사. 실제로 GPU 매칭을 끄려면 core/algorithm.py
--              쪽 변경이 필요함(이번 갱신 범위 밖).
--   영상편집   CPU "i5-K/Ultra5급 이상" -> i5-13600K/14600K = tier11로 직역
--              GPU "RTX 5060Ti급 이상" -> tier5
--   3D렌더링   CPU (가성비 최저) "6코어12스레드급, 예 i5-14400" -> tier3
--              GPU (가성비 최저) "RTX5060 12GB" -> tier3 (VRAM 16GB 조건은 vga_products에
--              VRAM 컬럼이 없어 반영 불가 — 스키마 확장 필요, 범위 밖)
--              SSD 가성비 최저 1TB(요구사양 required_ssd_gb는 두 모드 공통 floor로 씀)
--   방송/스트리밍  GPU (가성비 최저) "RTX4060/5060" -> tier2
--              CPU 항목 원문이 "RTX 4070Ti급 이상"으로 GPU 모델명이 적혀있어 오탈자로
--              보임 — 팀 확인 전까지 기존값(9) 유지.
--   개발/컴파일 CPU "i5-13600급 이상"(K 아님) -> tier5
--              GPU "RTX5050급 이상" -> tier1
-- 게임(game_requirements)의 CPU/GPU/RAM/저장장치는 게임별 테이블 그대로 사용 —
-- 이 문서가 명시한 게임 저장장치 규칙(가성비1TB/성능2TB, HDD1TB)은 이미
-- api/server.py의 게임 선택 시 최소 1TB 보정과 일치해서 별도 변경 없음.
--
-- 범위 밖(core/algorithm.py 변경 필요, 이번엔 안 건드림): PSU 정격출력 1.3배 마진+
-- 80PLUS 등급 매칭, 쿨러 TDP*MTP*1.3 공식, RAM-메인보드 지원 속도(MHz) 매칭,
-- M.2/SATA 슬롯 규칙, GPU VRAM 최소치.
-- ============================================================
USE DW_db;

UPDATE usage_profiles SET required_cpu_tier = 1, required_gpu_tier = 1, required_ram_gb = 16, required_ram_type = NULL, required_ssd_gb = 512, required_hdd_gb = 0 WHERE id = 1;
UPDATE usage_profiles SET required_cpu_tier = 11, required_gpu_tier = 5, required_ram_gb = 32, required_ram_type = 'DDR5', required_ssd_gb = 1000, required_hdd_gb = 2000 WHERE id = 2;
UPDATE usage_profiles SET required_cpu_tier = 3, required_gpu_tier = 3, required_ram_gb = 64, required_ram_type = 'DDR5', required_ssd_gb = 1000, required_hdd_gb = 4000 WHERE id = 3;
UPDATE usage_profiles SET required_cpu_tier = 9, required_gpu_tier = 2, required_ram_gb = 32, required_ram_type = NULL, required_ssd_gb = 1000, required_hdd_gb = 0 WHERE id = 4;
UPDATE usage_profiles SET required_cpu_tier = 5, required_gpu_tier = 1, required_ram_gb = 32, required_ram_type = NULL, required_ssd_gb = 1000, required_hdd_gb = 0 WHERE id = 5;

SELECT * FROM usage_profiles ORDER BY id;
