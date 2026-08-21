-- ============================================================
-- 08. usage_profiles의 CPU/GPU 요구 등급을 새 tier_rank 스케일로 재매핑
--
-- *** 반드시 07_tier_rank_expanded.sql과 함께 실행할 것 ***
-- tier_rank 번호 체계가 CPU 1~25→1~41, GPU 1~14→1~30으로 바뀌면서,
-- usage_profiles에 저장된 기존 요구 등급 값들이 전부 옛날 번호를 가리키게
-- 됐다 — 이 스크립트로 새 번호에 맞게 다시 계산한다.
--
-- CPU는 기존 값에 +16만 하면 된다(구형 16단계가 전부 앞쪽에 추가됐을
-- 뿐, 기존 1~25 순서는 그대로 유지됨).
-- GPU는 구형 GPU가 중간중간에도 끼어들어서 단순 덧셈이 아니라 개별
-- 매핑표를 썼다(아래 CASE문 참고).
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

-- CPU: 기존 값 + 16
UPDATE usage_profiles SET required_cpu_tier = required_cpu_tier + 16 WHERE required_cpu_tier IS NOT NULL;
UPDATE usage_profiles SET required_cpu_tier_perf = required_cpu_tier_perf + 16 WHERE required_cpu_tier_perf IS NOT NULL;

-- GPU: 구 번호 -> 새 번호 매핑표
-- 1->9, 2->10, 3->12, 4->14, 5->15, 6->17, 7->19, 8->20, 9->22, 10->23, 11->26, 12->28, 13->29, 14->30
UPDATE usage_profiles SET required_gpu_tier = CASE required_gpu_tier
    WHEN 1 THEN 9 WHEN 2 THEN 10 WHEN 3 THEN 12 WHEN 4 THEN 14 WHEN 5 THEN 15
    WHEN 6 THEN 17 WHEN 7 THEN 19 WHEN 8 THEN 20 WHEN 9 THEN 22 WHEN 10 THEN 23
    WHEN 11 THEN 26 WHEN 12 THEN 28 WHEN 13 THEN 29 WHEN 14 THEN 30
    ELSE required_gpu_tier END
WHERE required_gpu_tier IS NOT NULL;

UPDATE usage_profiles SET required_gpu_tier_perf = CASE required_gpu_tier_perf
    WHEN 1 THEN 9 WHEN 2 THEN 10 WHEN 3 THEN 12 WHEN 4 THEN 14 WHEN 5 THEN 15
    WHEN 6 THEN 17 WHEN 7 THEN 19 WHEN 8 THEN 20 WHEN 9 THEN 22 WHEN 10 THEN 23
    WHEN 11 THEN 26 WHEN 12 THEN 28 WHEN 13 THEN 29 WHEN 14 THEN 30
    ELSE required_gpu_tier_perf END
WHERE required_gpu_tier_perf IS NOT NULL;

-- 확인
SELECT code, required_cpu_tier, required_cpu_tier_perf, required_gpu_tier, required_gpu_tier_perf
FROM usage_profiles;
