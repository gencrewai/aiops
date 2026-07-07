# aiops (CLI 상태 바) — 개선 계획 v1 (오피스 정비 패스)

> 작성: 2026-07-06 · 상위: keystone-hub `docs/analysis/2026-07-06-llm-work-quality-master-plan.md` (PR #221)
> 성격: 마스터 플랜 방안 C(AI 오피스) C-1 인벤토리 감사의 프로젝트 실행분. **실행은 항목별 사람 승인.**

## 오피스 좌표
- 부서: **인프라실(계기판)** — Claude Code·Codex CLI 상태 바의 정본. keystone-hub가 `claude-statusline.sh/.ps1`로 재vendoring해 전 머신 배포
- 등급: 유지보수(마지막 커밋 2026-06-13) · 원격 `gencrewai/aiops` — **codecleanup-dev가 아닌 외부 org** (권한·병합 가능 여부 이 패스에서 실측)

## 현황 [검증됨: 프로브]
- main 체크아웃, dirty 1건. 최근: model-profile-switcher 병합(#3), effort/account 표시 feature 브랜치들 존재
- 동기화 계약 [메모리]: 기능 변경은 aiops main 병합 → keystone이 재vendoring → 각 머신 apply 순으로만 전 머신 반영. aiops-models 프로필은 keystone 비관리

## 마스터 플랜 축 적용
| 축 | 이 repo에서의 의미 |
|---|---|
| 커널(방안 A) | 소비자 아님 (셸 스크립트 프로젝트) — 단 상태 바는 **현재 세션의 실모델을 아는 유일한 표면**이라 H-3(실모델 판독) 검증의 참고 구현 |
| 모델 배정(C-3) | Fable 5 퇴역(7/7) 후 모델 표기·프로필 스위처가 opus-4-8/sonnet-5 체계를 올바로 표시하는지 확인 대상 |
| 측정(방안 D) | 해당 없음 |

## 개선 항목
| # | 항목 | 완료기준 | risk |
|---|---|---|---|
| 1 | 퇴역 후 표기 점검 — fable-5 항목 처리·fallback 표시 확인 | 7/8 이후 실세션 스크린샷 1장 | R0 |
| 2 | dirty 1건 처분 + 미병합 feature 브랜치 2종(effort-codex·account) 판정 | 병합/폐기 기록 | R1 |
| 3 | 동기화 계약 repo 내 문서화 — "aiops 변경이 전 머신에 반영되는 경로"를 README에 1절 (현재는 keystone 메모리에만 존재) | README 반영 | R0 |
| 4 | H-3 참고 구현 노트 — statusline이 실모델을 얻는 입력 스키마를 keystone H-3 검증에 인용 | 마스터 플랜 H-3에 참조 추가 | R0 |

## 스코프 컷
기능 추가(새 위젯) 없음. org 이전(gencrewai→개인) 논의는 사람 판단 — 이 패스는 실측 결과만 기록.
