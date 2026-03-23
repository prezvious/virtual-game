"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/shop/shop.module.css";

type ShopItem = {
  id: string; name: string; description: string; price: number; currency: string;
  category: string; icon: string; rarity: string; metadata: Record<string, unknown>;
};

const RARITY_COLORS: Record<string, string> = {
  common: "#6b7280", uncommon: "#22c55e", rare: "#3b82f6", epic: "#a855f7", legendary: "#f59e0b",
};
const CATEGORIES = ["all", "rods", "bait", "amulets", "boosts", "cosmetics"];

export default function ShopClient() {
  const [items, setItems] = useState<ShopItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [category, setCategory] = useState("all");
  const [balance, setBalance] = useState({ coins: 0, gems: 0 });
  const [purchaseMsg, setPurchaseMsg] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/shop?category=${category}`);
        const json = await res.json();
        if (json.ok) setItems(json.items);
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.user) {
          const { data } = await supabase.from("user_balances").select("coins, gems").eq("user_id", session.user.id).single();
          if (data) setBalance(data);
        }
      } finally {
        setLoading(false);
      }
    };
    void load();
  }, [category]);

  const purchase = useCallback(async (itemId: string) => {
    setBusy(true); setPurchaseMsg("");
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) { setPurchaseMsg("Sign in to purchase items."); return; }
      const res = await fetch("/api/shop/purchase", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ item_id: itemId, quantity: 1 }),
      });
      const json = await res.json();
      setPurchaseMsg(json.ok ? json.message : json.error);
      if (json.ok) {
        const { data } = await supabase.from("user_balances").select("coins, gems").eq("user_id", session.user.id).single();
        if (data) setBalance(data);
      }
    } finally {
      setBusy(false);
    }
  }, []);

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <div>
          <h1 className={styles.title}>Shop</h1>
          <p className={styles.subtitle}>Upgrade your gear and customize your profile.</p>
        </div>
        <div className={styles.balanceCard}>
          <span className={styles.balanceItem}>{balance.coins.toLocaleString()} coins</span>
          <span className={styles.balanceDivider}>|</span>
          <span className={styles.balanceItem}>{balance.gems.toLocaleString()} gems</span>
        </div>
      </section>

      {purchaseMsg && (
        <div className={styles.purchaseMsg}>
          <p>{purchaseMsg}</p>
          <button onClick={() => setPurchaseMsg("")} className={styles.dismissBtn}>x</button>
        </div>
      )}

      <nav className={styles.filters}>
        {CATEGORIES.map((cat) => (
          <button key={cat} className={`${styles.filterBtn} ${category === cat ? styles.filterActive : ""}`} onClick={() => setCategory(cat)}>
            {cat.charAt(0).toUpperCase() + cat.slice(1)}
          </button>
        ))}
      </nav>

      <section className={styles.grid}>
        {loading ? <p className={styles.emptyMsg}>Loading shop...</p> : items.length === 0 ? <p className={styles.emptyMsg}>No items in this category.</p> : (
          items.map((item) => (
            <article key={item.id} className={styles.card} style={{ borderColor: RARITY_COLORS[item.rarity] }}>
              <div className={styles.cardHeader}>
                <h3 className={styles.cardName}>{item.name}</h3>
                <span className={styles.cardRarity} style={{ color: RARITY_COLORS[item.rarity] }}>{item.rarity.toUpperCase()}</span>
              </div>
              <p className={styles.cardDesc}>{item.description}</p>
              <div className={styles.cardFooter}>
                <span className={styles.cardPrice}>{item.price.toLocaleString()} {item.currency}</span>
                <button onClick={() => void purchase(item.id)} disabled={busy} className={styles.buyBtn}>{busy ? "..." : "Buy"}</button>
              </div>
            </article>
          ))
        )}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/profile" className={styles.btnGhost}>My Profile</Link>
      </section>
    </div>
  );
}
