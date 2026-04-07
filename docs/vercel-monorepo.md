# Vercel 배포 — 모노레포 (`apps/web`)

JobStack 저장소는 pnpm + Turborepo 모노레포이다. 웹앱은 `apps/web`의 Next.js(App Router)이다.

## Vercel 프로젝트 설정

1. GitHub 저장소를 Vercel에 연결한다.
2. **Root Directory**: `apps/web`
3. **Install Command** (저장소 루트의 lockfile 사용):

   ```bash
   cd ../.. && pnpm install --frozen-lockfile
   ```

4. **Build Command**:

   ```bash
   cd ../.. && pnpm exec turbo run build --filter=@jobstack/web
   ```

5. **Output**: Next.js 기본 (`apps/web` 기준 `.next`).

환경 변수가 필요하면 Vercel 대시보드에서 `apps/web` 또는 프로젝트 루트에 맞게 설정한다.

## 로컬 확인

```bash
pnpm install
pnpm exec turbo run dev --filter=@jobstack/web
```

브라우저에서 `http://localhost:3000` — 랜딩 200 OK.
