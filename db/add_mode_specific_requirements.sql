-- ============================================================
-- 실사용자 제공 세부 가이드: 방송/3D렌더링/개발 용도의 가성비·성능 모드별
-- GPU/CPU/SSD 요구사항을 별도 컬럼으로 추가한다.
--
-- *** 매핑 근거(gpu_performance_tier.sql 기준 1~14 스케일) ***
-- 1 RTX5050, 2 RTX4060, 3 RTX5060, 4 RTX4060Ti, 5 RTX5060Ti, 6 RTX4070,
-- 7 RTX4070 SUPER, 8 RTX5070, 9 RTX4070Ti, 10 RTX5070Ti, 11 RTX4080/4080S,
-- 12 RTX5080, 13 RTX4090, 14 RTX5090
--
-- 방송(스트리밍):
--   가성비 "RTX4060/RTX5060" 하한 -> tier 2
--   성능 "RTX4070~RTX4080S/4090/5080" 하한(RTX4070이 최저) -> tier 6
-- 3D렌더링:
--   가성비 "RTX4060Ti16GB/RTX4070 12GB/RTX5060 12GB" 하한 -> tier 3
--   성능 "RTX4070TiSuper16GB~RTX4090/5080" 하한 -> tier 9
--   (RTX4070 Ti SUPER는 현재 gpu_performance_tier에 없는 모델이라 근접한
--   RTX4070Ti(tier9)로 근사했다 — 팀원이 tier표에 이 모델을 추가하면 그
--   tier_rank로 바꿔야 정확해진다)
--
-- *** CPU(3D렌더링)는 코어/스레드 수 기준인데, 지금 코어/스레드 데이터가
-- 크롤링만 되고 매칭에 안 쓰이고 있어서 정확한 구현이 아직 안 된다 —
-- 예시로 주신 모델명(i5-14400/i7-14700K, i9-14900K)을 tier_rank로 근사
-- 매핑했지만, "6코어12스레드~8코어16스레드"라는 스펙 자체는 반영 못 했다. ***
--   가성비 CPU 하한: i5-14400 -> tier 3
--   성능 CPU 하한: i9-14900K -> tier 24
-- ============================================================
USE dw_db;

ALTER TABLE usage_profiles ADD COLUMN required_gpu_tier_perf SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_cpu_tier_perf SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_ssd_gb_perf SMALLINT UNSIGNED NULL;

-- 방송/스트리밍: GPU만 모드별로 다름
UPDATE usage_profiles SET required_gpu_tier = 2, required_gpu_tier_perf = 6 WHERE code = 'STREAMING';

-- 3D렌더링: GPU/CPU/SSD 전부 모드별로 다름
UPDATE usage_profiles
SET required_gpu_tier = 3, required_gpu_tier_perf = 9,
    required_cpu_tier = 3, required_cpu_tier_perf = 24,
    required_ssd_gb = 1000, required_ssd_gb_perf = 2000
WHERE code = 'RENDERING_3D';

-- 개발/컴파일: SSD만 모드별로 다름(DRAM 탑재 여부는 지금 데이터 없어 미반영)
UPDATE usage_profiles SET required_ssd_gb = 1000, required_ssd_gb_perf = 2000 WHERE code = 'DEVELOPMENT';

SELECT code, required_gpu_tier, required_gpu_tier_perf, required_cpu_tier, required_cpu_tier_perf,
       required_ssd_gb, required_ssd_gb_perf
FROM usage_profiles;
