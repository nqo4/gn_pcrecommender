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
--
-- *** 수정(위험한 이중 적용 방지) ***
-- 이 스크립트를 이미 적용된 DB에 실수로 한 번 더 돌리면 값이 깨진다 —
-- CPU는 +16이 또 더해지고(예: 19 -> 35), GPU는 새 스케일 값(9~30)이 다시
-- CASE문의 옛 스케일(1~14) 구간과 우연히 겹치는 경우(예: 이미 새 스케일인
-- 12가 CASE문의 "12 -> 28"에 다시 걸림) 값이 완전히 틀어진다. 값 범위로
-- "이미 마이그레이션됐는지"를 판별하는 건 9~14 구간이 옛/새 스케일 양쪽에
-- 다 있을 수 있어 신뢰할 수 없다 — 대신 마이그레이션 완료 여부를 기록하는
-- 마커 테이블을 두고, 이미 적용됐으면 전부 건너뛴다.
-- ============================================================
USE dw_db;
SET SQL_SAFE_UPDATES = 0;

CREATE TABLE IF NOT EXISTS _schema_migrations (
    name        VARCHAR(100) PRIMARY KEY,
    applied_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

SET @already_applied = (
    SELECT COUNT(*) FROM _schema_migrations WHERE name = '11_remap_usage_profiles_tiers'
);

-- CPU: 기존 값 + 16 (이미 적용됐으면 @already_applied=1이라 WHERE가 전부 거짓이 되어 아무 것도 안 바뀐다)
UPDATE usage_profiles SET required_cpu_tier = required_cpu_tier + 16
WHERE required_cpu_tier IS NOT NULL AND @already_applied = 0;
UPDATE usage_profiles SET required_cpu_tier_perf = required_cpu_tier_perf + 16
WHERE required_cpu_tier_perf IS NOT NULL AND @already_applied = 0;

-- GPU: 구 번호 -> 새 번호 매핑표
-- 1->9, 2->10, 3->12, 4->14, 5->15, 6->17, 7->19, 8->20, 9->22, 10->23, 11->26, 12->28, 13->29, 14->30
UPDATE usage_profiles SET required_gpu_tier = CASE required_gpu_tier
    WHEN 1 THEN 9 WHEN 2 THEN 10 WHEN 3 THEN 12 WHEN 4 THEN 14 WHEN 5 THEN 15
    WHEN 6 THEN 17 WHEN 7 THEN 19 WHEN 8 THEN 20 WHEN 9 THEN 22 WHEN 10 THEN 23
    WHEN 11 THEN 26 WHEN 12 THEN 28 WHEN 13 THEN 29 WHEN 14 THEN 30
    ELSE required_gpu_tier END
WHERE required_gpu_tier IS NOT NULL AND @already_applied = 0;

UPDATE usage_profiles SET required_gpu_tier_perf = CASE required_gpu_tier_perf
    WHEN 1 THEN 9 WHEN 2 THEN 10 WHEN 3 THEN 12 WHEN 4 THEN 14 WHEN 5 THEN 15
    WHEN 6 THEN 17 WHEN 7 THEN 19 WHEN 8 THEN 20 WHEN 9 THEN 22 WHEN 10 THEN 23
    WHEN 11 THEN 26 WHEN 12 THEN 28 WHEN 13 THEN 29 WHEN 14 THEN 30
    ELSE required_gpu_tier_perf END
WHERE required_gpu_tier_perf IS NOT NULL AND @already_applied = 0;

INSERT IGNORE INTO _schema_migrations (name) VALUES ('11_remap_usage_profiles_tiers');

-- 확인 (already_applied=1이면 "건너뜀" 표시, 0이면 방금 적용된 값)
SELECT IF(@already_applied = 1, '이미 적용됨 — 건너뜀', '방금 적용함') AS status;
SELECT code, required_cpu_tier, required_cpu_tier_perf, required_gpu_tier, required_gpu_tier_perf
FROM usage_profiles;
