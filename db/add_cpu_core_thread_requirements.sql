-- ============================================================
-- 매칭 로직 사전 준비: CPU 코어/스레드 수 요구사항 컬럼을 usage_profiles에
-- 미리 추가한다. 지금은 값을 다 NULL로 둔다(코어/스레드 데이터가 아직
-- 크롤링 안 됨) — merge_requirements가 NULL을 0(제한 없음)으로 처리하므로
-- 지금 이 스크립트를 실행해도 기존 매칭 결과에는 아무 영향이 없다.
--
-- *** 나중에 할 일 ***
-- 1) 팀원이 CPU 코어/스레드 크롤링을 완료하면, danawa_spec_summary에서
--    실제 spec_key 이름을 확인한다(check_ram_spec_keys.py와 같은 방식으로
--    "SELECT DISTINCT spec_key FROM danawa_spec_summary WHERE category='cpu'"
--    를 돌려서 코어/스레드 관련 항목을 찾으면 된다).
-- 2) core/algorithm.py의 CPU 스테이지 서브쿼리에서 spec_key='코어 수'/
--    '스레드 수'로 미리 넣어둔 부분을 실제 이름으로 교체한다.
-- 3) 아래 UPDATE문의 값을 실사용자가 준 3D렌더링 가이드대로 채운다:
--    가성비 "6코어12스레드~8코어16스레드", 성능 "12코어20스레드~16코어32스레드"
-- ============================================================
USE DW_db;

ALTER TABLE usage_profiles ADD COLUMN required_cpu_cores SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_cpu_threads SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_cpu_cores_perf SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_cpu_threads_perf SMALLINT UNSIGNED NULL;

-- 코어/스레드 크롤링이 끝나면 아래 주석을 풀고 실제 값으로 채우면 된다.
-- UPDATE usage_profiles
-- SET required_cpu_cores = 6, required_cpu_threads = 12,
--     required_cpu_cores_perf = 12, required_cpu_threads_perf = 20
-- WHERE code = 'RENDERING_3D';

SELECT code, required_cpu_cores, required_cpu_threads, required_cpu_cores_perf, required_cpu_threads_perf
FROM usage_profiles;
