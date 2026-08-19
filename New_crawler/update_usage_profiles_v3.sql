-- ============================================================
-- PC 용도별 요구치 갱신 v3 (실사용자 제공 "PC 용도별 부품 매칭 로직" 문서 기준)
-- 이전 버전(update_usage_profiles_v2.sql) 전체 교체.
--
-- *** 전제조건: 07_tier_rank_expanded.sql이 먼저 실행돼 있어야 한다 ***
-- tier_rank가 확장 스케일(CPU 1~41, GPU 1~30)로 바뀐 뒤의 번호를 쓴다.
-- 옛 스케일(CPU 1~25/GPU 1~14) 기준으로 짰던 첫 버전은 폐기 — 실DB에
-- 이미 07/08번 스크립트로 확장 스케일이 적용돼 있어서, 옛 번호를 그대로
-- 쓰면 요구치가 실제보다 훨씬 낮게 걸린다.
--
-- tier_rank 환산 근거 — 07_tier_rank_expanded.sql의 모델별 UPDATE 조건과
-- 직접 대조한 값(근사/추정 아님, 그 스크립트가 그 모델에 실제로 매기는 번호):
--   문서작업   CPU "i3 전체/i5-13400급부터" -> i3-13100 = tier17
--              GPU "매칭 안함(내장그래픽 CPU 한정)" -> 이 스키마엔 "GPU 스테이지 생략"
--              개념이 없어 최저치(9, RTX5050)로만 근사. 실제로 GPU 매칭을 끄려면
--              core/algorithm.py 쪽 변경이 필요함(이번 갱신 범위 밖).
--   영상편집   CPU "i5-K/Ultra5급 이상" -> i5-13600K/14600K = tier27
--              GPU "RTX 5060Ti급 이상" -> tier15
--   3D렌더링   CPU (가성비 최저) "6코어12스레드급, 예 i5-14400" -> tier19
--              GPU (가성비 최저) "RTX5060 12GB" -> tier12 (VRAM 16GB 조건은
--              vga_products에 VRAM 컬럼이 없어 반영 불가 — 스키마 확장 필요, 범위 밖)
--              SSD 가성비 최저 1TB(요구사양 required_ssd_gb는 두 모드 공통 floor로 씀)
--   방송/스트리밍  GPU (가성비 최저) "RTX4060/5060" 중 최저 -> RTX4060 = tier10
--              CPU 항목 원문이 "RTX 4070Ti급 이상"으로 GPU 모델명이 적혀있어 오탈자로
--              보임 — 팀 확인 전까지 기존값(울트라5 245K 상당) 유지, tier25로 환산.
--   개발/컴파일 CPU "i5-13600급 이상"(K 아님) -> tier21
--              GPU "RTX5050급 이상" -> tier9
-- 게임(game_requirements)의 CPU/GPU/RAM/저장장치는 게임별 테이블 그대로 사용 —
-- 이 문서가 명시한 게임 저장장치 규칙(가성비1TB/성능2TB, HDD1TB)은 이미
-- api/server.py의 게임 선택 시 최소 1TB 보정과 일치해서 별도 변경 없음.
--
-- 범위 밖(core/algorithm.py 변경 필요, 이번엔 안 건드림): GPU VRAM 최소치,
-- M.2/SATA 슬롯 규칙. (PSU 1.3배 마진+80PLUS, 쿨러 TDP*MTP*1.3 공식,
-- RAM-메인보드 속도 매칭은 main에 이미 구현돼 있음 — core/algorithm.py 참고.)
--
-- ※ 이 저장소의 mock DB(db/seed_data.sql, DW_db_mock)는 자체 데이터가
-- 아직 옛 스케일(CPU 1~25/GPU 1~14)이라 이 파일과 별개다 — 그쪽은 내부적으로
-- 일관돼 있어 문제없이 동작하지만, 실DB와 숫자를 맞추려면 mock 쪽 tier
-- 데이터도 별도로 확장 스케일로 다시 짜야 한다(이번 범위 밖).
-- ============================================================
USE dw_db;

UPDATE usage_profiles SET required_cpu_tier = 17, required_gpu_tier = 9,  required_ram_gb = 16, required_ram_type = NULL,   required_ssd_gb = 512,  required_hdd_gb = 0    WHERE id = 1;
UPDATE usage_profiles SET required_cpu_tier = 27, required_gpu_tier = 15, required_ram_gb = 32, required_ram_type = 'DDR5', required_ssd_gb = 1000, required_hdd_gb = 2000 WHERE id = 2;
UPDATE usage_profiles SET required_cpu_tier = 19, required_gpu_tier = 12, required_ram_gb = 64, required_ram_type = 'DDR5', required_ssd_gb = 1000, required_hdd_gb = 4000 WHERE id = 3;
UPDATE usage_profiles SET required_cpu_tier = 25, required_gpu_tier = 10, required_ram_gb = 32, required_ram_type = NULL,   required_ssd_gb = 1000, required_hdd_gb = 0    WHERE id = 4;
UPDATE usage_profiles SET required_cpu_tier = 21, required_gpu_tier = 9,  required_ram_gb = 32, required_ram_type = NULL,   required_ssd_gb = 1000, required_hdd_gb = 0    WHERE id = 5;

SELECT * FROM usage_profiles ORDER BY id;
