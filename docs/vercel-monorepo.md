# Vercel 배포 — 모노레포 (`apps/web`)

JobStack 저장소는 pnpm + Turborepo 모노레포이다. 웹앱은 `apps/web`의 Next.js(App Router)이다.

## Vercel 프로젝트 설정

1. GitHub 저장소를 Vercel에 연결한다.
2. **Root Directory**: `apps/web`
3. **Install / Build**: `apps/web/vercel.json`에 정의되어 있다. 대시보드에서 동일 값을 수동으로 넣을 필요는 없다(파일이 우선한다).

   - Install: `cd ../.. && pnpm install --frozen-lockfile`
   - Build: `cd ../.. && pnpm exec turbo run build --filter=@jobstack/web`

4. **Output**: Next.js 기본 (`apps/web` 기준 `.next`).

### 환경 변수 (Preview / Production)

저장소 루트 [`.env.example`](../.env.example)를 기준으로 Vercel **Project → Settings → Environment Variables**에 등록한다.

| 변수 | 필수 | 메모 |
| --- | --- | --- |
| `DATABASE_URL` | 예 | Neon / Supabase 등 서버리스 Postgres. 로컬 Docker URL은 배포에서 사용 불가. |
| `AUTH_SECRET` | 예 | `openssl rand -base64 32` 로 생성. |
| `AUTH_URL` | 예 | 배포 URL(예: `https://xxx.vercel.app`). Preview마다 URL이 바뀌면 Preview용으로 별도 값 또는 Vercel의 `VERCEL_URL` 기반 설정이 필요할 수 있다. |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | 로그인 플로우 | Google Cloud 콘솔에 **승인된 리디렉션 URI**에 `https://<배포도메인>/api/auth/callback/google` 추가. |
| `EMAIL_SERVER` / `EMAIL_FROM` | 선택 | 매직 링크용. |
| `PORTONE_*` | 결제 연동 시 | 해당 기능 사용 시에만. |

Preview 배포마다 호스트명이 달라질 수 있으므로, OAuth 리디렉션은 와일드카드(허용 시) 또는 배포별 URI 추가가 필요할 수 있다.

## 배포 후 스모크 (공개 URL 기준)

`BASE`를 실제 `https://….vercel.app` 로 바꾼다.

```bash
BASE="https://YOUR_DEPLOYMENT.vercel.app"
for path in "" "/login" "/skills"; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$path")
  echo "$path -> HTTP $code"
done
```

200이 아니면 Vercel 로그·환경 변수·DB 연결을 확인한다.

## CLI로 연결 (선택)

로컬에서 `npx vercel login` 후 저장소 루트 또는 `apps/web`에서 `vercel link` 로 프로젝트를 묶을 수 있다. CI/에이전트 환경에서는 비대화형 로그인 제약이 있으므로 **Git 연동 + 대시보드**가 일반적이다.

## 로컬 확인

```bash
pnpm install
pnpm exec turbo run dev --filter=@jobstack/web
```

브라우저에서 `http://localhost:3000` — 랜딩 200 OK.
