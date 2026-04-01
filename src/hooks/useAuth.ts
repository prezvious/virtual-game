"use client";

import { useCallback, useEffect, useState } from "react";
import type { User, Session } from "@supabase/supabase-js";
import { getClientSupabase } from "@/lib/auth-client";

type AuthState = {
  user: User | null;
  session: Session | null;
  loading: boolean;
};

export function useAuth() {
  const [state, setState] = useState<AuthState>({ user: null, session: null, loading: true });

  useEffect(() => {
    const supabase = getClientSupabase();
    let mounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setState({ user: data.session?.user ?? null, session: data.session, loading: false });
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!mounted) return;
      setState({ user: session?.user ?? null, session, loading: false });
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const signOut = useCallback(async () => {
    const supabase = getClientSupabase();
    await supabase.auth.signOut();
  }, []);

  return { ...state, signOut };
}
