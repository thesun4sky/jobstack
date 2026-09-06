# 프로필 자동 업데이트 세부
resume 스킬 SKILL.md Phase 9에서, 프로필 저장 항목을 채울 때 Read 한다.

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
# 프로필 업데이트 (이력서 작성 시)
PROFILE="$_JS_STATE/profiles/default.yaml"
# 수집된 정보를 YAML 형태로 저장/업데이트
```

저장 항목:
- `name`, `email`, `phone`
- `education[]` — 학교, 전공, 졸업년도
- `experience[]` — 회사, 직무, 기간, 성과
- `skills[]` — 기술스택, 숙련도
- `certifications[]` — 자격증, 취득일
- `target_role` — 목표 직무
- `target_companies[]` — 목표 기업 리스트
- `resume_versions[]` — 공고 단위 변형본 관리: `회사명`, `공고 키워드`, `매칭률`, `파일 경로`. 원본 이력서는 보존하고, 공고별로 파생된 버전만 이 배열에 기록합니다.
