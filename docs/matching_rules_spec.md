# PC 견적 추천 시스템 — 부품 매칭 규칙 스펙 문서

> 마지막 갱신 기준 코드: `core/algorithm.py`, `core/psu_rules.py`, `core/gemini_review.py`, `api/server.py`
> 이 문서는 코드 안 주석에 흩어진 매칭 규칙을 한 곳에 정리한 것입니다. 규칙을 바꿀 땐 코드와 이 문서를 함께 갱신하세요.

---

## 1. 전체 아키텍처

### 1.1 매칭 순서 (STAGES)

```
CPU → GPU → 메인보드 → RAM → 쿨러 → PSU → 케이스
```

각 단계는 **자신보다 앞서 확정된 부품의 정보만** 참조할 수 있습니다. 스택 기반 백트래킹 방식(`search()` 함수)으로 동작하며, 한 단계에서 후보가 모두 소진되면 이전 단계로 돌아가 다음 후보를 시도합니다.

**저장장치(SSD/HDD)는 이 순서에 없습니다** — 다른 부품과 물리적 호환성 제약이 없는 독립 항목으로 보고, `select_storage()`가 별도로 처리한 뒤 최종 결과에 붙입니다.

### 1.2 스테이지 의존관계 (STAGE_DEPENDENCIES)

각 스테이지가 **실제로 참조하는 이전 스테이지**만 명시적으로 정의해서, 백트래킹 캐시 키를 정확하게 만듭니다(안 그러면 무관한 스테이지 변경 때마다 불필요한 재조회가 발생해 성능이 크게 떨어집니다).

```python
{
    "cpu": [],
    "gpu": ["cpu"],
    "mboard": ["cpu", "gpu"],
    "ram": ["mboard"],
    "cooler": ["cpu", "ram", "gpu"],
    "psu": ["gpu", "cpu"],
    "case": ["mboard", "cooler", "gpu", "psu"],
}
```

### 1.3 성능 등급 버킷 (4단계)

CPU/GPU 각각을 `tier_rank`(정수, CPU 1~25 / GPU 1~14, `cpu_performance_tier`/`gpu_performance_tier` 테이블 기준) 값으로 갖고 있고, 이를 4단계 버킷으로 매핑합니다.

```python
CPU_TIER_BUCKETS = [(8, "entry"), (11, "mainstream"), (18, "high"), (25, "flagship")]
GPU_TIER_BUCKETS = [(2, "entry"), (5, "mainstream"), (10, "high"), (14, "flagship")]
```

| 버킷 | CPU 예시 | GPU 예시 |
|---|---|---|
| entry (1~8 / 1~2) | i3 전체, i5비K, 울트라5 하위(225~245) | RTX 5050, RTX 4060 |
| mainstream (9~11 / 3~5) | i5-K, 울트라5-K(245K~250K) | RTX 5060, RTX 4060Ti, RTX 5060Ti |
| high (12~18 / 6~10) | i7 전체, 울트라7 전체 | RTX 4070~5070Ti |
| flagship (19~25 / 11~14) | i9 전체, 울트라9 전체 | RTX 4080~5090 |

이 버킷은 CPU-GPU 밸런스, 메인보드 라인업 매칭에 공통으로 쓰입니다.

---

## 2. 부품별 매칭 규칙

### 2.1 CPU

| 조건 | 근거 |
|---|---|
| `tier_rank >= req.cpu_tier_min` | 요구 성능 등급(게임/용도에서 결정) |
| GPU 불필요 용도(문서작업)면 내장그래픽 있는 모델만 | `has_igpu(name)` — 이름에 F 접미사(단, K는 무관, "13400F"/"13700KF" 등)가 있으면 내장그래픽 없음으로 판정 |

**avg_power_w**: CPU 조회 시 `danawa_spec_summary`의 `PBP-MTP`("125-253W" 형식)에서 앞부분(PBP, Processor Base Power = 평균 소비전력)만 파싱해서 같이 가져옵니다. 뒷부분(MTP, 순간 최대전력)은 쓰지 않기로 결정했습니다.

**is_k_series(name)**: 이름에 K가 있으면(KF/KS 포함) True. 쿨러 매칭에서 "i7/i9 K시리즈는 무조건 수랭"을 판별하는 데 씁니다.

### 2.2 GPU

