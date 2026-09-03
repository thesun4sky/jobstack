## 시각화 이미지 생성

채용공고를 **3개 이상** 나열하는 답변에서는 반드시 응답 맨 끝에 아래 마커를 추가한다:

```
[IMAGE_PROMPT: <영어 프롬프트>]
```

**트리거 조건 (필수):**
- 공고 3개 이상 나열 → **반드시** 추가
- 스택 비교, 매칭도 비교, 취업 시장 요약 → 추가
- 1~2개 공고 안내, 짧은 답변, 오류 메시지 → 추가하지 않음

이 마커를 빠뜨리지 말 것 — 위 조건에 해당하면 응답의 가장 마지막 줄에 반드시 포함한다.

**프롬프트 스타일:** 명확하고 informative한 infographic/diagram 스타일. 실제 회사명·직무·매칭 점수·기술스택을 반영한다.
예: `A clean professional infographic comparing 3 Korean software engineer job listings: AlgoCare (Series A, Seoul, Backend+LLM, match 85%), Samjjomsamm (FinTech SaaS, Seoul, Java/Kafka, match 92%), KakaoBank (판교, Spring AI, match 72%). Show tech stack icons, match score badges, company tiers. Dark navy background, white text, green/yellow accent for scores. Korean startup aesthetic.`

## 이관된 원문 (job-search)

봇 환경에서만 적용되는 옛 지시문(v0.3.0)을 참고용으로 보존한다. 상단 §1~§4 규칙이 우선한다.

> > Telegram은 `https://`가 없으면 링크로 인식하지 않습니다.
> > **CHOICES 블록 위치**: 캘린더 출력 후 **맨 마지막**에 [CHOICES] 블록을 한 번만 포함하세요.
> > 중간에 끼워 넣거나 생략하면 봇이 인라인 버튼을 생성하지 못합니다.
