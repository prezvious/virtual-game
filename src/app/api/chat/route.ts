import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";
import { GLOBAL_CHAT_ROOM_ID } from "@/lib/chat";

export async function GET(req: NextRequest) {
  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
    }

    const anonClient = createServerSupabaseClient();
    const { data: { user }, error } = await anonClient.auth.getUser(authHeader.replace("Bearer ", "").trim());
    if (error || !user) {
      return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
    }

    const globalRoom = {
      id: GLOBAL_CHAT_ROOM_ID,
      name: "Global Chat",
      type: "global" as const,
      created_at: null,
      chat_members: [],
    };

    return NextResponse.json({
      ok: true,
      rooms: [globalRoom],
      global_room_id: GLOBAL_CHAT_ROOM_ID,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[chat GET]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