| 조건 | 근거 |
|---|---|
| `tier_rank >= req.gpu_tier_min` | 요구 성능 등급 |
| CPU-GPU 밸런스 | CPU 버킷 기준 **상하 1단계 이내**만 허용(병목 방지) — `context`에 CPU가 없으면(예산 사전 체크용 단독 조회) 이 필터 생략 |
| GPU 불필요 용도면 | 스테이지 자체를 건너뜀(STAGES에서 제외) |

**avg_power_w**: `danawa_spec_summary`의 `사용전력`("최대 450W" 또는 "160W" 형식)에서 숫자만 파싱.

### 2.3 메인보드

| 조건 | 근거 |
|---|---|
| `socket == CPU.socket` | 물리적 호환 필수조건 |
| 미니PC 배치 시 `form_factor == "ITX"` | 사용자 배치 옵션 |
| 라인업 등급 매칭 | CPU/GPU 버킷 중 **더 상위인 쪽** 기준 상하 1단계 이내(전원부 VRM 품질은 CPU 전력 소모가 더 크게 좌우한다는 판단) |

**라인업 등급 판별(`mboard_lineup_bucket`)**: 실제 스펙 컬럼이 없어서 상품명 키워드로 판별합니다.

| 라인업 | 키워드 |
|---|---|
| 상급(high) | MEG, MPG, MAXIMUS, STRIX, AORUS MASTER, TACHYON |
| 중급형(mainstream) | MAG, 박격포, 토마호크, TUF, AORUS ELITE |
| 보급형(entry, 기본값) | PRO, PRIME, UD, EAGLE, 기타 매칭 안 되는 것 |

매칭되는 라인업이 하나도 없으면(카탈로그가 작아서) 필터 없이 전체로 폴백합니다(과도한 배제 방지).

### 2.4 RAM

메인보드가 확정한 `ram_type`(DDR4/DDR5)과 `ram_slot_count` 안에서 선택합니다. **용량/속도 컬럼이 DB에 없어서** 다나와 가격 옵션명·상품명에서 정규식으로 파싱합니다.

| 항목 | 파싱 방식 |
|---|---|
| 용량 | 옵션명 `"32GB(16Gx2)"` 형태 → 정규식으로 총용량 추출 |
| 속도(MHz) | 상품명 `"DDR5-5600"` 형태 → 정규식 추출 |
| 히트싱크 높이 | `danawa_spec_summary`의 `높이` spec_key |

**듀얼채널 고정**: 다나와가 이미 묶어 파는 킷 옵션(예: 32Gx2)이 아니라, **단일 스틱 상품을 찾아 quantity=2로 구매**하는 방식입니다(메인보드 슬롯이 1개뿐이면 quantity=1로 예외 처리). 결과에 `unit_price_krw`, `quantity` 필드가 명시되어 프론트엔드에 "개당 X원 × 2개"로 정확히 표시됩니다.

**모드별 목표 클럭**:
- 가성비(cost): DDR5는 5600MHz 이상 우선(없으면 규격 전체로 확대). DDR4는 규칙 대상 아님.
- 성능(perf): **6000~6400MHz 범위** 우선 → 없으면 6000MHz 이상 전체 → 그래도 없으면 전체로 폴백. (6400 초과 초고클럭은 안정성 우려로 일부러 제외)

```python
MIN_DDR5_SPEED_COST = 5600
MIN_DDR5_SPEED_PERF = 6000
```

### 2.5 쿨러

| 조건 | 근거 |
|---|---|
| `CPU.socket ∈ 쿨러.support_sockets` | 물리적 호환 |
| **i7/i9 중 K시리즈만** 무조건 수랭(라디에이터 390mm 이상) 강제 | `is_k_series()` 판별. K가 아니면(비K) 아래 수치 검증만 적용 |
| 그 외 전부(비K 포함): `(CPU.avg_power_w + GPU.avg_power_w) × 1.3 <= 쿨러.tdp_rating_w` | 공랭만 이 검증 대상(수랭은 TDP 데이터가 부실한 경우가 많아 면제) |
| RAM 히트싱크 간섭 | RAM 높이 > 40mm면, 공랭 중 `height_mm >= 155`("대장급")인 것 제외(경험적 근사치 — 정확한 "RAM 클리어런스" 컬럼은 없음) |

390mm 라디에이터 기준: 표준 360mm 라디에이터의 실제 물리 길이(팬 포함)가 약 390~400mm라는 실측 데이터로 정한 임계값입니다.

### 2.6 PSU

