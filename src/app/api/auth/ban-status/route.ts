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

    let userId = data.user?.id ?? null;
    const authErrorCode = extractAuthErrorCode(error);

    if (!userId && authErrorCode === "user_banned") {
      userId = extractUserIdFromAccessToken(token);
    }

    if (!userId || (error && authErrorCode !== "user_banned")) {
      return unauthorized();
    }

    const supabase = createServiceSupabaseClient();
    const { data: userResult, error: userError } = await supabase.auth.admin.getUserById(userId);
    if (userError || !userResult.user) {
      return NextResponse.json(
        { ok: false, error: userError?.message || "Failed to load user status." },
        { status: 500 },
      );
    }

    const bannedUntil = extractBannedUntil(userResult.user);
    if (!bannedUntil && authErrorCode !== "user_banned") {
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
    const message = error instanceof Error ? error.message : "Unknown server error";
    console.error("[ban-status GET]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
