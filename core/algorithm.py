"""
견적 생성 알고리즘 (기획서 2.2~2.4절).

순서: CPU/GPU 확정 -> 메인보드 -> RAM -> 쿨러 -> PSU -> 케이스
탐색 방식은 아래 명시적 스택으로 구현한다 — 각 스테이지에서 후보를 하나씩
시도하다가(예: 1.2.8 -> 1.2.9 -> 1.2.10) 후보가 전부 소진되면 바로 이전
스테이지로 돌아가 그 선택을 한 칸 위 후보로 바꾸고(1.2.10 -> 1.3.1) 다시
내려온다(기획서 2.2.1절 백트래킹 규칙). 가장 앞 스테이지(CPU)까지 후보가
소진되면 최종 실패.
"""
import re
from dataclasses import dataclass, field

from db.db import get_connection
from core import gemini_review

STAGES = ["cpu", "gpu", "mboard", "ram", "cooler", "psu", "case"]

# *** 수정(실사용자 재요청: "메인보드를 다시 먼저 가져올 것") ***
# RAM 먼저 순서로 바꿨다가 다시 메인보드 우선으로 되돌린다. RAM이 배운
# 규칙(DDR5 우선, 5600MHz 이상 우선, 듀얼채널 단일스틱 구매)은 그대로
# 유지하되, 이제 "메인보드가 정한 규격 안에서" 그 우선순위를 적용한다.
STAGE_DEPENDENCIES: dict[str, list[str]] = {
    "cpu": [],
    "gpu": ["cpu"],       # *** 수정(밸런스 가이드): GPU는 이제 CPU 체급도 본다 ***
    "mboard": ["cpu", "gpu"],
    "ram": ["mboard"],
    "cooler": ["cpu", "ram"],  # *** 수정(실사용자 재결정): 쿨러는 이제 CPU 단독 발열만 보므로 gpu 의존 제거 ***
    "psu": ["gpu", "cpu"],  # *** 수정: CPU 체급별 최소 와트수 하한선도 참조하므로 cpu도 의존 ***
    "case": ["mboard", "cooler", "gpu", "psu"],
}

# *** 신설(실사용자 제공 Gemini 밸런스 가이드 1절 반영) ***
# CPU/GPU 체급을 4단계(Flagship/High-End/Mainstream/Entry)로 나누고,
# CPU-GPU는 1단계 초과 차이 나면 병목으로 본다. cpu_performance_tier/
# gpu_performance_tier의 tier_rank 값 구간을 가이드의 실제 모델 예시
# (i9/Ultra9=Flagship, i7/Ultra7=High-End, i5-K/Ultra5상위=Mainstream,
# i5비K/Ultra5하위=Entry / RTX 5080~5090=Flagship, RTX 4070~5070Ti=High-End,
# RTX 4060Ti~5060Ti=Mainstream, RTX 4060/5050=Entry)에 맞춰 눈금을 매겼다.
#
# *** 수정(실사용자 요청: "확장 등급표" — 07_tier_rank_expanded.sql) ***
# 11/12세대·셀러론·펜티엄 같은 구형 CPU를 새로 끼워넣으면서 tier_rank
# 번호가 1~41로 넓어졌는데, 구형 CPU 묶음(1~16)과 신형 CPU 묶음(17~41)이
# 성능대별로 서로 떨어져 있어서(예: entry가 1~5, 17~24 두 군데로 나뉨)
# "누적 상한선 하나"로는 표현이 안 된다 — CPU는 (하한,상한,버킷이름)
# 여러 구간의 리스트로 바꿨다. GPU는 새 번호(1~30)가 성능대별로 자연스럽게
# 이어져서 기존처럼 단일 구간 리스트를 그대로 쓴다.
CPU_TIER_BUCKETS = [
    (1, 5, "entry"),        # 셀러론~i5-12400(구형 보급형)
    (6, 9, "mainstream"),   # i5-11600K~i7-12700(구형 중급)
    (10, 13, "high"),       # i7-11700K~i9-12900(구형 상급)
    (14, 16, "flagship"),   # i9-11900K~i9-12900KS(구형 최상급)
    (17, 24, "entry"),      # i3-13100~i5-13600/14600(신형 보급형)
    (25, 27, "mainstream"), # 울트라5-245K~i5-13600K/14600K(신형 중급)
    (28, 34, "high"),       # i7-13700~i7-14700K(신형 상급)
    (35, 41, "flagship"),   # i9-13900~i9-14900KS(신형 최상급)
]
GPU_TIER_BUCKETS = [(9, "entry"), (15, "mainstream"), (23, "high"), (30, "flagship")]
BUCKET_ORDER = ["entry", "mainstream", "high", "flagship"]


def _tier_bucket_ranges(tier_rank: int | None, ranges: list[tuple[int, int, str]]) -> str | None:
    """(하한, 상한, 버킷이름) 여러 구간 중 tier_rank가 속하는 구간을 찾는다."""
    if tier_rank is None:
        return None
    for lo, hi, name in ranges:
        if lo <= tier_rank <= hi:
            return name
    return ranges[-1][2]


def _tier_bucket(tier_rank: int | None, boundaries: list[tuple[int, str]]) -> str | None:
    """(상한, 버킷이름) 누적 상한선 방식 — 구간이 항상 1부터 연속될 때만 쓴다."""
    if tier_rank is None:
        return None
    for upper, name in boundaries:
        if tier_rank <= upper:
            return name
    return boundaries[-1][1]


def cpu_tier_bucket(tier_rank: int | None) -> str | None:
    return _tier_bucket_ranges(tier_rank, CPU_TIER_BUCKETS)


def gpu_tier_bucket(tier_rank: int | None) -> str | None:
    return _tier_bucket(tier_rank, GPU_TIER_BUCKETS)


# 메인보드 라인업 등급(상품명 기반 — 3사 라인업명은 컬럼이 아니라 상품명에만
# 있어서 정규식으로 판별한다). 가이드 표의 "보급형(H/A)/중급형(B)/상급·최상위(Z)"를
# 그대로 GPU 버킷과 대응시킨다: 보급형->entry/mainstream, 중급형->mainstream/high,
# 상급->high/flagship.
_MBOARD_CHIPSET_RE = re.compile(r"\b([ZXBHA])\d{3}[A-Z]?\b")
_MBOARD_CHIPSET_BUCKET = {"Z": "high", "X": "high", "B": "mainstream", "H": "entry", "A": "entry"}
_MBOARD_LINEUP_PATTERNS = [
    (re.compile(r"MEG|MPG|MAXIMUS|STRIX|AORUS MASTER|TACHYON", re.IGNORECASE), "high"),
    (re.compile(r"MAG|박격포|토마호크|TUF|AORUS ELITE", re.IGNORECASE), "mainstream"),
    (re.compile(r"PRO |PRIME|UD|EAGLE", re.IGNORECASE), "entry"),
]


def mboard_lineup_bucket(name: str) -> str:
    """상품명에서 메인보드 등급을 판별한다.

    *** 수정(실사용자 발견: "i9-14900KS+RTX4090에 B760 보드가 매칭됨") ***
    브랜드 서브라인 이름(STRIX/TUF/PRIME 등)만 보고 판별했더니, "ASUS ROG
    STRIX B760-G"처럼 ASUS가 B(중급) 칩셋 보드에도 STRIX 이름을 붙이는
    경우를 "상급"으로 오판했다 — STRIX는 원래 상급 라인업(Z790 STRIX 등)에
    주로 쓰이지만 B시리즈에도 마케팅상 확장돼있다. 칩셋 코드(Z/X=상급,
    B=중급, H/A=보급형)가 상품명에 명시적으로 있으면 그걸 최우선으로
    쓰고, 칩셋 코드를 못 찾을 때만 브랜드 서브라인 이름으로 폴백한다."""
    chip_m = _MBOARD_CHIPSET_RE.search((name or "").upper())
    if chip_m:
        return _MBOARD_CHIPSET_BUCKET.get(chip_m.group(1), "entry")
    for pattern, bucket in _MBOARD_LINEUP_PATTERNS:
        if pattern.search(name or ""):
            return bucket
    return "entry"