| 조건 | 근거 |
|---|---|
| **`(CPU.avg_power_w + GPU.avg_power_w) × 1.3 <= PSU.rated_w`** | 사용자 최종 결정 — 순간 피크(MTP) 대신 평균 소비전력 기준으로 통일 |
| CPU 등급별 최소 하한선(안전망) | avg_power_w 데이터가 없는 상품 대비: entry 400W / mainstream 500W / high 650W / flagship 750W. 계산값과 하한선 중 **더 큰 값**을 최종 요구치로 사용 |
| ATX3.0/3.1 강제 | GPU `tier_rank >= 9`(RTX4070Ti급 이상)면 `has_atx3_support(name)` — 상품명에 "ATX3.0/3.1" 또는 "12VHPWR"/"12V-2x6" 명시된 것만. 단순 "ATX 파워" 표기는 구형(ATX 2.x)으로 간주 |
| **80PLUS 인증 등급(모드별)** | 가성비: `BRONZE` 이상 / 성능: `GOLD` 이상. `meets_80plus_minimum(name, min_tier)`로 판정하며, **무인증 제품은 등급 요구가 있으면 항상 탈락** |
| 미니PC 배치 시 | `form_factor == "SFX"` |

**등급 서열**(`psu_rules.py`의 `_TIER_RANK`): STANDARD(0) < BRONZE(1) < SILVER(2) < GOLD(3) < PLATINUM(4) < TITANIUM(5). 상위 등급은 하위 요구조건도 자동으로 통과합니다.

### 2.7 케이스

| 조건 | 근거 |
|---|---|
| `mboard.form_factor ∈ case.support_form_factors` | 폼팩터 호환 |
| `GPU.length_mm + 20 <= case.max_vga_length_mm` | GPU가 있을 때만(문서작업처럼 GPU 없으면 생략) |
| PSU 폼팩터 호환 | `_psu_form_factor_matches()` — 케이스는 "표준-ATX"/"M-ATX(SFX)" 같은 다나와 원문 표기라 PSU 쪽 단순 표기("ATX"/"SFX")와 형식이 다름. 괄호 안 값 또는 하이픈 뒤 값으로 정규화해서 비교 |
| 공랭 쿨러 높이 | `cooler.height_mm <= case.max_cooler_height_mm`(공랭일 때만) |

---

## 3. 저장장치 (SSD/HDD)

STAGES와 독립적으로 `select_storage(ssd_gb_min, hdd_gb_min)`가 처리합니다.

| 항목 | 처리 방식 |
|---|---|
| 용량 | 다나와 가격 옵션명에서 파싱(`"1TB_980원/1GB"` 등) |
| HDD 벌크 상품 제외 | 옵션명의 배수 표기("2x12TB")가 있으면 서버·벌크용으로 보고 제외, 단품만 후보 |

**모드/용도별 요구 용량**은 `req.ssd_gb_min`/`hdd_gb_min`에서 결정되며, API 레이어(`parse_requirements_and_options`, `create_build`)에서 게임·용도·모드를 종합해 계산합니다 — 4절 참고.

---

## 4. 용도(usage_profiles)별 요구사항

`usage_profiles` 테이블의 각 행에 `required_cpu_tier`, `required_gpu_tier`, `required_ram_gb`, `required_ssd_gb`, `required_hdd_gb`, `requires_dgpu` 기본값이 있고, 방송/3D렌더링/개발은 `*_perf` 컬럼으로 성능 모드 전용 값을 따로 둡니다.

| 용도 | CPU(가성비→성능) | GPU(가성비→성능) | RAM | SSD(가성비→성능) | HDD | requires_dgpu |
|---|---|---|---|---|---|---|
| 문서작업 | tier 3 | tier 1(매칭 안 함) | 16GB | 512GB | - | **False**(단독 선택 시만) |
| 영상편집 | tier 9 | tier 5 | 32GB | 1TB | 2TB | True |
| 3D렌더링 | tier 3 → tier 24 | tier 3 → tier 9 | 64GB | 1TB → 2TB | 4TB | True |
| 방송/스트리밍 | tier 9 | tier 2 → tier 6 | 32GB | 1TB | - | True |
| 개발/컴파일 | tier 9 | tier 1 | 32GB | 1TB → 2TB | - | True |
| 게임 | 게임별 개별값(`game_requirements`) | 게임별 개별값 | 게임별 개별값 | **1TB → 2TB**(하한선) | **1TB**(하한선) | 항상 True |

