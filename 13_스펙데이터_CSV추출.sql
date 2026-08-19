-- ============================================================
-- 13. danawa_spec_summary 테이블을 CSV로 내보내기
--
-- MySQL Workbench에서 CSV로 저장하는 방법 2가지:
--
-- [방법 A - 가장 쉬움] Result Grid에서 직접 내보내기
--   1) 아래 SELECT 쿼리를 실행
--   2) 결과창(Result Grid) 우측 상단의 내보내기 아이콘(Export) 클릭
--   3. 파일 형식 CSV 선택 -> 저장 위치 지정 -> 저장
--
-- [방법 B] SELECT INTO OUTFILE (서버 로컬 파일로 직접 저장, 서버 권한 필요할 수 있음)
--   아래 방법 A를 우선 권장합니다.
-- ============================================================
USE dw_db;

-- 전체 스펙 데이터 (605+212+... 전체 카테고리 다 합쳐서, 약 수만 건 될 수 있음)
SELECT category, product_id, spec_key, spec_value, spec_order, scraped_at
FROM danawa_spec_summary
ORDER BY category, product_id, spec_order;