@dataclass
class Requirements:
    # *** 수정(실제 스키마 연결): cpu_tier_min/gpu_tier_min은 이제 코드 안에서
    # 이름을 추측하는 게 아니라, DB의 cpu_performance_tier/gpu_performance_tier
    # 테이블이 매긴 tier_rank 값을 그대로 쓴다(정확도가 훨씬 높음 — 팀원이
    # 기획서 6장을 SQL로 옮기면서 K/비K, 세대, Ultra 시리즈까지 정확히 반영함).
    cpu_tier_min: int = 0
    gpu_tier_min: int = 0
    ram_gb_min: int = 8
    # *** 수정(실사용자 제공 "PC 용도별 견적 가이드"): 이전엔 "게임을 하나라도
    # 선택하면 무조건 1TB, 아니면 500GB"라는 대충 정한 규칙이었는데, 이제
    # game_requirements.storage_gb / usage_profiles.required_ssd_gb·hdd_gb라는
    # 정확한 근거가 생겨서 다른 필드들과 똑같이 merge_requirements에서
    # max()로 병합한다. ***
    ssd_gb_min: int = 500
    hdd_gb_min: int = 0
    # *** 신설(실사용자 요청: "문서작업용 PC는 GPU 없이 내장그래픽 CPU만") ***
    # False면 GPU 스테이지 자체를 건너뛰고, CPU는 내장그래픽 있는 모델만
    # 고른다. 게임은 항상 True(실제 게임엔 GPU가 필요), 문서작업 용도만
    # False로 설정된다(다른 용도/게임과 같이 선택되면 True가 우선).
    requires_dgpu: bool = True
    # *** 신설(매칭 로직 사전 준비 — 실사용자 요청: "3D렌더링 CPU 코어/스레드
    # 조건") *** 코어/스레드 수 크롤링이 아직 안 끝나서 지금은 항상 0(제한
    # 없음)이지만, usage_profiles에 required_cpu_cores/threads(_perf)
    # 컬럼과 merge_requirements 병합 로직은 미리 만들어뒀다 — 크롤링이
    # 끝나면 CPU 스테이지의 아래 TODO 부분만 실제 spec_key로 채우면 된다.
    cpu_min_cores: int = 0
    cpu_min_threads: int = 0


def merge_requirements(rows: list[dict]) -> Requirements:
    """
    다중 게임/PC 용도 통합 (기획서 2.1절 핵심 규칙): 게임을 2개 이상 선택했거나,
    게임과 용도를 함께 선택한 경우, 항목별로 더 높은 쪽을 채택한다.

    rows: game_requirements/usage_profiles에서 뽑은 행을, api/server.py가
    미리 공통 키(required_cpu_tier/required_gpu_tier/required_ram_gb/
    required_ssd_gb/required_hdd_gb)로 정규화해서 넘긴다 — 두 테이블의
    실제 컬럼명이 서로 다르기 때문이다(game_requirements는 cpu_tier_rank
    /storage_gb, usage_profiles는 required_cpu_tier/required_ssd_gb).
    """
    if not rows:
        return Requirements()

    cpu_tier_min = max(r["required_cpu_tier"] for r in rows)
    gpu_tier_min = max(r["required_gpu_tier"] for r in rows)
    ram_gb_min = max(r["required_ram_gb"] for r in rows)
    ssd_gb_min = max(r.get("required_ssd_gb") or 500 for r in rows)
    hdd_gb_min = max(r.get("required_hdd_gb") or 0 for r in rows)
    # *** 신설(실사용자 요청): 하나라도 외장 GPU가 필요하다고 하면(게임은
    # 항상 True, 문서작업 외 다른 용도도 True) 전체적으로 GPU가 필요한
    # 걸로 본다 — 문서작업 하나만 단독 선택했을 때만 GPU를 생략한다.
    requires_dgpu = any(r.get("requires_dgpu", True) for r in rows)
    # *** 신설(매칭 로직 사전 준비): usage_profiles에 required_cpu_cores/
    # threads 컬럼이 생기면 이 값들이 자동으로 채워진다 — 지금은 컬럼이
    #없거나 NULL이라 항상 0(제한 없음)으로 병합된다. ***
    cpu_min_cores = max((r.get("required_cpu_cores") or 0) for r in rows)
    cpu_min_threads = max((r.get("required_cpu_threads") or 0) for r in rows)

    return Requirements(
        cpu_tier_min=cpu_tier_min, gpu_tier_min=gpu_tier_min, ram_gb_min=ram_gb_min,
        ssd_gb_min=ssd_gb_min, hdd_gb_min=hdd_gb_min, requires_dgpu=requires_dgpu,
        cpu_min_cores=cpu_min_cores, cpu_min_threads=cpu_min_threads,
    )


@dataclass
class Options:
    placement: str = "상관없음"   # 책상 위/책상 아래/미니 PC/상관없음
    rgb: str = "상관없음"          # 화려/없음/상관없음


@dataclass
class BuildResult:
    parts: dict = field(default_factory=dict)   # {stage: row(dict)}
    total_price: int = 0
    status: str = "ok"           # ok / no_matching_product / budget_insufficient
    message: str = ""
    review_notes: list = field(default_factory=list)  # Gemini 검수 코멘트(있으면)


def _fetch_all(conn, table, where="", params=(), media_category=None, extra_select=None):
    """MySQL 커서로 조회한다. table 인자엔 _v 뷰 이름(가격 포함)을 넘긴다.
    ? 대신 %s 플레이스홀더를 쓴다(mysql.connector 규칙).

    media_category를 주면 product_media(사진/다나와 링크)를 LEFT JOIN해서
    image_url/product_url을 같이 붙여준다 — 아직 그 카테고리 사진 데이터가
    없으면 NULL로 채워지며(LEFT JOIN이라 에러 없음), 실제 덤프가 들어오면
    자동으로 채워진다.

    extra_select: 추가 서브쿼리 컬럼(문자열, "AS 별칭" 포함)을 SELECT 절에
    끼워넣는다 — CPU/GPU 평균 소비전력처럼 danawa_spec_summary에서 값을
    가져와야 하는데 카테고리마다 파싱 방식이 달라 공용화하기 애매한
    경우에 쓴다."""
    sql = f"SELECT p.*"
    if extra_select:
        sql += f", {extra_select}"
    if media_category:
        sql += ", m.image_url, m.product_url"
    sql += f" FROM {table} p"
    if media_category:
        sql += f" LEFT JOIN product_media m ON m.category = '{media_category}' AND m.product_id = p.product_id"
    if where:
        sql += f" WHERE {where}"
    cursor = conn.cursor(dictionary=True)
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    cursor.close()
    return rows


_RAM_OPTION_RE = re.compile(r"^\s*(\d+)\s*GB(?:\((\d+)\s*G[xX]\s*(\d+)\))?")


def _parse_ram_option(option_name: str) -> tuple[int, int] | None:
    """다나와 RAM 옵션명("64GB(32Gx2)", "8GB" 등)에서 (총용량GB, 패키지 개수)를
    뽑아낸다. 괄호 표기가 없으면 단일 스틱(패키지 개수 1)으로 본다.
    형식이 하나도 안 맞으면 None(용량 파싱 실패한 옵션은 후보에서 제외)."""
    m = _RAM_OPTION_RE.match(option_name or "")
    if not m:
        return None
    total_gb = int(m.group(1))
    stick_count = int(m.group(3)) if m.group(3) else 1
    return total_gb, stick_count


_RAM_SPEED_RE = re.compile(r"DDR[45]-(\d+)")
# *** 수정(실사용자 최종 결정): 가성비/성능 모드별 목표 클럭을 분리한다.
# 가성비 = CPU 공식 지원 클럭과 비슷하게(5600MHz), 성능 = 6000~6400MHz
# (CPU 공식 클럭보다 높은 XMP/EXPO 오버클럭 여유분).
MIN_DDR5_SPEED_COST = 5600
MIN_DDR5_SPEED_PERF = 6000


