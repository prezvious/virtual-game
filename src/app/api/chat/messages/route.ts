import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient, createServiceSupabaseClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";
import {
  CHAT_HISTORY_RETENTION_HOURS,
  CHAT_MESSAGE_MAX_LENGTH,
  GLOBAL_CHAT_ROOM_ID,
} from "@/lib/chat";

type ChatRoomRow = {
  id: string;
  type: string;
};

type MessageRow = {
  id: string;
  room_id: string;
  content: string;
  created_at: string;
  sender_id: string;
};

type UserProfileRow = {
  user_id: string;
  username: string | null;
  avatar_url: string | null;
};

type HydratedMessage = {
  id: string;
  content: string;
  created_at: string;
  sender_id: string;
  user_profiles: {
    username: string | null;
    avatar_url: string | null;
  } | null;
};

type RoomAccessResult =
  | { ok: true; room: ChatRoomRow }
  | { ok: false; error: string; status: number };

function getServiceRoleKey() {
  return process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_FUNCTIONS_KEY || "";
}

function getErrorMessage(error: unknown, fallback: string) {
  if (error && typeof error === "object" && "message" in error && typeof error.message === "string") {
    return error.message;
  }

  return fallback;
}

function logSupabaseError(context: string, error: unknown) {
  if (error && typeof error === "object") {
    const supabaseError = error as {
      code?: string | null;
      details?: string | null;
      hint?: string | null;
      message?: string | null;
    };

    console.error(context, {
      code: supabaseError.code ?? null,
      details: supabaseError.details ?? null,
      hint: supabaseError.hint ?? null,
      message: supabaseError.message ?? "Unknown Supabase error",
    });
    return;
  }

  console.error(context, error);
}

async function getUserFromRequest(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return { user: null, tokenProvided: false };
  }

  const anonClient = createServerSupabaseClient();
  const token = authHeader.replace("Bearer ", "").trim();
  const { data, error } = await anonClient.auth.getUser(token);
  if (error) {
    logSupabaseError("[chat/messages auth]", error);
    return { user: null, tokenProvided: true };
  }

  return { user: data.user ?? null, tokenProvided: true };
}

async function ensureRoomAccess(roomId: string, userId?: string): Promise<RoomAccessResult> {
  const supabase = createServiceSupabaseClient();
  const { data: room, error: roomError } = await supabase
    .from("chat_rooms")
    .select("id, type")
    .eq("id", roomId)
    .maybeSingle<ChatRoomRow>();

  if (roomError) {
    logSupabaseError("[chat/messages room]", roomError);
    return {
      ok: false,
      error: roomError.code === "22P02" ? "Invalid chat room." : "Unable to load the chat room right now.",
      status: roomError.code === "22P02" ? 400 : 500,
    };
  }

  if (!room) {
    return { ok: false, error: "Chat room not found.", status: 404 };
  }

  if (room.type === "global") {
    return { ok: true, room };
  }

  if (!userId) {
    return { ok: false, error: "Unauthorized.", status: 401 };
  }

  const { data: member, error: memberError } = await supabase
    .from("chat_members")
    .select("room_id")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle<{ room_id: string }>();

  if (memberError) {
    logSupabaseError("[chat/messages membership]", memberError);
    return { ok: false, error: "Unable to verify chat access right now.", status: 500 };
  }

  if (!member) {
    return { ok: false, error: "You do not have access to this chat room.", status: 403 };
  }

  return { ok: true, room };
}

async function hydrateMessages(messageRows: MessageRow[]) {
  if (messageRows.length === 0) {
    return [] as HydratedMessage[];
  }

  const supabase = createServiceSupabaseClient();
  const senderIds = [...new Set(messageRows.map((message) => message.sender_id))];
  const { data: profileRows, error: profileError } = await supabase
    .from("user_profiles")
    .select("user_id, username, avatar_url")
    .in("user_id", senderIds)
    .returns<UserProfileRow[]>();

  if (profileError) {
    throw profileError;
  }

  const profilesByUserId = new Map(
    (profileRows || []).map((profile) => [
      profile.user_id,
      {
        username: profile.username,
        avatar_url: profile.avatar_url,
      },
    ]),
  );

  return messageRows.map<HydratedMessage>((message) => ({
    id: message.id,
    content: message.content,
    created_at: message.created_at,
    sender_id: message.sender_id,
    user_profiles: profilesByUserId.get(message.sender_id) ?? null,
  }));
}

