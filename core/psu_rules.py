"""
PSU 안전 판정용 키워드 규칙 (실사용자 제공 PSU 매칭 가이드).

core/algorithm.py(PSU 후보 필터링)와 core/gemini_review.py(검수 프롬프트에
"이미 확인된 사실"로 알려주기) 양쪽에서 같이 쓰기 때문에, 순환 참조를
피하려고 별도 모듈로 뺐다.

*** 판정 규칙(가이드 원문) ***
'ATX 파워'는 단순 물리 규격(폼팚터) 표기일 뿐이라, 이 표기만으로 최신
전력 규격 지원 여부를 판단하면 안 된다. 상품명/스펙에 'ATX 3.0', 'ATX 3.1',
'12VHPWR', '12V-2x6'이 명시적으로 있을 때만 최신 규격 지원으로 판정하고,
그냥 'ATX 파워'로만 표기돼 있으면 ATX 2.x(구형)로 간주한다.
"""
import re

_ATX3_RE = re.compile(r"ATX\s*3\.[01]|12VHPWR|12V-?2x6", re.IGNORECASE)
_80PLUS_TIER_RE = re.compile(
    r"80\s*PLUS\s*(TITANIUM|티타늄|PLATINUM|플래티넘|GOLD|골드|SILVER|실버|BRONZE|브론즈|STANDARD|스탠다드)",
    re.IGNORECASE,
)

# GPU tier_rank >= 22(RTX 4070Ti/5070Ti/4080/5080/4090/5090급)부터 12VHPWR
# 네이티브 PSU를 강제한다 — 가이드의 "고성능 GPU" 목록과 정확히 일치.
# *** 수정(실사용자 요청: "확장 등급표" 07_tier_rank_expanded.sql 적용으로
# GPU tier_rank가 1~14에서 1~30 스케일로 바뀌면서 임계값도 같이 이동) ***
HIGH_POWER_GPU_TIER_THRESHOLD = 22


def has_atx3_support(name: str) -> bool:
    """상품명에 ATX3.0/3.1 또는 12VHPWR/12V-2x6이 명시돼 있는지 확인한다.
    단순 'ATX 파워' 표기만으로는 True가 되지 않는다(가이드 판정 규칙)."""
    return bool(_ATX3_RE.search(name or ""))


def extract_80plus_tier(name: str) -> str | None:
    """상품명에서 80PLUS 등급 키워드(브론즈/골드/플래티넘 등)를 추출한다.
    못 찾으면 None(무인증 또는 표기 불명)."""
    m = _80PLUS_TIER_RE.search(name or "")
    return m.group(1).upper() if m else None


# *** 신설(실사용자 최종 결정: 가성비=Bronze~Silver, 성능=Gold 이상) ***
# 등급 서열을 숫자로 매겨서 "이 등급 이상"을 쉽게 비교할 수 있게 한다.
_TIER_RANK = {
    "STANDARD": 0, "스탠다드": 0,
    "BRONZE": 1, "브론즈": 1,
    "SILVER": 2, "실버": 2,
    "GOLD": 3, "골드": 3,
    "PLATINUM": 4, "플래티넘": 4,
    "TITANIUM": 5, "티타늄": 5,
}


def meets_80plus_minimum(name: str, min_tier: str) -> bool:
    """이 PSU의 80PLUS 등급이 min_tier(예: "GOLD") 이상인지 확인한다.
    등급 표기가 아예 없으면(무인증) False — 최소 등급 요구가 있는 상황에서
    무인증 제품을 통과시키면 안 되기 때문이다."""
    tier = extract_80plus_tier(name)
    if tier is None:
        return False
    return _TIER_RANK.get(tier, -1) >= _TIER_RANK.get(min_tier.upper(), 0)
