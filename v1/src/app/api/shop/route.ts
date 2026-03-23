import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const supabase = createServerSupabaseClient();
  const category = req.nextUrl.searchParams.get("category");

  let query = supabase.from("shop_items").select("*").eq("is_available", true).order("price", { ascending: true });

  if (category && category !== "all") {
    query = query.eq("category", category);
  }

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, items: data || [] });
}
