import { NextRequest, NextResponse } from "next/server";
import {
  extractAuthErrorCode,
  extractBannedUntil,
  extractUserIdFromAccessToken,
  isPermanentBan,
  isRecord,
} from "@/lib/ban";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";

type BanLogRow = {
  details: Record<string, unknown> | null;
};

function unauthorized() {
  return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
}

export async function GET(req: NextRequest) {
  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) return unauthorized();

    const token = stripBearer(authHeader);
    if (!token) return unauthorized();

    const anonClient = createAnonServerClient();
    const { data, error } = await anonClient.auth.getUser(token);

    // Fix N-6: Require valid session - don't extract userId from expired JWT
    if (error || !data.user) {
      return unauthorized();
    }

    const userId = data.user.id;

    const supabase = createServiceSupabaseClient();
    const { data: userResult, error: userError } = await supabase.auth.admin.getUserById(userId);
    if (userError || !userResult.user) {
      return NextResponse.json(
        { ok: false, error: userError?.message || "Failed to load user status." },
        { status: 500 },
      );
    }

    const bannedUntil = extractBannedUntil(userResult.user);
    if (!bannedUntil) {
      return NextResponse.json({ ok: true, banned: false });
    }

    let reason: string | undefined;
    const { data: logs } = await supabase
      .from("admin_logs")
      .select("details")
      .eq("action", "ban_user")
      .eq("target_user_id", userId)
      .order("created_at", { ascending: false })
      .limit(20);

    for (const log of (logs || []) as BanLogRow[]) {
      const details = isRecord(log.details) ? log.details : null;
      if (!details || details.source !== "admin_console") continue;
      if (details.banned_until !== bannedUntil) continue;
      if (typeof details.reason === "string" && details.reason.trim()) {
        reason = details.reason.trim();
      }
      break;
    }

    return NextResponse.json({
      ok: true,
      banned: true,
      bannedUntil: bannedUntil ?? null,
      isPermanent: isPermanentBan(bannedUntil),
      ...(reason ? { reason } : {}),
    });
  } catch (error) {
    console.error("[ban-status GET]", error);
    return NextResponse.json({ ok: false, error: "Failed to check ban status." }, { status: 500 });
  }
}
