import type { Metadata } from "next";
import { JobClawFooter } from "@/components/jobclaw-footer";
import { JobClawHeader } from "@/components/jobclaw-header";

export const metadata: Metadata = {
  title: {
    default: "JobClaw — 텔레그램 연동 취업 에이전트",
    template: "%s | JobClaw",
  },
  description:
    "구독형 AI 에이전트. Claude 기반 JobStack 스킬을 텔레그램에서 사용합니다.",
};

export default function JobClawLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-50 antialiased">
      <JobClawHeader />
      {children}
      <JobClawFooter />
    </div>
  );
}