def _fetch_ram_options(conn, ram_type: str, mboard_slot_count: int | None, ram_gb_min: int, mode: str = "cost") -> list[dict]:
    """RAM을 상품(product_id) 단위가 아니라 "옵션"(용량 구성) 단위로 조회한다.

    *** 수정(실사용자 재요청: "메인보드를 다시 먼저 가져올 것") ***
    RAM을 메인보드보다 먼저 고르는 순서로 바꿨다가 다시 되돌렸다 — 이제
    메인보드가 이미 정해준 ram_type(DDR4/DDR5)과 슬롯 수 안에서 RAM을
    고른다. 듀얼채널을 기본으로 하되 슬롯이 1개뿐이면 단일 스틱으로
    예외 처리한다. DDR4/DDR5 자체를 바꾸는 폴백은 안 한다(메인보드가
    이미 규격을 확정했으므로 의미가 없다).

    *** 수정(실사용자 최종 결정: 모드별 목표 클럭 분리) ***
    가성비(cost) 모드는 CPU 공식 지원 클럭과 비슷한 5600MHz를 목표로 하고,
    성능(perf) 모드는 6000~6400MHz(XMP/EXPO 오버클럭 여유분)를 목표로 한다.
    범위 상한(6400)을 넘는 초고클럭 램은 안정성/호환성 이슈가 있을 수
    있어 일부러 제외한다.
    """
    dual_channel = (mboard_slot_count or 2) >= 2
    quantity = 2 if dual_channel else 1

    def _query() -> list[dict]:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT p.product_id, p.name, pp.option_name, pp.price AS price_krw,
                   m.image_url, m.product_url,
                   (SELECT CAST(REGEXP_SUBSTR(spec_value, '[0-9]+') AS UNSIGNED)
                    FROM danawa_spec_summary
                    WHERE category = 'ram' AND product_id = p.product_id AND spec_key = '높이'
                    LIMIT 1) AS heatsink_height_mm
            FROM ram_products p
            JOIN ram_prices pp ON pp.product_id = p.product_id
            LEFT JOIN product_media m ON m.category = 'ram' AND m.product_id = p.product_id
            WHERE p.ram_type = %s
              AND pp.crawl_date = (SELECT MAX(crawl_date) FROM ram_prices)
            """,
            (ram_type,),
        )
        rows = cursor.fetchall()
        cursor.close()
        return rows

    def _to_options(rows: list[dict], min_speed: int, max_speed: int | None = None) -> list[dict]:
        options = []
        for row in rows:
            speed_m = _RAM_SPEED_RE.search(row["name"] or "")
            speed = int(speed_m.group(1)) if speed_m else 0
            if speed < min_speed:
                continue
            if max_speed and speed > max_speed:
                continue
            parsed = _parse_ram_option(row["option_name"])
            if parsed is None:
                continue
            stick_capacity_gb, stick_count = parsed
            if stick_count != 1:
                continue  # 이미 묶인 킷 옵션은 제외 — 단일 스틱만 후보로 삼는다
            total_capacity_gb = stick_capacity_gb * quantity
            if total_capacity_gb < ram_gb_min:
                continue
            unit_price = row["price_krw"]
            option_label = row["option_name"].split("_")[0]
            options.append({
                "product_id": row["product_id"],
                "name": f"{row['name']} {option_label}" + (f" x{quantity}" if quantity > 1 else ""),
                "price_krw": unit_price * quantity,
                "unit_price_krw": unit_price,
                "quantity": quantity,
                "capacity_gb": total_capacity_gb,
                "ram_type": ram_type,
                "speed_mhz": speed,
                "heatsink_height_mm": row.get("heatsink_height_mm"),
                "image_url": row["image_url"],
                "product_url": row["product_url"],
            })
        return options

    all_rows = _query()
    if ram_type != "DDR5":
        return _to_options(all_rows, 0)  # DDR4는 클럭 목표 규칙 대상이 아님(가이드가 DDR5 기준)

    if mode == "perf":
        # 성능: 6000~6400MHz 범위 우선 -> 없으면 6000MHz 이상 전체 -> 그래도 없으면 전체
        in_range = _to_options(all_rows, MIN_DDR5_SPEED_PERF, 6400)
        if in_range:
            return in_range
        at_least_perf = _to_options(all_rows, MIN_DDR5_SPEED_PERF)
        if at_least_perf:
            return at_least_perf
        return _to_options(all_rows, 0)

    fast = _to_options(all_rows, MIN_DDR5_SPEED_COST if ram_type == "DDR5" else 0)
    if fast:
        return fast
    return _to_options(all_rows, 0)



def _psu_form_factor_matches(psu_form_factor: str, case_supported: str) -> bool:
    """케이스의 support_psu_form_factors는 다나와 원문 그대로("표준-ATX",
    "M-ATX(SFX)")라 PSU 쪽 단순 표기(ATX/SFX/TFX)와 형식이 다르다.
    괄호가 있으면 괄호 안 값이 실제 지원 PSU 폼팩터고("M-ATX(SFX)" -> SFX),
    없으면 하이픈 뒤 값을 쓴다("표준-ATX" -> ATX)."""
    m = re.search(r"\(([A-Za-z]+)\)", case_supported)
    tail = m.group(1) if m else case_supported.split("-")[-1].strip()
    return psu_form_factor == tail


from core.psu_rules import has_atx3_support, extract_80plus_tier, meets_80plus_minimum, HIGH_POWER_GPU_TIER_THRESHOLD


_NO_IGPU_RE = re.compile(r"\d{3,5}K?F\b", re.IGNORECASE)


_K_SERIES_RE = re.compile(r"\d{3,5}K", re.IGNORECASE)


def is_k_series(name: str) -> bool:
    """*** 신설(실사용자 결정: "i7/i9는 K 시리즈일 때만 수랭 강제") ***
    이전엔 i7/i9 전체(K 여부 무관)를 대상으로 했는데, 실사용자가 K
    시리즈만으로 좁히기로 했다. 모델번호 뒤에 K가 붙으면(KF도 포함) K
    시리즈로 판별한다."""
    return bool(_K_SERIES_RE.search(name or ""))


def has_igpu(name: str) -> bool:
    """*** 신설(실사용자 요청: "문서작업용 PC는 GPU 없이 내장그래픽 CPU만") ***
    인텔은 모델번호 뒤에 F가 붙으면(K가 있든 없든, 예: 13400F/13700KF)
    내장그래픽이 없다는 뜻이다 — 이 명명 규칙으로 내장그래픽 유무를
    판별한다. 코어 울트라 시리즈도 동일한 F 접미사 규칙을 따른다."""
    return not bool(_NO_IGPU_RE.search(name or ""))


def get_candidates(conn, stage: str, context: dict, req: Requirements, opt: Options, mode: str) -> list[dict]:
    """해당 스테이지에서 이전 단계 선택(context)과 호환되는 후보를 정렬해서 반환한다.
    mode='cost' -> 가격 오름차순(가성비 모드, 2.3절)
    mode='perf' -> 등급/가격 내림차순(성능 모드 최대 견적 산출, 2.4절)
    """
    if stage == "cpu":
        # *** 신설(실사용자 결정: "(CPU+GPU 평균 소비전력)×1.3 <= PSU/쿨러 용량"
        # 공식으로 통일) *** 인텔 공식 스펙 "PBP-MTP"(예: "125-253W")에서
        # 앞부분(PBP, Processor Base Power = 기본/평균 전력)만 파싱한다.
        # 순간 최대(MTP, 뒷부분)는 이번 결정에 따라 쓰지 않는다.
        #
        # *** 매칭 로직 사전 준비(실사용자 요청: "3D렌더링 CPU 코어/스레드
        # 조건") *** core_count/thread_count도 avg_power_w와 같은 방식으로
        # danawa_spec_summary에서 서브쿼리로 가져오도록 미리 만들어뒀다.
        # ↓↓↓ TODO: 실제 크롤링 완료 후 spec_key 이름을 확인해서 아래
        # '코어 수'/'스레드 수' 부분을 정확한 값으로 바꿀 것(지금은 실제
        # danawa 표기를 확인 못 해서 추정값 — check_ram_spec_keys.py와
        # 같은 방식으로 category='cpu'에서 스레드/코어 관련 spec_key를
        # 먼저 조회해서 정확한 이름을 확인해야 한다). ↑↑↑
        rows = _fetch_all(
            conn, "cpu_products_v", "usage_type = 'consumer'", media_category="cpu",
            extra_select=(
                "(SELECT CAST(SUBSTRING_INDEX(spec_value, '-', 1) AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cpu' AND product_id=p.product_id "
                " AND spec_key='PBP-MTP' LIMIT 1) AS avg_power_w, "
                # *** 수정(실사용자 최종 결정: "쿨러는 CPU 최대전력값만 사용,
                # 최저/평균값은 안 씀") *** "125-253W"의 뒷값(MTP, Maximum
                # Turbo Power = 순간 최대전력)만 따로 파싱한다. PSU 계산에
                # 쓰는 avg_power_w(PBP, 앞값)와는 별개 필드다 — 쿨러는
                # max_power_w를, PSU는 여전히 avg_power_w를 쓴다.
                "(SELECT CAST(SUBSTRING_INDEX(spec_value, '-', -1) AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cpu' AND product_id=p.product_id "
                " AND spec_key='PBP-MTP' LIMIT 1) AS max_power_w, "
                "(SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cpu' AND product_id=p.product_id "
                " AND spec_key='코어 수' LIMIT 1) AS core_count, "  # TODO: 실제 spec_key로 교체
                "(SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cpu' AND product_id=p.product_id "
                " AND spec_key='스레드 수' LIMIT 1) AS thread_count"  # TODO: 실제 spec_key로 교체
            ),
        )
        rows = [r for r in rows if (r["tier_rank"] or 0) >= req.cpu_tier_min]
        # *** 신설(매칭 로직 사전 준비) *** req.cpu_min_cores/threads는 지금
        # merge_requirements가 항상 0(제한 없음)을 반환하므로, 코어/스레드
        # 크롤링이 끝나고 usage_profiles에 값이 채워지기 전까지는 이 필터가
        # 실질적으로 아무것도 거르지 않는다(안전하게 미리 연결해둔 상태).
        if req.cpu_min_cores:
            rows = [r for r in rows if (r.get("core_count") or 0) >= req.cpu_min_cores]
        if req.cpu_min_threads:
            rows = [r for r in rows if (r.get("thread_count") or 0) >= req.cpu_min_threads]
        # *** 신설(실사용자 요청: "문서작업용 PC는 GPU 없이 내장그래픽 CPU만") ***
        # req.requires_dgpu가 False면(예: 문서작업 용도) 외장 GPU를 아예 안
        # 고르므로, CPU가 반드시 내장그래픽을 갖고 있어야 한다(F 접미사 없는
        # 모델만 허용) — 안 그러면 화면 출력 자체가 안 되는 PC가 만들어진다.
        if not req.requires_dgpu:
            rows = [r for r in rows if has_igpu(r["name"])]
    elif stage == "gpu":
        # *** 수정(실사용자 제공 밸런스 가이드 1-①): CPU-GPU 체급이 1단계를
        # 초과해서 벌어지면 안 됨. 4단계(entry/mainstream/high/flagship)로
        # 나눠서, CPU 버킷 기준 상하 1단계 이내의 GPU만 후보로 남긴다 —
        # "필요조건(req.gpu_tier_min)"과 "밸런스 상한"을 동시에 만족해야 한다.
        # context에 cpu가 없으면(예: 예산 사전 체크용 단독 조회) 밸런스
        # 필터는 건너뛰고 요구조건만 적용한다.
        # *** 신설(실사용자 결정: "(CPU+GPU 평균 소비전력)×1.3" 공식) ***
        # danawa_spec_summary의 "사용전력"("최대 450W" 또는 "160W" 형태)에서
        # 숫자만 뽑는다.
        rows = _fetch_all(
            conn, "vga_products_v", media_category="vga",
            extra_select=(
                "(SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='vga' AND product_id=p.product_id "
                " AND spec_key='사용전력' LIMIT 1) AS avg_power_w"
            ),
        )
        rows = [r for r in rows if (r["tier_rank"] or 0) >= req.gpu_tier_min]
        cpu = context.get("cpu")
        if cpu:
            cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
            if cpu_bucket:
                cpu_idx = BUCKET_ORDER.index(cpu_bucket)
                allowed = set(BUCKET_ORDER[max(0, cpu_idx - 1): cpu_idx + 2])
                balanced = [r for r in rows if gpu_tier_bucket(r["tier_rank"]) in allowed]
                if balanced:
                    rows = balanced
    elif stage == "mboard":
        cpu = context["cpu"]
        rows = _fetch_all(conn, "mboard_products_v", "socket = %s AND usage_type = 'consumer'", (cpu["socket"],), media_category="mboard")
        if opt.placement == "미니 PC":
            rows = [r for r in rows if r["form_factor"] == "ITX"]
        # *** 수정(실사용자 발견: "i9-14900KS에 B760 보급형 보드가 붙음") ***
        # 예전엔 GPU 체급만 보고 메인보드 라인업을 골랐는데, 메인보드
        # 전원부(VRM) 품질은 실제로 CPU 전력 소모가 더 크게 좌우한다 —
        # CPU와 GPU 버킷 중 "더 상위"인 쪽을 기준으로 삼는다(가이드 1-②
        # 원문도 "권장 매칭(CPU & GPU)"라고 둘 다 명시하고 있었는데 GPU만
        # 반영했던 게 누락이었다).
        cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        gpu = context.get("gpu")
        gpu_bucket = gpu_tier_bucket(gpu.get("tier_rank")) if gpu else None
        buckets = [b for b in (cpu_bucket, gpu_bucket) if b]
        if buckets:
            idx = max(BUCKET_ORDER.index(b) for b in buckets)
            allowed = set(BUCKET_ORDER[max(0, idx - 1): idx + 2])
            matched = [r for r in rows if mboard_lineup_bucket(r["name"]) in allowed]
            if matched:
                rows = matched
    elif stage == "ram":
        # *** 수정(실사용자 재요청: "메인보드를 다시 먼저 가져올 것") ***
        # 메인보드가 다시 RAM보다 먼저 온다 — 메인보드가 정한 ram_type/
        # ram_slot_count를 그대로 받아서 그 안에서 RAM을 고른다(속도 우선
        # 순위·듀얼채널 로직은 _fetch_ram_options 안에서 그대로 유지).
        mboard = context["mboard"]
        rows = _fetch_ram_options(conn, mboard["ram_type"], mboard["ram_slot_count"], req.ram_gb_min, mode)
    elif stage == "cooler":
        # *** 수정(실사용자 최종 결정) ***
        # 1) 등급 기반 강제: i7/i9 "중에서도 K 시리즈"만 무조건 3열 수랭
        #    (라디에이터 390mm+) — K 시리즈만으로 좁혔다(비K는 아래 2번
        #    수치 검증만 통과하면 공랭도 허용).
        # 2) 수치 기반 검증: *** 수정(실사용자 재결정) *** 쿨러는 GPU 발열과
        #    무관하다(GPU는 자체 쿨러가 있으므로) — CPU 단독 발열만 해결하면
        #    된다. 그리고 이번엔 "최댓값(MTP)"만 쓰기로 했다(평균/최저 안 씀).
        #    CPU.max_power_w × 1.3 <= 쿨러.tdp_rating_w. 수랭은 tdp_rating_w
        #    데이터가 부실한 경우가 많아 이 수치 검증에서 면제한다(1번
        #    규칙과 발열 등급 규칙으로 충분히 커버됨 — 공랭만 대상).
        cpu = context["cpu"]
        # *** 매칭 로직 사전 준비(실사용자 요청: "케이스 라디에이터 매칭은
        # 팬길이×팬개수로") *** fan_length_mm/fan_count도 CPU 코어/스레드
        # 사전 준비와 같은 방식으로 미리 연결해둔다 — 실제 spec_key 이름은
        # 아직 확인 못 해서 TODO로 추정값을 넣어뒀다(danawa_spec_summary에
        # category='cooler'로 조회해서 정확한 이름을 확인해야 한다).
        rows = _fetch_all(
            conn, "cooler_products_v", media_category="cooler",
            extra_select=(
                "(SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cooler' AND product_id=p.product_id "
                " AND spec_key='팬 크기' LIMIT 1) AS fan_length_mm, "  # TODO: 실제 spec_key로 교체
                "(SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED) "
                " FROM danawa_spec_summary WHERE category='cooler' AND product_id=p.product_id "
                " AND spec_key='팬 개수' LIMIT 1) AS fan_count"  # TODO: 실제 spec_key로 교체
            ),
        )
        rows = [r for r in rows if cpu["socket"] in [s.strip() for s in (r["support_sockets"] or "").split(",")]]

        bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        if bucket in ("high", "flagship") and is_k_series(cpu["name"]):
            rows = [
                r for r in rows
                if r["cooler_type"] == "수랭" and (r["radiator_length_mm"] or 0) >= 390
            ]
        else:
            required_cooling_w = round((cpu.get("max_power_w") or 0) * 1.3)
            rows = [
                r for r in rows
                if r["cooler_type"] == "수랭" or (r["tdp_rating_w"] or 0) >= required_cooling_w
            ]

        # *** 신설(실사용자 제공 RAM 매칭 가이드 5절: "대장급 공랭 쿨러 사용 시
        # 방열판 높은 튜닝 RAM과 물리적 간섭") ***
        # cooler_products엔 "RAM 클리어런스"(첫 슬롯까지의 여유 공간) 컬럼이
        # 없어서 정확한 물리 치수 비교는 못 한다 — 대신 실무에서 흔히 쓰이는
        # 경험적 기준(공랭 쿨러 자체 높이 155mm 이상 = "대장급"으로 분류되는
        # 제품군, RAM 히트싱크 40mm 초과 = 간섭 위험이 실제로 자주 보고되는
        # 두께)으로 근사한다. 정확한 클리어런스 값이 나중에 추가되면 이
        # 근사 규칙을 교체하면 된다.
        ram = context.get("ram")
        ram_height = ram.get("heatsink_height_mm") if ram else None
        if ram_height and ram_height > 40:
            rows = [
                r for r in rows
                if r["cooler_type"] != "공랭" or (r["height_mm"] or 0) < 155
            ]

        # *** 신설(실사용자 발견: "성능 모드 다운그레이드에서 케이스가 쿨러보다
        # 먼저 정해지도록 순서를 바꿨더니, 케이스 선택 시점엔 쿨러가 아직
        # 수랭이라 케이스 쪽 공랭 높이 체크(case 스테이지의 max_cooler_height_mm
        # 검사)가 통째로 스킵된다 — 나중에 쿨러가 진짜로 공랭으로 바뀌어도
        # 이미 정해진 케이스와 실제로 맞는지 아무도 확인 안 한다") ***
        # case가 이미 정해져 있으면(다운그레이드 흐름), 공랭 후보를 그 케이스의
        # max_cooler_height_mm으로 직접 걸러서 이 구멍을 메운다. 가성비 모드나
        # case가 아직 없는 시점(cooler가 case보다 먼저인 STAGES 순서)에는
        # context에 case가 없으므로 이 필터는 자동으로 건너뛴다.
        case = context.get("case")
        if case:
            rows = [
                r for r in rows
                if r["cooler_type"] != "공랭" or (r["height_mm"] or 0) <= (case["max_cooler_height_mm"] or 0)
            ]
    elif stage == "psu":
        # *** 수정(실사용자 최종 결정: PSU/쿨러 계산식을 하나로 통일) ***
        # 순간 피크(GPU recommended_psu_w, 이미 제조사 마진 포함된 값)
        # 대신, "(CPU 평균 소비전력 + GPU 평균 소비전력) × 1.3"으로
        # 통일한다. CPU는 danawa "PBP-MTP"의 PBP(기본전력), GPU는
        # "사용전력"에서 가져온다(둘 다 CPU/GPU 스테이지 조회 시 이미
        # avg_power_w로 파싱해뒀다).
        cpu = context["cpu"]
        gpu = context.get("gpu")
        cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        # avg_power_w 데이터가 없는 상품(스펙 미확보)을 대비한 안전망 —
        # 계산값이 이 최소치보다 작으면 최소치를 쓴다.
        min_by_cpu = {"entry": 400, "mainstream": 500, "high": 650, "flagship": 750}.get(cpu_bucket, 400)
        cpu_power = cpu.get("avg_power_w") or 0
        gpu_power = (gpu.get("avg_power_w") or 0) if gpu else 0
        required_w = max(round((cpu_power + gpu_power) * 1.3), min_by_cpu)
        form = "SFX" if opt.placement == "미니 PC" else None
        rows = _fetch_all(conn, "power_products_v", "rated_w >= %s", (required_w,), media_category="power")
        # *** 신설(실사용자 제공 PSU 안전 가이드): 고성능 GPU(RTX 4070Ti/5070Ti/
        # 4080/5080/4090/5090급, tier_rank>=9)는 12VHPWR 케이블을 쓰는데,
        # PSU가 ATX 3.0/3.1 네이티브 지원이 아니면(구형 ATX + 변환젠더) 접촉
        # 불량/전류 쏠림으로 케이블 멜팅·화재 위험이 있다 — 상품명에
        # ATX3.0/3.1 또는 12VHPWR/12V-2x6 표기가 명시된 것만 후보로 남긴다
        # (그냥 "ATX 파워"라고만 된 건 구형으로 간주, 가이드 원문 판정 규칙).
        if gpu and (gpu.get("tier_rank") or 0) >= HIGH_POWER_GPU_TIER_THRESHOLD:
            rows = [r for r in rows if has_atx3_support(r["name"])]
        # *** 신설(실사용자 최종 결정: "가성비=Bronze~Silver, 성능=Gold 이상") ***
        # 가성비 모드는 최소 브론즈, 성능 모드는 최소 골드를 요구한다(무인증
        # 제품은 둘 다 배제) — 상한은 두지 않는다(더 좋은 인증이면 당연히 통과).
        min_tier = "GOLD" if mode == "perf" else "BRONZE"
        rows = [r for r in rows if meets_80plus_minimum(r["name"], min_tier)]
        if form:
            rows = [r for r in rows if r["form_factor"] == form]
        # *** 신설(실사용자 발견과 동일한 클래스의 버그: 성능 모드 다운그레이드
        # 순서(DOWNGRADE_ORDER)에서 case가 psu보다 먼저 확정된다 — case는 그
        # 시점의 psu 폼팩터를 보고 골라지는데, 여기 psu 후보는 opt.placement가
        # "미니 PC"가 아니면 폼팩터 필터가 전혀 없어 ATX/SFX/TFX가 가격순으로
        # 뒤섞인다. 다운그레이드가 더 싼 다른 폼팩터 PSU를 고르면, 이미 확정된
        # case가 실제로는 그 폼팩터를 지원 안 하는 조합이 나올 수 있다 —
        # 쿨러-케이스 높이 검증(위 "cooler" 스테이지)과 같은 문제라 같은 방식
        # (context에 case가 이미 있으면 그 case가 지원하는 폼팩터로 역필터)으로
        # 막는다. case가 아직 없는 시점(search()의 기본 STAGES 순서 — psu가
        # case보다 먼저)에는 context에 case가 없으므로 자동으로 건너뛴다. ***
        case = context.get("case")
        if case:
            rows = [
                r for r in rows
                if r["form_factor"] and case["support_psu_form_factors"]
                and _psu_form_factor_matches(r["form_factor"], case["support_psu_form_factors"])
            ]
    elif stage == "case":
        mboard, cooler, psu = context["mboard"], context["cooler"], context["psu"]
        gpu = context.get("gpu")
        rows = _fetch_all(conn, "case_products_v", media_category="case")
        rows = [r for r in rows if mboard["form_factor"] in [s.strip() for s in (r["support_form_factors"] or "").split(",")]]
        # *** 수정(실사용자 요청: GPU 없는 문서작업용 PC 지원) ***
        # 외장 GPU가 없으면(내장그래픽만 사용) 케이스의 GPU 길이 제약 자체가
        # 의미가 없으니 이 조건을 건너뛴다.
        if gpu:
            rows = [r for r in rows if (gpu["length_mm"] or 0) + 20 <= (r["max_vga_length_mm"] or 0)]
        rows = [r for r in rows if psu["form_factor"] and r["support_psu_form_factors"] and _psu_form_factor_matches(psu["form_factor"], r["support_psu_form_factors"])]
        if cooler["cooler_type"] == "공랭":
            rows = [r for r in rows if (cooler["height_mm"] or 0) <= (r["max_cooler_height_mm"] or 0)]
        else:
            # *** 수정(실사용자 최종 결정: "라디에이터 길이 옵션이 아니라
            # '팬 길이 × 팬 개수' <= 케이스 라디에이터 지원 크기로 매칭") ***
            # 케이스의 라디에이터 지원 크기 컬럼(radiator_support_mm)이
            # 아직 없어서(원본 크롤링 데이터에 케이스 카테고리 항목 자체가
            # 없음이 확인됨) r.get()으로 안전하게 접근한다 — 값이 없으면
            # 이 검증을 건너뛴다(과도한 배제 방지, 나중에 데이터 생기면
            # 자동으로 검증이 활성화된다).
            fan_length = cooler.get("fan_length_mm")
            fan_count = cooler.get("fan_count")
            if fan_length and fan_count:
                required_radiator_mm = fan_length * fan_count
                rows = [
                    r for r in rows
                    if not r.get("radiator_support_mm") or required_radiator_mm <= r["radiator_support_mm"]
                ]
        # *** 수정(실제 스키마 연결): case_products에 수랭 라디에이터 지원 크기
        # 컬럼(radiator_support_mm)이 아직 없어서(나중에 추가 컬럼 작업 때 처리),
        # 위 검증은 지금은 사실상 항상 통과한다(데이터가 없으면 건너뜀) —
        # 크롤링 완료 후 이 컬럼이 채워지면 자동으로 정상 작동한다. ***
        if opt.placement == "미니 PC":
            rows = [r for r in rows if r["support_form_factors"] == "ITX"]
        elif opt.placement == "책상 위":
            # 책상 위에 놓기 좋은 미니타워/미들타워를 우선한다(상품명 기반 — 미니 PC처럼
            # 완전히 강제하지는 않는다, 조건을 만족하는 상품이 없으면 전체로 폴백).
            preferred = [r for r in rows if ("미니타워" in r["name"] or "미들타워" in r["name"])]
            if preferred:
                rows = preferred
        elif opt.placement == "책상 아래":
            preferred = [r for r in rows if ("미들타워" in r["name"] or "빅타워" in r["name"])]
            if preferred:
                rows = preferred

        if opt.rgb == "화려":
            preferred = [r for r in rows if ("RGB" in r["name"].upper())]
            if preferred:
                rows = preferred
        elif opt.rgb == "없음":
            preferred = [r for r in rows if ("RGB" not in r["name"].upper())]
            if preferred:
                rows = preferred
    else:
        rows = []

    if mode == "cost":
        rows.sort(key=lambda r: r["price_krw"])
    else:  # perf: 등급 높은 것 우선(CPU/GPU), 나머지는 비싼 것(더 좋은 것으로 간주) 우선
        if stage == "cpu" or stage == "gpu":
            rows.sort(key=lambda r: (-(r["tier_rank"] or 0), -r["price_krw"]))
        else:
            rows.sort(key=lambda r: -r["price_krw"])
    return rows


REVIEWABLE_STAGES = {"gpu", "mboard", "ram", "cooler", "psu", "case"}
MAX_REVIEW_RETRIES_PER_STAGE = 5  # 같은 스테이지에서 검수 거부가 반복될 때 API 호출 상한


def search(req: Requirements, opt: Options, mode: str,
           start_stage: str = "cpu", fixed_parts: dict | None = None,
           with_review: bool = False) -> BuildResult:
    """스택 기반 순차 결정 + 백트래킹 (기획서 2.2.1절).

    start_stage/fixed_parts: 부품 업그레이드 기능(2.5절)에서, CPU/GPU/메인보드처럼
    이미 확정된 앞단은 그대로 두고 특정 스테이지부터만 다시 탐색할 때 쓴다
    (예: RAM 용량 개선은 start_stage="ram", fixed_parts={"cpu":..., "gpu":..., "mboard":...}).

    *** 수정(실사용자 발견: "물리 스펙 없을 때 견적 생성이 몇 분씩 걸림") ***
    메인보드는 CPU만 보고 정해지는데, 백트래킹은 무조건 "바로 이전 스테이지"부터
    다시 시도한다 — 메인보드 실패가 GPU와 무관해도, GPU 후보 수만큼 메인보드를
    반복 조회하게 되어 CPU×GPU 조합 수만큼(수만 번) DB 쿼리가 발생했다.
    STAGE_DEPENDENCIES로 각 스테이지가 실제로 어떤 이전 스테이지에 의존하는지
    정의해두고, 그 의존 대상의 product_id만으로 캐시 키를 만들어 같은 조합을
    다시 조회하지 않도록 한다 — 탐색 순서 자체는 그대로 두고 중복 조회만 없앤다.

    *** 수정(실사용자 재요청: 단계별 누적 Gemini 검수) *** with_review=True면,
    각 스테이지에서 후보를 하나 고를 때마다(CPU는 비교 대상이 없어 제외,
    GPU부터 시작) "지금까지 확정된 부품 + 이번 후보"를 Gemini에 보내 검수한다.
    문제가 있다고 답하면 이 후보는 버리고 같은 스테이지의 다음 후보를 시도한다
    (기존 백트래킹 루프에 자연스럽게 편입 — 후보 소진과 동일하게 처리하되,
    "검수 탈락"과 "완전 소진"을 구분해서 review_notes에 남긴다). 같은 스테이지에서
    검수 탈락이 MAX_REVIEW_RETRIES_PER_STAGE번을 넘으면 더 이상 검수하지 않고
    그냥 다음 후보로 진행한다(API 호출 폭주 방지 — 예: 카탈로그 데이터 자체가
    부실해서 Gemini가 계속 다른 이유로 거부하는 경우를 대비).
    *** 신설(실사용자 요청: "문서작업용 PC는 GPU 없이 내장그래픽 CPU만") ***
    req.requires_dgpu가 False면 GPU 스테이지 자체를 건너뛴다 — 전역 STAGES
    상수 대신, 이번 탐색에서 실제로 쓸 스테이지 목록(active_stages)을
    동적으로 계산해서 쓴다.
    """
    fixed_parts = fixed_parts or {}
    active_stages = [s for s in STAGES if s != "gpu" or req.requires_dgpu]
    start_idx = active_stages.index(start_stage)
    conn = get_connection()
    candidate_cache: dict[tuple, list[dict]] = {}
    review_notes: list[str] = []
    review_retry_count: dict[int, int] = {}  # stage_idx -> 이 스테이지에서 검수 거부 누적 횟수
    try:
        stack: list[tuple[int, dict]] = [(0, fixed_parts[s]) for s in active_stages[:start_idx]]
        stage_idx = start_idx
        candidate_idx = 0

        while True:
            if stage_idx == len(active_stages):
                parts = {active_stages[i]: stack[i][1] for i in range(len(active_stages))}
                total = sum(p["price_krw"] for p in parts.values())
                return BuildResult(parts=parts, total_price=total, status="ok", review_notes=review_notes)

            stage = active_stages[stage_idx]
            context = {active_stages[i]: stack[i][1] for i in range(stage_idx)}
            cache_key = (
                stage,
                tuple(context[dep]["product_id"] for dep in STAGE_DEPENDENCIES[stage] if dep in context),
            )
            if cache_key not in candidate_cache:
                candidate_cache[cache_key] = get_candidates(conn, stage, context, req, opt, mode)
            candidates = candidate_cache[cache_key]

            if candidate_idx >= len(candidates):
                # 이 스테이지 후보 소진 -> 백트래킹(2.2.1절)
                if stage_idx == start_idx:
                    return BuildResult(status="no_matching_product", message="해당하는 상품을 찾을 수 없습니다", review_notes=review_notes)
                stage_idx -= 1
                prev_idx, _ = stack.pop()
                candidate_idx = prev_idx + 1
                review_retry_count.pop(stage_idx, None)
                continue

            chosen = candidates[candidate_idx]

            if with_review and stage in REVIEWABLE_STAGES:
                retries = review_retry_count.get(stage_idx, 0)
                if retries < MAX_REVIEW_RETRIES_PER_STAGE:
                    trial_parts = dict(context)
                    trial_parts[stage] = chosen
                    review = gemini_review.review_partial(conn, trial_parts, stage)
                    if review and review["issue"]:
                        review_retry_count[stage_idx] = retries + 1
                        review_notes.append(
                            f"Gemini 검수: {chosen['name']} 거부됨({review['reason']}) — 다음 후보로 대체"
                        )
                        candidate_idx += 1
                        continue
                    elif review and retries == 0:
                        # 첫 시도에 바로 통과한 경우에만 "정상 통과" 로그를 남긴다(과도한 기록 방지)
                        pass

            stack.append((candidate_idx, chosen))
            stage_idx += 1
            candidate_idx = 0
    finally:
        conn.close()


def check_data_readiness(conn) -> str | None:
    """
    *** 신설(실사용자 발견: "물리 스펙 없을 때 견적 생성이 몇 분씩 걸리다 무한
    로딩") *** STAGE_DEPENDENCIES 캐싱은 "같은 조합을 두 번 조회 안 하는" 것만
    막아줄 뿐, 케이스처럼 메인보드+쿨러+GPU+PSU 4개에 동시에 의존하는 스테이지가
    스펙 데이터 자체가 하나도 없어서 무조건 실패하는 경우엔 여전히 그 4개
    조합 수만큼(수백만 번) 반복하게 된다 — 탐색을 시작하기 전에 각 스테이지의
    호환성 컬럼에 데이터가 조금이라도 있는지 미리 확인해서, 없으면 즉시
    실패 메시지를 준다(탐색 자체를 시도하지 않음).

    반환값: 문제없으면 None, 문제 있으면 사람이 읽을 안내 메시지.
    """
    checks = [
        ("cpu_products", "socket", "CPU 소켓"),
        ("mboard_products", "socket", "메인보드 소켓"),
        ("mboard_products", "form_factor", "메인보드 폼팩터"),
        ("mboard_products", "ram_type", "메인보드 RAM 규격"),
        ("mboard_products", "ram_slot_count", "메인보드 RAM 슬롯 수"),
        ("ram_products", "ram_type", "RAM 규격"),
        ("cooler_products", "support_sockets", "쿨러 지원 소켓"),
        ("cooler_products", "cooler_type", "쿨러 타입(공랭/수랭)"),
        ("vga_products", "recommended_psu_w", "GPU 권장 전력"),
        ("power_products", "rated_w", "PSU 정격 출력"),
        ("power_products", "form_factor", "PSU 폼팩터"),
        ("case_products", "support_form_factors", "케이스 지원 폼팩터"),
        ("case_products", "max_vga_length_mm", "케이스 최대 GPU 길이"),
        ("case_products", "support_psu_form_factors", "케이스 지원 PSU 폼팩터"),
    ]
    cursor = conn.cursor()
    missing = []
    for table, column, label in checks:
        cursor.execute(f"SELECT COUNT({column}) FROM {table}")
        (count,) = cursor.fetchone()
        if count == 0:
            missing.append(label)
    cursor.close()
    if missing:
        return (
            "물리 스펙 데이터가 아직 준비되지 않았습니다(" + ", ".join(missing) + " 없음) — "
            "spec_scraper.py 실행 또는 팀원 덤프 반영이 필요합니다."
        )
    return None

def build_cost_efficient(
    req: Requirements, opt: Options, budget: int,
    ssd_gb_min: int = 500, hdd_gb_min: int = 0,
) -> BuildResult:
    """가성비 모드(2.3절): CPU+GPU 최소 조합가가 예산보다 크면 즉시 종료(최적화).

    *** 수정(실사용자 발견: "성능 모드 최초 견적이 이미 예산을 초과") ***
    저장장치(SSD/HDD)는 STAGES에 없어서 search()가 아예 모르는 항목인데,
    예전엔 이 함수가 반환한 뒤 API 레이어에서 저장장치를 나중에 붙이면서
    예산 재확인을 전혀 안 했다 — 그래서 부품 7개로는 예산 안에 들어왔어도
    저장장치를 더하면 초과하는 사고가 났다. 이제 저장장치 가격을 먼저 계산해서
    "부품에 쓸 수 있는 예산"에서 미리 빼두고, 최종 결과에 저장장치를 포함해서
    반환한다 — 이러면 반환되는 total_price가 항상 실제 예산 이내임을 보장한다.
    """
    storage = select_storage(ssd_gb_min, hdd_gb_min)
    storage_price = sum(p["price_krw"] for p in storage.values() if p)
    parts_budget = budget - storage_price
    if parts_budget < 0:
        return BuildResult(
            status="budget_insufficient",
            message=f"저장장치 최저가({storage_price:,}원)만으로도 예산을 초과합니다",
        )

    conn = get_connection()
    readiness_issue = check_data_readiness(conn)
    if readiness_issue:
        conn.close()
        return BuildResult(status="no_matching_product", message=readiness_issue)
    cpus = get_candidates(conn, "cpu", {}, req, opt, "cost")
    # *** 수정(실사용자 요청: GPU 없는 문서작업용 PC 지원) ***
    # requires_dgpu가 False면 GPU 최저가를 아예 조회하지 않는다(그 사전
    # 체크 자체가 의미 없다 — 예산 하한선은 CPU만으로 계산한다).
    gpus = get_candidates(conn, "gpu", {}, req, opt, "cost") if req.requires_dgpu else []
    conn.close()
    if not cpus or (req.requires_dgpu and not gpus):
        return BuildResult(status="no_matching_product", message="요구 성능을 만족하는 CPU 또는 GPU가 없습니다")
    min_cpu_gpu = cpus[0]["price_krw"] + (gpus[0]["price_krw"] if gpus else 0)
    if min_cpu_gpu > parts_budget:
        return BuildResult(
            status="budget_insufficient",
            message=f"최소한 {min_cpu_gpu + storage_price:,}원 이상의 예산이 필요합니다(CPU+GPU+저장장치 최저가 기준)",
        )
    # *** 수정(실사용자 요청: "단계별 검수 대신 최종 한 번만 검수") ***
    # with_review=False로 단계별 누적 검수를 끈다(나중에 다시 켤 수 있도록
    # search() 자체의 기능은 그대로 남겨뒀다) — 대신 아래 _apply_final_review로
    # 완성된 견적을 딱 한 번만 검수한다.
    result = search(req, opt, mode="cost", with_review=False)
    if result.status == "ok" and result.total_price > parts_budget:
        return BuildResult(
            status="budget_insufficient",
            message=f"최소 견적조차 예산을 초과합니다 — 최소한 {result.total_price + storage_price:,}원의 예산이 필요합니다",
        )
    return _apply_final_review(_attach_storage(result, storage), req, opt, budget)


def _attach_storage(result: BuildResult, storage: dict) -> BuildResult:
    """검색 결과(BuildResult)에 저장장치를 합쳐서 새 BuildResult를 만든다.
    build_cost_efficient/build_performance가 반환하는 결과에는 항상 저장장치가
    포함돼 있어야, 그 total_price가 실제로 지불해야 할 총액과 정확히 일치한다."""
    if result.status != "ok":
        return result
    parts = dict(result.parts)
    total = result.total_price
    for key in ("ssd", "hdd"):
        if storage.get(key):
            parts[key] = storage[key]
            total += storage[key]["price_krw"]
    return BuildResult(parts=parts, total_price=total, status="ok")


def _apply_final_review(result: BuildResult, req: Requirements, opt: Options, budget: int) -> BuildResult:
    """*** 신설(실사용자 요청: "단계별 검수 대신 최종 한 번만 검수해서 안정성
    테스트") *** 완성된 견적(저장장치 포함)에 대해 Gemini 검수를 딱 한 번
    호출한다 — search()의 with_review=True(단계별 누적 검수)는 지금
    꺼져있고(아래 build_cost_efficient/build_performance 참고), 대신 여기서
    전체를 한 번에 본다. 문제 있는 카테고리가 있으면 그 부품만 같은 호환
    조건 안에서 다음 후보로 교체한다(다른 부품은 그대로 유지) — 나중에
    다시 단계별 검수로 되돌릴 수 있도록 search()의 with_review 기능
    자체는 그대로 남겨뒀다."""
    if result.status != "ok":
        return result

    conn = get_connection()
    try:
        review = gemini_review.review_final(conn, result.parts)
        if review is None or not review["issue"]:
            return result

        category = review["category"]
        if category not in result.parts:
            result.review_notes.append(f"Gemini 검수: 문제 발견({review['reason']})했지만 대상 카테고리를 특정하지 못해 그대로 둡니다.")
            return result

        # 문제로 지목된 부품 하나만 같은 호환 조건(다른 부품들은 고정)에서 재조회한다.
        context = {s: result.parts[s] for s in result.parts if s != category}
        candidates = get_candidates(conn, category, context, req, opt, "cost")
        match = gemini_review.find_best_match(candidates, review["suggested_model"], result.parts[category]["product_id"])
        if not match:
            result.review_notes.append(f"Gemini 검수: {category} 이슈 발견({review['reason']})했지만 대체할 상품이 없어 유지합니다.")
            return result

        new_total = result.total_price - result.parts[category]["price_krw"] + match["price_krw"]
        if new_total > budget:
            result.review_notes.append(f"Gemini 검수: {category} 이슈 발견({review['reason']})했지만 대체 부품이 예산을 초과해 유지합니다.")
            return result

        new_parts = dict(result.parts)
        new_parts[category] = match
        new_result = BuildResult(parts=new_parts, total_price=new_total, status="ok", review_notes=list(result.review_notes))
        new_result.review_notes.append(f"Gemini 검수: 원래 {category}({review['reason']}) 대신 {match['name']}로 교체했습니다.")
        return new_result
    finally:
        conn.close()


_STORAGE_OPTION_RE = re.compile(r"^\s*(?:(\d+)\s*[xX]\s*)?(\d+(?:\.\d+)?)\s*(GB|TB)", re.IGNORECASE)


def _parse_storage_option(option_name: str) -> tuple[int, int] | None:
    """다나와 SSD/HDD 옵션명에서 (단품 용량GB, 묶음 개수)를 뽑아낸다.
    SSD는 "512GB_1,549원/1GB", "1TB_980원/1GB" 형태(묶음 없음)이고,
    HDD는 그 외에 "2x12TB_77원/1GB"(12TB 2개 묶음, 서버·벌크용 판매 단위)
    형태도 있다 — 묶음 개수가 있으면 호출부에서 "일반 조립 PC엔 안 맞는
    벌크 상품"으로 보고 제외한다(케이스 안에 여러 개 넣을 자리를 확인하는
    로직이 없어서, 안전하게 단품만 후보로 삼는다)."""
    m = _STORAGE_OPTION_RE.match(option_name or "")
    if not m:
        return None
    pack_count = int(m.group(1)) if m.group(1) else 1
    size = float(m.group(2))
    unit = m.group(3).upper()
    capacity_gb = int(size * 1000) if unit == "TB" else int(size)
    return capacity_gb, pack_count


def _fetch_storage_options(conn, prefix: str, media_category: str, gb_min: int) -> list[dict]:
    """SSD/HDD를 상품 단위가 아니라 "옵션"(용량) 단위로 조회한다 — RAM과 동일한
    방식으로, capacity_gb 컬럼 없이 다나와 option_name에서 용량을 파싱한다.
    2개/4개 묶음(벌크) 표기가 있는 옵션은 일반 조립 PC 용도가 아니라고 보고
    제외하고, 단품(묶음 개수 1)만 후보로 남긴다.
    prefix: "ssd" 또는 "hdd" — {prefix}_products/{prefix}_prices 테이블을 조회한다."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""
        SELECT p.product_id, p.name, pp.option_name, pp.price AS price_krw,
               m.image_url, m.product_url
        FROM {prefix}_products p
        JOIN {prefix}_prices pp ON pp.product_id = p.product_id
        LEFT JOIN product_media m ON m.category = '{media_category}' AND m.product_id = p.product_id
        WHERE pp.crawl_date = (SELECT MAX(crawl_date) FROM {prefix}_prices)
        """
    )
    rows = cursor.fetchall()
    cursor.close()

    options = []
    for row in rows:
        parsed = _parse_storage_option(row["option_name"])
        if parsed is None:
            continue
        capacity_gb, pack_count = parsed
        if pack_count != 1:
            continue  # 벌크(서버용) 묶음 상품 제외
        if capacity_gb < gb_min:
            continue
        options.append({
            "product_id": row["product_id"],
            "name": f"{row['name']} {row['option_name'].split('_')[0]}",
            "price_krw": row["price_krw"],
            "capacity_gb": capacity_gb,
            "image_url": row["image_url"],
            "product_url": row["product_url"],
        })
    return options


def select_storage(ssd_gb_min: int = 500, hdd_gb_min: int = 0) -> dict:
    """저장장치 선택 (기획서 10장 확인 필요 항목: 순차 결정 순서에 저장장치 단계가
    명시적으로 없어서, 어느 시점에 처리할지 미정 — 이 프로토타입에서는 잠정적으로
    다른 부품과 호환성 제약이 없는 독립 항목으로 보고, 메인 순차 결정과 별개로
    붙이는 후처리 단계로 둔다.

    *** 수정(RAM과 동일한 발견 적용): ssd_products/hdd_products에 용량(GB)
    컬럼은 없지만, 다나와 option_name에 용량이 이미 있어서 컬럼 추가 없이도
    실제 용량 요구사항을 검증할 수 있다. ***"""
    conn = get_connection()
    try:
        ssds = _fetch_storage_options(conn, "ssd", "ssd", ssd_gb_min)
        ssds.sort(key=lambda r: r["price_krw"])
        ssd = ssds[0] if ssds else None

        hdd = None
        if hdd_gb_min > 0:
            hdds = _fetch_storage_options(conn, "hdd", "hdd", hdd_gb_min)
            hdds.sort(key=lambda r: r["price_krw"])
            hdd = hdds[0] if hdds else None

        return {"ssd": ssd, "hdd": hdd}
    finally:
        conn.close()


def check_bottleneck(cpu_row: dict, gpu_row: dict) -> bool:
    """CPU-GPU 체급 불균형(병목) 여부 — 실제로는 Gemini가 PC 용도까지 감안해
    최종 검수한다(기획서 1.4/2.4절). 프로토타입에서는 등급 격차가 too 크면
    병목으로 보는 간단한 임시 규칙으로 대체한다.

    *** 수정(실제 스키마 연결): 이름 매칭(core/tiers.py) 대신 DB의
    tier_rank 컬럼을 직접 쓴다 — cpu_performance_tier_fix.sql 기준 CPU는
    1~25, gpu_performance_tier 기준 GPU는 1~14 스케일이라 정규화 분모를
    거기에 맞췄다. ***"""
    ct, gt = cpu_row.get("tier_rank"), gpu_row.get("tier_rank")
    if ct is None or gt is None:
        return False
    ct_norm, gt_norm = ct / 25, gt / 14
    return abs(ct_norm - gt_norm) > 0.55


# 성능 모드 다운그레이드 순서(2.4절): 가성비 모드의 정반대
DOWNGRADE_ORDER = ["case", "psu", "cooler", "ram", "mboard", "gpu", "cpu"]
# *** 신설(실사용자 요청: "단계별 검수 대신 최종 한 번만 검수해서 안정성
# 테스트") *** True로 바꾸면 다운그레이드 중 후보마다 다시 검수한다
# (예전 동작으로 복귀). 지금은 build_cost_efficient/build_performance
# 둘 다 최종 한 번(_apply_final_review)만 검수하도록 꺼져있다.
DOWNGRADE_REVIEW_ENABLED = False


def build_performance(
    req: Requirements, opt: Options, budget: int,
    ssd_gb_min: int = 500, hdd_gb_min: int = 0,
) -> BuildResult:
    """성능 모드(2.4절): 최대 견적을 만든 뒤 예산 초과 시 역순으로 다운그레이드.

    가성비 모드와 동일한 이유로, 저장장치 가격을 먼저 빼둔 "부품용 예산"
    기준으로 다운그레이드를 진행하고, 최종 결과에 저장장치를 포함해서
    반환한다 — 반환되는 total_price가 항상 budget 이내임을 보장한다.
    """
    storage = select_storage(ssd_gb_min, hdd_gb_min)
    storage_price = sum(p["price_krw"] for p in storage.values() if p)
    parts_budget = budget - storage_price
    if parts_budget < 0:
        return BuildResult(
            status="budget_insufficient",
            message=f"저장장치 최저가({storage_price:,}원)만으로도 예산을 초과합니다",
        )

    conn = get_connection()
    readiness_issue = check_data_readiness(conn)
    conn.close()
    if readiness_issue:
        return BuildResult(status="no_matching_product", message=readiness_issue)

    # *** 수정(실사용자 요청: "단계별 검수 대신 최종 한 번만 검수") ***
    max_build = search(req, opt, mode="perf", with_review=False)
    if max_build.status != "ok":
        return max_build
    if max_build.total_price <= parts_budget:
        return _apply_final_review(_attach_storage(max_build, storage), req, opt, budget)

    # 다운그레이드 진행 상태: 각 스테이지별로 "현재 몇 단계 내렸는지" 인덱스를 추적
    conn = get_connection()
    review_notes: list[str] = []
    try:
        current = dict(max_build.parts)
        # 각 스테이지의 전체 후보를 비싼 순(perf 정렬)으로 캐싱해두고, 다운그레이드는
        # 그 리스트에서 한 칸씩 뒤로(더 저렴한 쪽으로) 이동하는 식으로 구현한다.
        candidate_cache: dict[str, list[dict]] = {}

        def candidates_for(stage):
            if stage not in candidate_cache:
                # *** 수정(실사용자 요청: GPU 없는 문서작업용 PC 지원) ***
                # 전역 STAGES 대신 current.keys()를 쓴다 — GPU 없는 빌드는
                # current에 "gpu" 키 자체가 없어서, STAGES를 그대로 쓰면
                # current["gpu"]에서 KeyError가 났다.
                context = {s: current[s] for s in current if s != stage}
                candidate_cache[stage] = get_candidates(conn, stage, context, req, opt, "perf")
            return candidate_cache[stage]

        cpu_gpu_floor_reached = False
        best_within_budget = None

        for stage in DOWNGRADE_ORDER:
            if stage not in current:
                continue  # GPU 없는 빌드는 "gpu" 스테이지 자체를 건너뛴다
            candidates = candidates_for(stage)
            try:
                cur_pos = next(i for i, c in enumerate(candidates) if c["product_id"] == current[stage]["product_id"])
            except StopIteration:
                cur_pos = 0

            # *** 수정(실사용자 발견: "CPU/GPU까지 최소 옵션으로 내렸는데도 예산을
            # 맞추지 못했다"는 메시지가, 실제로는 어느 부품도 낮아지지 않은 채 뜬다) ***
            # 예전엔 "이 스테이지 하나만 낮춰서 예산 안에 들어오는가"만 봐서, 한
            # 스테이지의 가격차만으로는 예산을 못 맞추는 게 보통인 상황(거의 항상)에
            # 그 스테이지를 최고 사양 그대로 두고 다음 스테이지로 넘어갔다 — 절감액이
            # 스테이지 사이에 전혀 누적되지 않아, 뒤쪽 GPU/CPU 차례가 와도 다른 부품이
            # 죄다 최고 사양이라 여전히 예산을 못 맞추고 실패했다(가성비 모드로는
            # 분명히 예산 안에 드는 조합이 있는데도). 이제 이 스테이지에서 예산 안에
            # 드는 후보가 하나도 없으면, 그 스테이지의 최저가 후보라도 채택해서
            # 절감분이 다음 스테이지로 누적되게 한다 — 모든 스테이지를 다 훑어도
            # 안 되면 그때 진짜로 "최소 옵션까지 내렸는데도 부족"이 맞다.
            review_retries = 0
            cheapest_pos = None
            for next_pos in range(cur_pos + 1, len(candidates)):
                trial = dict(current)
                trial[stage] = candidates[next_pos]
                total = sum(p["price_krw"] for p in trial.values())

                # GPU가 없는 빌드는 CPU-GPU 병목 개념 자체가 없으니 건너뛴다.
                bottleneck = "gpu" in trial and check_bottleneck(trial["cpu"], trial["gpu"])
                if bottleneck:
                    continue  # ③ 병목 발생 -> 이 후보는 건너뛰고 다음 후보 시도

                cheapest_pos = next_pos  # 병목 없는 후보 중 가장 마지막(=가장 저렴)

                if total <= parts_budget:
                    # *** 수정(실사용자 발견: "성능 모드에서 PSU 전력량 부족,
                    # 메인보드 등급 부족 — 다운그레이드가 검수를 안 받는다") ***
                    # *** 수정(실사용자 요청: "단계별 검수 대신 최종 한 번만
                    # 검수") *** DOWNGRADE_REVIEW_ENABLED=False로 다운그레이드
                    # 중 후보별 검수를 껐다 — 나중에 다시 단계별 검수로
                    # 되돌리고 싶으면 이 상수만 True로 바꾸면 된다(코드는
                    # 그대로 남겨뒀다).
                    if DOWNGRADE_REVIEW_ENABLED and (review_retries < MAX_REVIEW_RETRIES_PER_STAGE):
                        review = gemini_review.review_partial(conn, trial, stage)
                        if review and review["issue"]:
                            review_retries += 1
                            review_notes.append(
                                f"Gemini 검수(다운그레이드): {trial[stage]['name']} 거부됨({review['reason']}) — 다음 후보로 대체"
                            )
                            continue

                    current = trial
                    candidate_cache.pop("mboard", None)
                    candidate_cache.pop("ram", None)
                    candidate_cache.pop("cooler", None)
                    candidate_cache.pop("psu", None)
                    candidate_cache.pop("case", None)

                    if best_within_budget is None or total > best_within_budget[0]:
                        best_within_budget = (total, dict(current))
                    break  # 이 스테이지에서는 예산 안에 들어왔으니 다음 스테이지로
                # ① 계속 예산 부족 -> 이 스테이지에서 더 낮출 후보가 있으면 계속 시도
            else:
                # ② 이 스테이지 혼자서는 예산을 못 맞췄다 — 병목 없는 후보 중
                # 가장 저렴한 걸로라도 낮춰서 절감분을 다음 스테이지로 넘긴다.
                if cheapest_pos is not None:
                    current = dict(current)
                    current[stage] = candidates[cheapest_pos]
                    candidate_cache.pop("mboard", None)
                    candidate_cache.pop("ram", None)
                    candidate_cache.pop("cooler", None)
                    candidate_cache.pop("psu", None)
                    candidate_cache.pop("case", None)

            if stage in ("cpu", "gpu") and best_within_budget is None:
                cpu_gpu_floor_reached = True

        if best_within_budget is not None:
            total, parts = best_within_budget
            return _apply_final_review(
                _attach_storage(BuildResult(parts=parts, total_price=total, status="ok", review_notes=review_notes), storage),
                req, opt, budget,
            )

        if cpu_gpu_floor_reached:
            return BuildResult(
                status="budget_insufficient",
                message="CPU/GPU까지 최소 옵션으로 내렸는데도 예산을 맞추지 못했습니다",
            )
        return BuildResult(status="budget_insufficient", message="예산 내 견적을 찾지 못했습니다")
    finally:
        conn.close()
