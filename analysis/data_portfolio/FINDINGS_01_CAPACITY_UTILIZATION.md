# Finding 01 — Recorded teaching-capacity utilization

Snapshot date: 2026-09-25  
Analysis window: **2026-08-24 ~ 2026-09-20**  
Timezone: KST

## Question
**기록된 교사 근무 가능시간과 실제 수업 배정 사이에 요일별 불균형이 있는가?**

이 질문은 교사 개인의 성과를 평가하려는 것이 아니라, 서비스에서 제공하는 **명목상 예약 가능 공급(capacity)** 이 실제 수업으로 얼마나 사용되는지 보는 운영 지표다.

## Why the window starts on 2026-08-24
`private.teacher_work_hour_versions`는 과거 근무시간 이력을 저장하지만, 현재 DB에서 2026-08-24 이전 구간은 version coverage가 불완전하다.

따라서 과거 lesson 전체를 현재 work-hours와 단순 비교하면 잘못된 utilization이 만들어질 수 있다.

2026-08-24 ~ 2026-09-20 lesson 283건 중:
- work-hour version이 존재하는 lesson: **246건**
- coverage: **86.93%**
- duration 기준 coverage도 **86.93%**

분석 분모/분자는 이 covered cohort로 제한했다.

## Metric definition

### Scheduled utilization
```text
scheduled lesson minutes / recorded work-hour capacity minutes
```

### Booked utilization
```text
(scheduled + canceled lesson minutes) / recorded work-hour capacity minutes
```

취소가 없었다면 어느 정도까지 슬롯이 이미 배정되어 있었는지를 보기 위해 두 지표를 분리했다.

## Result

Covered cohort:
- recorded capacity: **192.5h**
- scheduled lesson time: **76.75h**
- canceled lesson time: **4.75h**
- scheduled utilization: **39.87%**
- booked utilization: **42.34%**

즉, 이 4주 구간에서는 취소 때문에 사라진 예약시간이 utilization을 약 **2.47%p** 낮췄다.

반대로 기록된 capacity의 절반 이상은 **취소 이전에도 예약되지 않은 상태**였다.

### By weekday

| Day | Capacity | Scheduled | Canceled | Scheduled util. | Booked util. |
|---|---:|---:|---:|---:|---:|
| Mon | 24.0h | 11.5h | 0.5h | 47.92% | 50.00% |
| Tue | 33.5h | 11.25h | 0.25h | 33.58% | 34.33% |
| Wed | 18.0h | 8.75h | 0.75h | 48.61% | 52.78% |
| Thu | 48.0h | 16.5h | 1.75h | 34.38% | 38.02% |
| Fri | 23.5h | 14.5h | 0.5h | **61.70%** | **63.83%** |
| Sat | 45.5h | 14.25h | 1.0h | **31.32%** | **33.52%** |

## Initial interpretation
이 기간에는 **금요일의 recorded capacity 이용률이 가장 높고**, 화·목·토요일은 상대적으로 낮았다.

특히:
- Fri scheduled utilization: **61.70%**
- Tue: **33.58%**
- Thu: **34.38%**
- Sat: **31.32%**

따라서 “취소율을 낮추는 것”만으로 전체 capacity 활용 문제를 설명하기는 어렵다.

### Candidate service/operation action
신규 학생 배정 또는 자율 예약 슬롯 노출 시:
1. 현재 utilization이 높은 요일의 남은 capacity를 먼저 확인하고,
2. 낮은 utilization 요일에는 신규 등록 시 선택 가능한 시간대를 더 명확히 노출하거나,
3. 실제 수요가 지속적으로 낮다면 work-hour supply 자체를 재검토한다.

## What this does NOT prove
- 교사의 생산성/성과를 의미하지 않는다.
- 예약되지 않은 시간이 “낭비”였다고 단정하지 않는다.
- 4주 데이터만으로 계절성이나 장기 수요를 확정하지 않는다.
- version coverage가 없는 lesson을 제외했기 때문에 전체 학원의 절대 utilization과 동일하지 않다.

## Next validation
- [ ] 같은 metric을 8~12주 누적할 수 있을 때 재계산
- [ ] teacher별 값은 외부 포트폴리오에 공개하지 않고 내부 진단에만 사용
- [ ] 시간대(14/15/16/17/18/19시)별 capacity utilization 분석
- [ ] 신규 등록 시 선택 요일과 utilization의 관계 확인
- [ ] 운영 변경 후 4주 전/후 비교

## Portfolio takeaway
단순히 “수업 255건”을 집계하는 대신,
**신뢰 가능한 근무시간 history 범위를 먼저 확인하고 → covered cohort를 정의하고 → capacity 대비 실제 예약을 비교해 → 어떤 운영 액션을 검증할지 제안**한 사례다.
