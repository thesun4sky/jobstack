import { auth } from "@/auth";
import { getEffectivePlan } from "@/lib/billing/plan";
import { NextResponse } from "next/server";

export async function GET() {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const billing = await getEffectivePlan(session.user.id);

  return NextResponse.json({
    user: {
      id: session.user.id,
      email: session.user.email,
      name: session.user.name,
    },
    billing: {
      planKey: billing.planKey,
      subscriptionStatus: billing.subscriptionStatus,
      hasSubscriptionRow: billing.hasSubscriptionRow,
      paperclipAgentId: billing.paperclipAgentId,
      paperclipProvisionError: billing.paperclipProvisionError,
    },
  });
}