**병합 규칙**: 게임/용도를 여러 개 동시에 선택하면 각 항목마다 **가장 높은 요구치**를 채택(`merge_requirements`). `requires_dgpu`는 예외적으로 "하나라도 필요하면 전체 필요"(any 로직) — 문서작업을 다른 것과 같이 고르면 GPU가 매칭됩니다.

**게임 SSD/HDD 하한선**: 가벼운 게임(롤/발로란트 등)은 `game_requirements.storage_gb` 자체가 작아서, 그대로 쓰면 비현실적으로 작은 SSD가 나옵니다 — 게임을 하나라도 선택하면 모드별 하한선(가성비 1TB, 성능 2TB, HDD는 모드 무관 1TB)을 무조건 보장합니다.

---

## 5. Gemini 최종 검수

각 부품 확정 단계마다 검수하던 방식(`review_partial`, 코드는 남아있음)에서 **완성된 견적 전체를 한 번만 검수**하는 방식(`review_final`)으로 전환했습니다(속도 개선 목적).

**검수 항목**: CPU-GPU 밸런스, 메인보드 VRM, RAM 규격, 쿨러 발열/스로틀링, PSU 인증·ATX3.0, 케이스 통풍/공간.

**문제 발견 시**: 문제 카테고리로 지목된 부품만 같은 호환 조건(다른 부품은 고정) 안에서 다음 후보로 교체. Gemini가 제안한 모델명과 최대한 가깝게 일치하는 상품을 `find_best_match()`(토큰 매칭)로 찾고, 없으면 다음 최저가 후보로 폴백. 예산을 초과하면 교체를 포기하고 원래 부품 유지.

**단계별 검수로 되돌리기**: `DOWNGRADE_ORDER` 옆의 `DOWNGRADE_REVIEW_ENABLED = False`를 `True`로 바꾸고, `search()` 호출의 `with_review=False`를 `True`로 바꾸면 원상복구됩니다.

---

## 6. 성능 모드(예산 맞추기)의 다운그레이드

1. 예산 무시하고 최대 스펙으로 먼저 구성(`search(mode="perf")`)
2. 예산 초과 시 `DOWNGRADE_ORDER = ["case", "psu", "cooler", "ram", "mboard", "gpu", "cpu"]` 순서로 하나씩 낮춤 — CPU/GPU는 최대한 유지, 나머지부터 희생
3. 각 다운그레이드 시도마다 `check_bottleneck()`(CPU-GPU 병목 재확인)을 거침 — GPU 없는 빌드는 이 체크 생략

---

## 7. 알려진 한계 / 근사치 (정확도 개선 여지)

| 항목 | 현재 상태 |
|---|---|
| 3D렌더링 CPU "6코어12스레드~8코어16스레드" 조건 | 코어/스레드 데이터가 매칭에 안 쓰여서 예시 모델명 기준 tier_rank로 근사 |
| RTX 4070 Ti SUPER | 등급표에 없는 모델이라 RTX4070Ti(tier 9)로 근사 |
| SSD DRAM 탑재/PCIe버전/NVMe·SATA 프로토콜 | 데이터 없음 — 용량만 반영, 나머지 조건 미구현 |
| 쿨러 "RAM 클리어런스" 정확한 물리 치수 | 컬럼 없음 — 경험적 임계값(40mm/155mm)으로 근사 |
| 케이스 라디에이터 지원 규격 상세(240/280/360, 상단/전면 구분) | 데이터 없음 |
| M.2 슬롯 정보(폼팩터/프로토콜/PCIe버전) 기반 SSD 매칭 | 미구현 — SSD는 지금 용량으로만 선택 |
| SATA 포트/커넥터 개수 기반 매칭 | 미구현 |
| GPU 코어/스레드, VRAM 용량, 보조전원 커넥터 | 크롤링만 되고 매칭 로직에서 미사용 |

---

## 8. 파일 구조 요약

| 파일 | 역할 |
|---|---|
| `core/algorithm.py` | 매칭 알고리즘 전체(STAGES, 백트래킹, 부품별 필터, 성능모드 다운그레이드) |
| `core/psu_rules.py` | PSU 관련 판별 함수(ATX3.0, 80PLUS 등급) — algorithm.py와 gemini_review.py 양쪽에서 공용으로 씀(순환참조 방지 목적으로 분리) |
| `core/gemini_review.py` | Gemini 최종 검수 프롬프트/호출 |
| `core/upgrade.py` | 견적 확정 후 CPU/GPU 업그레이드 기능 |
| `api/server.py` | Flask API — 게임/용도 요구사항 정규화·병합, 모드별 오버라이드 |
