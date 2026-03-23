import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const supabase = createServerSupabaseClient();
  const { data: { user } } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const { data: rooms } = await supabase
    .from("chat_rooms")
    .select(`
      id, name, type, created_at,
      chat_members(user_id, user_profiles:user_id(username, avatar_url))
    `)
    .or(`type.eq.global,id.in.(select room_id from chat_members where user_id eq ${user.id})`);

  const globalRoom = { id: "00000000-0000-0000-0000-000000000001", name: "Global Chat", type: "global" };

  return NextResponse.json({
    ok: true,
    rooms: rooms || [globalRoom],
    global_room_id: "00000000-0000-0000-0000-000000000001",
  });
}