export async function GET(req: NextRequest) {
  try {
    const roomId = req.nextUrl.searchParams.get("room_id") || GLOBAL_CHAT_ROOM_ID;
    const requestedLimit = Number(req.nextUrl.searchParams.get("limit"));
    const limit = Number.isFinite(requestedLimit) ? Math.max(1, Math.min(50, requestedLimit)) : 50;
    const serviceKey = getServiceRoleKey();

    if (!serviceKey) {
      console.error("[chat/messages GET] No service key set");
      return NextResponse.json({ ok: false, error: "Server misconfigured." }, { status: 500 });
    }

    const { user, tokenProvided } = await getUserFromRequest(req);
    if (tokenProvided && !user) {
      return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
    }

    const roomAccess = await ensureRoomAccess(roomId, user?.id);
    if (!roomAccess.ok) {
      return NextResponse.json({ ok: false, error: roomAccess.error }, { status: roomAccess.status });
    }

    const earliestVisibleMessage = new Date(
      Date.now() - CHAT_HISTORY_RETENTION_HOURS * 60 * 60 * 1000,
    ).toISOString();
    const supabase = createServiceSupabaseClient();
    const { data, error } = await supabase
      .from("messages")
      .select("id, room_id, content, created_at, sender_id")
      .eq("room_id", roomId)
      .gte("created_at", earliestVisibleMessage)
      .order("created_at", { ascending: false })
      .limit(limit)
      .returns<MessageRow[]>();

    if (error) {
      logSupabaseError("[chat/messages GET]", error);
      return NextResponse.json(
        { ok: false, error: "Chat history is temporarily unavailable. Please try again shortly." },
        { status: 500 },
      );
    }

    try {
      const hydratedMessages = await hydrateMessages((data || []).reverse());
      return NextResponse.json({ ok: true, messages: hydratedMessages });
    } catch (profileError) {
      logSupabaseError("[chat/messages GET hydrate]", profileError);
      return NextResponse.json(
        { ok: false, error: "Chat history is temporarily unavailable. Please try again shortly." },
        { status: 500 },
      );
    }
  } catch (err: unknown) {
    const message = getErrorMessage(err, "Unknown error");
    console.error("[chat/messages GET]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const serviceKey = getServiceRoleKey();
    if (!serviceKey) {
      console.error("[chat/messages POST] No service key set");
      return NextResponse.json({ ok: false, error: "Server misconfigured." }, { status: 500 });
    }

    const ip = getRequestIp(req);
    const rate = consumeRateLimit({ key: `chat:${ip}`, limit: 20, windowMs: 30_000 });
    if (!rate.allowed) {
      return NextResponse.json({ ok: false, error: "Slow down! Too many messages." }, { status: 429 });
    }

    const { user } = await getUserFromRequest(req);
    if (!user) {
      return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
    }

    let body: { room_id?: string; content?: string };
    try {
      body = (await req.json()) as { room_id?: string; content?: string };
    } catch {
      return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
    }

    const roomId = body.room_id || GLOBAL_CHAT_ROOM_ID;
    const content = (body.content || "").trim();

    if (!content || content.length > CHAT_MESSAGE_MAX_LENGTH) {
      return NextResponse.json(
        { ok: false, error: `Message must be 1-${CHAT_MESSAGE_MAX_LENGTH} characters.` },
        { status: 400 },
      );
    }

    const roomAccess = await ensureRoomAccess(roomId, user.id);
    if (!roomAccess.ok) {
      return NextResponse.json({ ok: false, error: roomAccess.error }, { status: roomAccess.status });
    }

    const supabase = createServiceSupabaseClient();
    const { data: msg, error } = await supabase
      .from("messages")
      .insert({ room_id: roomId, sender_id: user.id, content })
      .select("id, room_id, content, created_at, sender_id")
      .single<MessageRow>();

    if (error) {
      logSupabaseError("[chat/messages POST insert]", error);
      return NextResponse.json(
        { ok: false, error: "Unable to send message right now. Please try again." },
        { status: 500 },
      );
    }

    try {
      const [hydratedMessage] = await hydrateMessages([msg]);
      return NextResponse.json({ ok: true, message: hydratedMessage });
    } catch (profileError) {
      logSupabaseError("[chat/messages POST hydrate]", profileError);
      return NextResponse.json(
        { ok: false, error: "Message was sent, but chat refresh failed. Please reload the chat." },
        { status: 500 },
      );
    }
  } catch (err: unknown) {
    const message = getErrorMessage(err, "Unknown error");
    console.error("[chat/messages POST]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
