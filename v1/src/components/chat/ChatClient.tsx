"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/chat/chat.module.css";

type Message = {
  id: string;
  content: string;
  created_at: string;
  sender_id: string;
  user_profiles?: { username: string; avatar_url: string } | null;
};

const GLOBAL_ROOM = "00000000-0000-0000-0000-000000000001";

export default function ChatClient() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [currentUserId, setCurrentUserId] = useState("");
  const [currentUsername, setCurrentUsername] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  const fetchMessages = useCallback(async () => {
    try {
      const res = await fetch(`/api/chat/messages?room_id=${GLOBAL_ROOM}&limit=50`);
      const json = await res.json();
      if (json.ok) {
        setMessages(json.messages);
        setTimeout(scrollToBottom, 100);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const init = async () => {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (session?.user) {
        setCurrentUserId(session.user.id);
        const { data } = await supabase.from("user_profiles").select("username").eq("user_id", session.user.id).single();
        if (data) setCurrentUsername(data.username);
      }
      await fetchMessages();

      // Subscribe to realtime messages
      const channel = supabase
        .channel("global-chat")
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `room_id=eq.${GLOBAL_ROOM}` },
          (payload) => {
            const newMsg = payload.new as Message;
            setMessages((prev) => [...prev, newMsg]);
            setTimeout(scrollToBottom, 100);
          }
        )
        .subscribe();

      return () => { supabase.removeChannel(channel); };
    };

    const cleanup = init();
    return () => { void cleanup.then((fn) => fn?.()); };
  }, [fetchMessages]);

  const sendMessage = useCallback(async () => {
    const text = input.trim();
    if (!text || sending) return;
    setSending(true);
    setInput("");
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const res = await fetch("/api/chat/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ room_id: GLOBAL_ROOM, content: text }),
      });
      const json = await res.json();
      if (!json.ok) setInput(text);
    } finally {
      setSending(false);
    }
  }, [input, sending]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); void sendMessage(); }
  };

  const formatTime = (iso: string) => {
    try { return new Date(iso).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }); }
    catch { return ""; }
  };

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Global Chat</h1>
        <p className={styles.subtitle}>Chat with the Virtual Harvest community</p>
      </section>

      <section className={styles.chatBox}>
        <div className={styles.messages}>
          {loading && <p className={styles.emptyMsg}>Loading messages...</p>}
          {!loading && messages.length === 0 && <p className={styles.emptyMsg}>No messages yet. Be the first!</p>}
          {messages.map((msg) => {
            const isOwn = msg.sender_id === currentUserId;
            const senderName = msg.user_profiles?.username || (isOwn ? currentUsername : "Unknown");
            return (
              <div key={msg.id} className={`${styles.message} ${isOwn ? styles.messageOwn : ""}`}>
                <div className={styles.msgHeader}>
                  <Link href={`/profile/${senderName}`} className={styles.msgAuthor}>@{senderName}</Link>
                  <span className={styles.msgTime}>{formatTime(msg.created_at)}</span>
                </div>
                <p className={styles.msgContent}>{msg.content}</p>
              </div>
            );
          })}
          <div ref={bottomRef} />
        </div>

        {currentUserId ? (
          <div className={styles.inputBar}>
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Type a message..."
              className={styles.chatInput}
              maxLength={2000}
              rows={1}
            />
            <button onClick={() => void sendMessage()} disabled={sending || !input.trim()} className={styles.sendBtn}>
              {sending ? "..." : "Send"}
            </button>
          </div>
        ) : (
          <div className={styles.signInBar}>
            <p>Sign in to chat.</p>
            <Link href="/home" className={styles.btnPrimary}>Sign In</Link>
          </div>
        )}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/friends" className={styles.btnGhost}>Friends</Link>
      </section>
    </div>
  );
}
