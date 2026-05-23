import { MarketingFooter } from "@/components/marketing-footer";
import { MarketingHeader } from "@/components/marketing-header";
import { signIn } from "@/auth";
import Link from "next/link";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ callbackUrl?: string }>;
}) {
  const { callbackUrl } = await searchParams;
  const emailEnabled =
    Boolean(process.env.EMAIL_SERVER) && Boolean(process.env.EMAIL_FROM);
  const googleEnabled =
    Boolean(process.env.GOOGLE_CLIENT_ID) &&
    Boolean(process.env.GOOGLE_CLIENT_SECRET);

  return (
    <div className="min-h-screen bg-[var(--background)]">
      <MarketingHeader />
      <main className="mx-auto flex min-h-[70vh] max-w-lg flex-col justify-center px-4 py-16 sm:px-6">
        <div className="rounded-3xl border border-[var(--js-border)] bg-[var(--js-surface)] p-8 shadow-lg">
          <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
            계정
          </p>
          <h1 className="mt-2 text-2xl font-semibold text-[var(--js-ink)]">
            로그인
          </h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--js-muted)]">
            Google OAuth 및(또는) 이메일 매직 링크 — 배포 환경 변수는{" "}
            <code className="font-mono text-xs">.env.example</code> 참고
          </p>
          <div className="mt-8 flex flex-col gap-3">
            {googleEnabled ? (
              <form
                action={async () => {
                  "use server";
                  await signIn("google", {
                    redirectTo: callbackUrl ?? "/dashboard",
                  });
                }}
              >
                <button
                  type="submit"
                  className="w-full rounded-xl bg-[var(--js-ink)] py-3 text-sm font-semibold text-[var(--js-surface)] transition-opacity hover:opacity-90"
                >
                  Google로 계속
                </button>
              </form>
            ) : null}
            {emailEnabled ? (
              <form
                action={async (formData: FormData) => {
                  "use server";
                  const email = String(formData.get("email") ?? "");
                  await signIn("nodemailer", {
                    email,
                    redirectTo: callbackUrl ?? "/dashboard",
                  });
                }}
                className="flex flex-col gap-2"
              >
                <input
                  name="email"
                  type="email"
                  required
                  placeholder="you@example.com"
                  className="rounded-xl border border-[var(--js-border)] bg-[var(--js-elevated)] px-3 py-2.5 text-sm outline-none focus:border-[color-mix(in_oklab,var(--js-accent)_50%,var(--js-border))]"
                />
                <button
                  type="submit"
                  className="rounded-xl border border-[var(--js-border)] py-3 text-sm font-semibold text-[var(--js-ink)] hover:bg-[var(--js-elevated)]"
                >
                  이메일로 매직 링크 받기
                </button>
              </form>
            ) : null}
            {!googleEnabled && !emailEnabled ? (
              <p className="rounded-xl bg-[var(--js-elevated)] px-3 py-3 text-sm text-[var(--js-muted)]">
                OAuth·이메일 로그인을 쓰려면{" "}
                <code className="font-mono text-xs">GOOGLE_CLIENT_ID</code>/
                <code className="font-mono text-xs">SECRET</code> 또는{" "}
                <code className="font-mono text-xs">EMAIL_SERVER</code>/
                <code className="font-mono text-xs">EMAIL_FROM</code>을 설정하세요.
              </p>
            ) : null}
          </div>
          <p className="mt-6 text-center text-sm text-[var(--js-muted)]">
            계정이 없나요?{" "}
            <Link
              href="/signup"
              className="font-semibold text-[var(--js-accent-strong)] hover:underline"
            >
              회원가입
            </Link>
          </p>
        </div>
      </main>
      <MarketingFooter />
    </div>
  );
}
