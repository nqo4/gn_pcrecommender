-- ============================================================
-- 쿨러 타입(공랭/수랭) 채우기 — cooler_spec_update.sql에 이 로직이 빠져있어서
-- (support_sockets/height_mm만 채우고 cooler_type은 채우지 않음) 별도로 만듦.
--
-- 상품명에 "수랭", "일체형", "AIO", 또는 라디에이터 크기(240/280/360/420)가
-- 있으면 수랭으로, 나머지는 공랭으로 판단한다.
-- [수정] 숫자 앞뒤에 다른 숫자가 없을 때만 매칭하도록 경계를 넣었다 —
--   예전엔 부분 문자열 매칭이라 모델번호에 240 등이 낀 공랭(예: "...1240",
--   "RC-2400")이 수랭으로 오판됐다. 120/140은 공랭 팬 지름 표기("PA120" 등)와
--   겹쳐 오탐이 심해서 애초에 판별 키워드에서 뺐다(주석만 남아있던 것 정리).
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

UPDATE cooler_products
SET cooler_type = CASE
    WHEN name REGEXP '수랭|일체형|AIO|(^|[^0-9])(240|280|360|420)($|[^0-9])'
        THEN '수랭'
    ELSE '공랭'
END
WHERE cooler_type IS NULL;

SELECT cooler_type, COUNT(*) AS cnt FROM cooler_products GROUP BY cooler_type;
