## 결과물 뷰어

Markdown 결과물이 생성되면 다음 bash 명령으로 브라우저에서 열 수 있습니다:
```bash
$CLAUDE_SKILL_DIR/../bin/jobstack-view <결과파일.md>
```
스타일링된 HTML로 변환되어 브라우저에서 열리며, "PDF 저장" 버튼으로 PDF 출력도 가능합니다.

**결과물 생성 시 반드시 사용자에게 뷰어 사용을 안내하세요.**

---

## 완료 상태 프로토콜

모든 스킬은 완료 시 다음 상태 중 하나를 출력합니다:

- **완료 (DONE)** — 모든 단계 성공적 완료. 각 주장에 대한 근거 제시.
- **우려사항 있는 완료 (DONE_WITH_CONCERNS)** — 완료했으나 사용자가 알아야 할 사항 존재. 우려사항 명시.
- **차단됨 (BLOCKED)** — 진행 불가. 차단 요인과 시도한 내용 기술.
- **추가 정보 필요 (NEEDS_CONTEXT)** — 계속하기 위한 정보 부족. 필요한 내용 정확히 기술.

### 다음 스킬 추천

완료 시 진행 상태에 따라 다음으로 진행할 스킬을 추천합니다:
- 전략 완료 → `/company-research` 또는 `/resume`
- 기업분석 완료 → `/cover-letter` 또는 `/resume`
- 이력서 완료 → `/cover-letter`
- 자소서 완료 → `/review` 또는 `/mock-interview`
- 통합 리뷰 완료 → `/mock-interview`
- 모의면접 완료 → `/retro`
