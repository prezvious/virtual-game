"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import { CHAT_MESSAGE_MAX_LENGTH, GLOBAL_CHAT_ROOM_ID } from "@/lib/chat";
import styles from "@/app/chat/chat.module.css";

type Message = {
  id: string;
  content: string;
  created_at: string;
  sender_id: string;
  user_profiles?: { username: string | null; avatar_url: string | null } | null;
};

export default function ChatClient() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [currentUserId, setCurrentUserId] = useState("");
  const [currentUsername, setCurrentUsername] = useState("");
  const [loadError, setLoadError] = useState("");
  const [sendError, setSendError] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = useCallback((behavior: ScrollBehavior = "smooth") => {
    bottomRef.current?.scrollIntoView({ behavior });
  }, []);

  const fetchMessages = useCallback(async (options: { scrollBehavior?: ScrollBehavior } = {}) => {
    try {
      const res = await fetch(`/api/chat/messages?room_id=${GLOBAL_CHAT_ROOM_ID}&limit=50`, {
        cache: "no-store",
      });
      const json = await res.json();
      if (!res.ok || !json.ok) {
        throw new Error(json.error || "Unable to load chat history.");
      }

      setLoadError("");
      setMessages((prev) => {
        const incoming = (json.messages as Message[]) || [];
        const previousLastId = prev.length > 0 ? prev[prev.length - 1].id : null;
        const incomingLastId = incoming.length > 0 ? incoming[incoming.length - 1].id : null;
        const shouldScroll =
          Boolean(options.scrollBehavior) ||
          prev.length === 0 ||
          prev.length !== incoming.length ||
          previousLastId !== incomingLastId;

        if (shouldScroll) {
          const behavior = options.scrollBehavior ?? (prev.length === 0 ? "auto" : "smooth");
          setTimeout(() => scrollToBottom(behavior), 100);
        }

        return incoming;
      });
    } catch (error: unknown) {
      setLoadError(error instanceof Error ? error.message : "Unable to load chat history.");
    } finally {
      setLoading(false);
    }
  }, [scrollToBottom]);

  useEffect(() => {
    const supabase = getClientSupabase();
    let active = true;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const init = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!active) return;

        if (session?.user) {
          setCurrentUserId(session.user.id);
          const fallbackUsername =
            typeof session.user.user_metadata?.username === "string"
              ? session.user.user_metadata.username
              : session.user.email?.split("@")[0] || "";
          setCurrentUsername(fallbackUsername);

          const { data, error } = await supabase
            .from("user_profiles")
            .select("username")
            .eq("user_id", session.user.id)
            .maybeSingle<{ username: string | null }>();
          if (error) {
            console.error("[chat] failed to load current username", error.message);
          } else if (active && data?.username) {
            setCurrentUsername(data.username);
          }
        } else {
          setCurrentUserId("");
          setCurrentUsername("");
        }

        await fetchMessages({ scrollBehavior: "auto" });
        if (!active) return;

        channel = supabase
          .channel("global-chat")
          .on(
            "postgres_changes",
            {
              event: "INSERT",
              schema: "public",
              table: "messages",
              filter: `room_id=eq.${GLOBAL_CHAT_ROOM_ID}`,
            },
            () => {
              void fetchMessages({ scrollBehavior: "smooth" });
            },
          )
          .subscribe((status) => {
            if (!active) return;

            if (status === "SUBSCRIBED") {
              setLoadError("");
              void fetchMessages();
            }

            if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
              setLoadError("Live chat disconnected. Retrying automatically.");
            }
          });
      } catch (error: unknown) {
        if (!active) return;
        setLoadError(error instanceof Error ? error.message : "Unable to initialize chat.");
        setLoading(false);
      }
    };

    void init();

    const poll = window.setInterval(() => {
      void fetchMessages();
    }, 3000);

    return () => {
      active = false;
      window.clearInterval(poll);
      if (channel) {
        void supabase.removeChannel(channel);
      }
    };
  }, [fetchMessages]);

  const sendMessage = useCallback(async () => {
    const text = input.trim();
    if (!text || sending) return;

    setSending(true);
    setSendError("");
    setInput("");

    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        throw new Error("Sign in to chat before sending a message.");
      }

      const res = await fetch("/api/chat/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ room_id: GLOBAL_CHAT_ROOM_ID, content: text }),
      });
      const json = await res.json();
      if (!res.ok || !json.ok || !json.message) {
        throw new Error(json.error || "Unable to send message right now.");
      }

      setMessages((prev) => {
        const optimistic = json.message as Message;
        if (prev.some((message) => message.id === optimistic.id)) return prev;
        return [...prev, optimistic];
      });
      setTimeout(() => scrollToBottom("smooth"), 100);
      void fetchMessages();
    } catch (error: unknown) {
      setInput(text);
      setSendError(error instanceof Error ? error.message : "Unable to send message right now.");
    } finally {
      setSending(false);
    }
  }, [fetchMessages, input, scrollToBottom, sending]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void sendMessage();
    }
  };

  const formatTime = (iso: string) => {
    try {
      return new Date(iso).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" });
    } catch {
      return "";
    }
  };

  const renderAuthor = (senderName: string) => {
    if (senderName === "Unknown") {
      return <span className={styles.msgAuthor}>@{senderName}</span>;
    }

    return (
      <Link href={`/profile/${senderName}`} className={styles.msgAuthor}>
        @{senderName}
      </Link>
    );
  };

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Global Chat</h1>
        <p className={styles.subtitle}>Chat with the Virtual Harvest community</p>
      </section>

      <section className={styles.chatBox}>
        {loadError && (
          <p className={styles.errorBanner} role="alert">
            {loadError}
          </p>
        )}

        <div className={styles.messages}>
          {loading && <p className={styles.emptyMsg}>Loading messages...</p>}
          {!loading && messages.length === 0 && <p className={styles.emptyMsg}>No messages yet. Be the first!</p>}
          {messages.map((msg) => {
            const isOwn = msg.sender_id === currentUserId;
            const senderName = msg.user_profiles?.username || (isOwn ? currentUsername : "Unknown");
            return (
              <div key={msg.id} className={`${styles.message} ${isOwn ? styles.messageOwn : ""}`}>
                <div className={styles.msgHeader}>
                  {renderAuthor(senderName)}
                  <span className={styles.msgTime}>{formatTime(msg.created_at)}</span>
                </div>
                <p className={styles.msgContent}>{msg.content}</p>
              </div>
            );
          })}
          <div ref={bottomRef} />
        </div>

        {currentUserId ? (
          <div className={styles.composer}>
            {sendError && (
              <p className={styles.inputError} role="alert">
                {sendError}
              </p>
            )}

            <div className={styles.inputBar}>
              <textarea
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Type a message..."
                className={styles.chatInput}
                maxLength={CHAT_MESSAGE_MAX_LENGTH}
                rows={1}
              />
              <button onClick={() => void sendMessage()} disabled={sending || !input.trim()} className={styles.sendBtn}>
                {sending ? "..." : "Send"}
              </button>
            </div>
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
