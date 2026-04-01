"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/admin/admin.module.css";

type AdminUser = { user_id: string; username: string; is_admin: boolean; created_at: string };
type AdminLog = { id: string; admin_id: string; action: string; target_user_id: string; details: Record<string, unknown>; created_at: string; admin_username?: string | null };
type Setting = { key: string; value: Record<string, unknown>; updated_at: string };

type Tab = "users" | "logs" | "settings" | "actions";

export default function AdminClient() {
  const [isAdmin, setIsAdmin] = useState(false);
  const [checking, setChecking] = useState(true);
  const [tab, setTab] = useState<Tab>("users");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [logs, setLogs] = useState<AdminLog[]>([]);
  const [settings, setSettings] = useState<Setting[]>([]);
  const [searchQ, setSearchQ] = useState("");
  const [submittedSearchQ, setSubmittedSearchQ] = useState("");
  const [actionBusy, setActionBusy] = useState(false);
  const [actionMsg, setActionMsg] = useState("");
  const [tabError, setTabError] = useState("");
  const abortRef = useRef<AbortController | null>(null);
  const submittedSearchQRef = useRef("");

  // Action form state
  const [actionType, setActionType] = useState("spawn_item");
  const [targetUserId, setTargetUserId] = useState("");
  const [itemId, setItemId] = useState("");
  const [quantity, setQuantity] = useState("1");
  const [amount, setAmount] = useState("");
  const [weatherCondition, setWeatherCondition] = useState("clear");
  const [weatherIntensity, setWeatherIntensity] = useState("1");
  const [weatherGame, setWeatherGame] = useState("fisher");
  const [banReason, setBanReason] = useState("");

  const getToken = useCallback(async () => {
    const supabase = getClientSupabase();
    const { data: { session } } = await supabase.auth.getSession();
    return session?.access_token || "";
  }, []);

  useEffect(() => {
    const check = async () => {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.user) { setChecking(false); return; }
      const { data } = await supabase.from("user_profiles").select("is_admin").eq("user_id", session.user.id).single();
      setIsAdmin(!!data?.is_admin);
      setChecking(false);
    };
    void check();
  }, []);

  useEffect(() => {
    submittedSearchQRef.current = submittedSearchQ;
  }, [submittedSearchQ]);

  const fetchTab = useCallback(async (t: Tab, userQuery?: string) => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setTabError("");
    const token = await getToken();
    if (!token) {
      setTabError("No active session. Please log in again.");
      return;
    }
    try {
      if (t === "users") {
        const query = userQuery ?? submittedSearchQRef.current;
        const res = await fetch(`/api/admin?tab=users&q=${encodeURIComponent(query)}`, {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        const json = await res.json();
        if (json.ok) setUsers(json.users);
        else setTabError(json.error || "Failed to load users.");
      } else if (t === "logs") {
        const res = await fetch("/api/admin?tab=logs", {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        const json = await res.json();
        if (json.ok) setLogs(json.logs);
        else setTabError(json.error || "Failed to load logs.");
      } else if (t === "settings") {
        const res = await fetch("/api/admin?tab=settings", {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        });
        const json = await res.json();
        if (json.ok) setSettings(json.settings);
        else setTabError(json.error || "Failed to load settings.");
      }
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      setTabError(err instanceof Error ? err.message : "Network error. Check your connection.");
    }
  }, [getToken]);

  useEffect(() => {
    if (isAdmin) void fetchTab(tab);
    return () => { abortRef.current?.abort(); };
  }, [tab, isAdmin, fetchTab]);

  const executeAction = useCallback(async () => {
    setActionBusy(true); setActionMsg("");
    try {
      const token = await getToken();
      const body: Record<string, unknown> = { action: actionType, target_user_id: targetUserId };
      if (actionType === "spawn_item") { body.item_id = itemId; body.quantity = Number(quantity) || 1; }
      if (actionType === "set_weather") { body.condition = weatherCondition; body.intensity = Number(weatherIntensity) || 1; body.game = weatherGame; }
      if (actionType === "add_money" || actionType === "remove_money") { body.amount = Number(amount) || 0; }
      if (actionType === "ban_user" || actionType === "delete_user_data") { body.reason = banReason; }

      const res = await fetch("/api/admin", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
      });
      const json = await res.json();
      setActionMsg(json.ok ? json.message : json.error);
      if (json.ok) void fetchTab("logs");
    } finally {
      setActionBusy(false);
    }
  }, [actionType, targetUserId, itemId, quantity, amount, weatherCondition, weatherIntensity, weatherGame, banReason, getToken, fetchTab]);

  if (checking) return <div className={styles.shell}><p>Checking permissions...</p></div>;
  if (!isAdmin) return (
    <div className={styles.shell}>
      <div className={styles.forbidden}>
        <h2>Access Denied</h2>
        <p>You do not have admin privileges.</p>
        <Link href="/home" className={styles.btnPrimary}>Return Home</Link>
      </div>
    </div>
  );

  const tabs: { key: Tab; label: string }[] = [
    { key: "users", label: "Users" }, { key: "actions", label: "Actions" },
    { key: "logs", label: "Logs" }, { key: "settings", label: "Settings" },
  ];

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Admin Dashboard</h1>
        <p className={styles.subtitle}>Platform management and moderation tools.</p>
      </section>

      <nav className={styles.tabs}>
        {tabs.map((t) => (
          <button key={t.key} className={`${styles.tab} ${tab === t.key ? styles.tabActive : ""}`} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </nav>

      {tabError && <p className={`${styles.actionMsg} ${styles.errorText}`}>{tabError}</p>}

      {tab === "users" && (
        <section className={styles.section}>
          <div className={styles.searchBox}>
            <input value={searchQ} onChange={(e) => setSearchQ(e.target.value)} placeholder="Search users..." className={styles.searchInput} />
            <button
              onClick={() => {
                setSubmittedSearchQ(searchQ);
                void fetchTab("users", searchQ);
              }}
              className={styles.btnSmall}
            >
              Search
            </button>
          </div>
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <thead><tr><th>Username</th><th>Admin</th><th>Joined</th><th>User ID</th></tr></thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.user_id}>
                    <td><Link href={`/profile/${u.username}`}>@{u.username}</Link></td>
                    <td>{u.is_admin ? "Yes" : "No"}</td>
                    <td>{new Date(u.created_at).toLocaleDateString()}</td>
                    <td className={styles.mono}>{u.user_id.slice(0, 8)}...</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab === "actions" && (
        <section className={styles.section}>
          <div className={styles.actionForm}>
            <label><span>Action</span>
              <select value={actionType} onChange={(e) => setActionType(e.target.value)} className={styles.selectInput}>
                <option value="spawn_item">Spawn Item</option>
                <option value="set_weather">Set Weather</option>
                <option value="add_money">Add Money</option>
                <option value="remove_money">Remove Money</option>
                <option value="ban_user">Ban User</option>
                <option value="delete_user_data">Delete User Data</option>
              </select>
            </label>

            {actionType !== "set_weather" && (
              <label><span>Target User ID</span><input value={targetUserId} onChange={(e) => setTargetUserId(e.target.value)} className={styles.textInput} placeholder="UUID" /></label>
            )}

            {actionType === "spawn_item" && (
              <>
                <label><span>Item ID</span><input value={itemId} onChange={(e) => setItemId(e.target.value)} className={styles.textInput} placeholder="e.g. rod_titanium" /></label>
                <label><span>Quantity</span><input type="number" value={quantity} onChange={(e) => setQuantity(e.target.value)} className={styles.textInput} min="1" /></label>
              </>
            )}

            {actionType === "set_weather" && (
              <>
                <label><span>Game</span>
                  <select value={weatherGame} onChange={(e) => setWeatherGame(e.target.value)} className={styles.selectInput}>
                    <option value="fisher">Virtual Fisher</option>
                    <option value="farmer">Virtual Farmer</option>
                  </select>
                </label>
                <label><span>Condition</span>
                  <select value={weatherCondition} onChange={(e) => setWeatherCondition(e.target.value)} className={styles.selectInput}>
                    <option value="clear">Clear</option><option value="rain">Rain</option><option value="storm">Storm</option>
                    <option value="fog">Fog</option><option value="snow">Snow</option><option value="wind">Wind</option>
                  </select>
                </label>
                <label><span>Intensity (1-5)</span><input type="number" value={weatherIntensity} onChange={(e) => setWeatherIntensity(e.target.value)} className={styles.textInput} min="1" max="5" /></label>
              </>
            )}

            {(actionType === "add_money" || actionType === "remove_money") && (
              <label><span>Amount</span><input type="number" value={amount} onChange={(e) => setAmount(e.target.value)} className={styles.textInput} min="0" /></label>
            )}

            {(actionType === "ban_user" || actionType === "delete_user_data") && (
              <label><span>Reason</span><input value={banReason} onChange={(e) => setBanReason(e.target.value)} className={styles.textInput} placeholder="Reason" /></label>
            )}

            <button onClick={() => void executeAction()} disabled={actionBusy} className={styles.btnDanger}>
              {actionBusy ? "Executing..." : "Execute Action"}
            </button>
            {actionMsg && <p className={styles.actionMsg}>{actionMsg}</p>}
          </div>
        </section>
      )}

      {tab === "logs" && (
        <section className={styles.section}>
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <thead><tr><th>Admin</th><th>Action</th><th>Target</th><th>Details</th><th>Date</th></tr></thead>
              <tbody>
                {logs.map((l) => (
                  <tr key={l.id}>
                    <td>{l.admin_username ? `@${l.admin_username}` : l.admin_id?.slice(0, 8) || "—"}</td>
                    <td className={styles.mono}>{l.action}</td>
                    <td className={styles.mono}>{l.target_user_id?.slice(0, 8) || "—"}</td>
                    <td className={styles.mono}>{JSON.stringify(l.details).slice(0, 60)}</td>
                    <td>{new Date(l.created_at).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {tab === "settings" && (
        <section className={styles.section}>
          {settings.map((s) => (
            <div key={s.key} className={styles.settingCard}>
              <h3 className={styles.settingKey}>{s.key}</h3>
              <pre className={styles.settingValue}>{JSON.stringify(s.value, null, 2)}</pre>
              <p className={styles.settingMeta}>Last updated: {new Date(s.updated_at).toLocaleString()}</p>
            </div>
          ))}
        </section>
      )}
    </div>
  );
}
