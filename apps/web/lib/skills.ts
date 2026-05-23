export type SkillTier = 1 | 2 | 3 | 4;

export type SkillDef = {
  slug: string;
  cliPath: string;
  tier: SkillTier;
  title: string;
  short: string;
  /** 한 줄 설명 — 스킬 실행 화면 상단 */
  pitch: string;
  /** 모의 실행 단계 */
  phases: { label: string; detail: string }[];
};

export const SKILLS: SkillDef[] = [
  {
    slug: "auto",
    cliPath: "/auto",
    tier: 1,
    title: "Auto",
    short: "전체 오케스트레이션",
    pitch: "목표·일정·우선순위를 잡고 다음 액션을 자동 제안합니다.",
    phases: [
      { label: "컨텍스트 수집", detail: "지원 분야·기간·제약을 정리합니다." },
      { label: "워크플로 합성", detail: "13개 스킬 중 이번 주에 돌릴 순서를 제안합니다." },
      { label: "피드백 루프", detail: "실행 로그를 바탕으로 플랜을 다시 조정합니다." },
    ],
  },
  {
    slug: "strategy",
    cliPath: "/strategy",
    tier: 1,
    title: "Strategy",
    short: "전략·로드맵",
    pitch: "기업·직무에 맞는 준비 순서와 마일스톤을 설계합니다.",
    phases: [
      { label: "가설 정리", detail: "강점·약점·차별 포인트를 문장으로 고정합니다." },
      { label: "로드맵", detail: "주차별 목표와 산출물을 배치합니다." },
      { label: "검증 질문", detail: "스스로 점검할 체크리스트를 만듭니다." },
    ],
  },
  {
    slug: "tracker",
    cliPath: "/tracker",
    tier: 1,
    title: "Tracker",
    short: "지원·일정 트래킹",
    pitch: "지원 현황과 후속 액션을 한 화면에서 추적합니다.",
    phases: [
      { label: "파이프라인", detail: "서류·면접 단계별 상태를 기록합니다." },
      { label: "리마인더", detail: "후속 메일·준비 마감을 상기합니다." },
      { label: "리포트", detail: "주간 요약으로 병목을 드러냅니다." },
    ],
  },
  {
    slug: "company-research",
    cliPath: "/company-research",
    tier: 2,
    title: "Company research",
    short: "기업 리서치",
    pitch: "사업·제품·팀 문화 관점에서 면접에 쓸 인사이트를 뽑습니다.",
    phases: [
      { label: "정보 스캔", detail: "공시·블로그·채용 공고를 훑습니다." },
      { label: "질문 후보", detail: "면접관이 물어볼 만한 각도를 정리합니다." },
      { label: "한 장 요약", detail: "지원 동기 문장과 연결합니다." },
    ],
  },
  {
    slug: "job-search",
    cliPath: "/job-search",
    tier: 2,
    title: "Job search",
    short: "채용 탐색",
    pitch: "조건에 맞는 공고를 모으고 우선순위를 매깁니다.",
    phases: [
      { label: "필터", detail: "역할·스택·근무 형태 기준을 고정합니다." },
      { label: "클러스터링", detail: "유사 공고를 묶어 중복 지원을 줄입니다." },
      { label: "다음 액션", detail: "지원/보류/제외 결정을 기록합니다." },
    ],
  },
  {
    slug: "ncs",
    cliPath: "/ncs",
    tier: 2,
    title: "NCS",
    short: "직무·역량 정렬",
    pitch: "NCS 기준과 경험을 매핑해 서류·면접 언어를 맞춥니다.",
    phases: [
      { label: "역량 추출", detail: "요구 역량 키워드를 뽑습니다." },
      { label: "경험 매칭", detail: "프로젝트 사례와 연결합니다." },
      { label: "문장 변환", detail: "역량형 서술 초안을 만듭니다." },
    ],
  },
  {
    slug: "salary",
    cliPath: "/salary",
    tier: 3,
    title: "Salary",
    short: "연봉·협상",
    pitch: "레퍼런스와 협상 시나리오를 준비합니다.",
    phases: [
      { label: "밴드 추정", detail: "공개 데이터·주변 레퍼런스를 참고합니다." },
      { label: "협상 목표", detail: "최소·목표·이상선을 정합니다." },
      { label: "스크립트", detail: "제안·반박·마무리 멘트를 짭니다." },
    ],
  },
  {
    slug: "portfolio",
    cliPath: "/portfolio",
    tier: 3,
    title: "Portfolio",
    short: "포트폴리오",
    pitch: "프로젝트 스토리라인과 증빙 구성을 다듬습니다.",
    phases: [
      { label: "선별", detail: "대표 프로젝트 2~3개를 고릅니다." },
      { label: "임팩트", detail: "수치·역할·의사결정을 강조합니다." },
      { label: "발표 대본", detail: "3분 설명용 흐름을 만듭니다." },
    ],
  },
  {
    slug: "retro",
    cliPath: "/retro",
    tier: 3,
    title: "Retro",
    short: "회고",
    pitch: "주간·전형별 회고로 학습 속도를 높입니다.",
    phases: [
      { label: "사실", detail: "무슨 일이 있었는지 사건 중심으로 적습니다." },
      { label: "해석", detail: "패턴·감정·가설을 분리합니다." },
      { label: "실험", detail: "다음 주 행동 한 가지를 고릅니다." },
    ],
  },
  {
    slug: "resume",
    cliPath: "/resume",
    tier: 3,
    title: "Resume",
    short: "이력서",
    pitch: "직무 키워드와 성과 문장을 정렬합니다.",
    phases: [
      { label: "골격", detail: "경력 순서·강조 섹션을 잡습니다." },
      { label: "성과 문장", detail: "행동·수치·결과 형태로 다듬습니다." },
      { label: "ATS 점검", detail: "중복·빈 키워드를 점검합니다." },
    ],
  },
  {
    slug: "cover-letter",
    cliPath: "/cover-letter",
    tier: 4,
    title: "Cover letter",
    short: "자기소개서",
    pitch: "기업별 논리와 근거를 한글로 정교하게 맞춥니다.",
    phases: [
      { label: "질문 해부", detail: "문항 의도와 평가 기준을 분해합니다." },
      { label: "초안", detail: "사실·해석·의도를 분리해 씁니다." },
      { label: "첨삭", detail: "톤·중복·근거를 압축합니다." },
    ],
  },
  {
    slug: "mock-interview",
    cliPath: "/mock-interview",
    tier: 4,
    title: "Mock interview",
    short: "모의면접",
    pitch: "질문 은행·꼬리질문·타이머로 실전 감각을 올립니다.",
    phases: [
      { label: "시나리오", detail: "기술·인성·역량 유형 비율을 정합니다." },
      { label: "라운드", detail: "답변 녹음/기록 후 피드백을 받습니다." },
      { label: "보완", detail: "다음 라운드 집중 포인트를 고릅니다." },
    ],
  },
  {
    slug: "review",
    cliPath: "/review",
    tier: 4,
    title: "Review",
    short: "통합 점검",
    pitch: "서류·면접·스토리 일관성을 한 번에 검증합니다.",
    phases: [
      { label: "크로스체크", detail: "이력서·자소서·포폴의 모순을 찾습니다." },
      { label: "리스크", detail: "면접관이 파고들 만한 구멍을 표시합니다." },
      { label: "최종 플랜", detail: "우선 수정 순서를 제안합니다." },
    ],
  },
];

export function getSkill(slug: string): SkillDef | undefined {
  return SKILLS.find((s) => s.slug === slug);
}

export function skillsByTier(tier: SkillTier): SkillDef[] {
  return SKILLS.filter((s) => s.tier === tier);
}
