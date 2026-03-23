-- ============================================================
-- Platform Features Migration: Social, Achievements, Shop,
-- Chat, Admin, Onboarding, Extended Profiles
-- 2026-03-23
-- ============================================================

-- ── Extend user_profiles ────────────────────────────────────
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url text DEFAULT '',
  ADD COLUMN IF NOT EXISTS bio text DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_completed boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- ── Follows (asymmetric — mutual follows = friends) ─────────
CREATE TABLE IF NOT EXISTS follows (
  follower_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- ── Blocks / Restrictions ───────────────────────────────────
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  restriction_type text NOT NULL DEFAULT 'block'
    CHECK (restriction_type IN ('block', 'restrict')),
  created_at       timestamptz DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

-- ── Achievements v2 ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS achievements (
  id                text PRIMARY KEY,
  name              text NOT NULL,
  description       text NOT NULL,
  icon              text NOT NULL DEFAULT 'trophy',
  category          text NOT NULL DEFAULT 'general',
  requirement_type  text NOT NULL DEFAULT 'count',
  requirement_value int  NOT NULL DEFAULT 1,
  rarity            text NOT NULL DEFAULT 'common'
    CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  xp_reward         int  DEFAULT 0,
  sort_order        int  DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_achievements (
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  achievement_id text NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
  unlocked_at    timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, achievement_id)
);

-- Seed 20 achievements
INSERT INTO achievements (id, name, description, icon, category, requirement_type, requirement_value, rarity, xp_reward, sort_order) VALUES
  ('first_cast',        'First Cast',        'Catch your very first fish.',                          'fish',       'fishing',     'fish_caught',     1,        'common',    50,   1),
  ('hooked_10',         'Getting Hooked',    'Catch 10 fish total.',                                 'anchor',     'fishing',     'fish_caught',     10,       'common',    100,  2),
  ('century_catch',     'Century Catch',     'Catch 100 fish across all biomes.',                    'waves',      'fishing',     'fish_caught',     100,      'uncommon',  250,  3),
  ('fish_500',          'Master Angler',     'Catch 500 fish — you live on the water now.',          'sailboat',   'fishing',     'fish_caught',     500,      'rare',      500,  4),
  ('legendary_pull',    'Legendary Pull',    'Land a Legendary-rarity fish.',                        'crown',      'fishing',     'legendary_fish',  1,        'epic',      750,  5),
  ('biome_explorer',    'Biome Explorer',    'Fish in 10 different biomes.',                         'compass',    'exploration', 'biomes_visited',  10,       'uncommon',  200,  6),
  ('world_traveler',    'World Traveler',    'Visit every biome at least once.',                     'globe',      'exploration', 'biomes_visited',  60,       'legendary', 1500, 7),
  ('early_bird',        'Early Bird',        'Log in for 3 consecutive days.',                       'sunrise',    'dedication',  'login_streak',    3,        'common',    100,  8),
  ('devoted_player',    'Devoted Player',    'Log in for 14 consecutive days.',                      'calendar',   'dedication',  'login_streak',    14,       'rare',      400,  9),
  ('social_butterfly',  'Social Butterfly',  'Make 5 mutual friends on the platform.',               'users',      'social',      'friends_count',   5,        'uncommon',  200,  10),
  ('big_spender',       'Big Spender',       'Spend 10,000 coins in the shop.',                      'shopping-bag','economy',    'coins_spent',     10000,    'uncommon',  300,  11),
  ('gold_rush',         'Gold Rush',         'Earn 100,000 total money across all games.',           'coins',      'economy',     'money_earned',    100000,   'rare',      500,  12),
  ('millionaire_club',  'Millionaire Club',  'Accumulate 1,000,000 coins in your balance.',          'gem',        'economy',     'money_earned',    1000000,  'legendary', 2000, 13),
  ('rod_collector',     'Rod Collector',     'Own 5 different fishing rods.',                        'tool',       'collection',  'rods_owned',      5,        'uncommon',  200,  14),
  ('bait_master',       'Bait Master',       'Use 8 different bait types.',                          'bug',        'collection',  'baits_used',      8,        'rare',      350,  15),
  ('species_catalog',   'Species Catalog',   'Discover 50 unique fish species.',                     'book-open',  'collection',  'species_found',   50,       'rare',      500,  16),
  ('chat_champion',     'Chat Champion',     'Send 100 messages in chat.',                           'message-circle','social',   'messages_sent',   100,      'uncommon',  150,  17),
  ('night_owl',         'Night Owl',         'Play a game session between midnight and 4 AM.',       'moon',       'dedication',  'night_sessions',  1,        'uncommon',  100,  18),
  ('completionist',     'Completionist',     'Unlock 15 other achievements.',                        'award',      'meta',        'achievements_unlocked', 15, 'epic',     1000, 19),
  ('platform_pioneer',  'Platform Pioneer',  'Complete the onboarding tutorial.',                    'rocket',     'meta',        'onboarding_done', 1,        'common',    75,   20)
ON CONFLICT (id) DO NOTHING;

-- ── Shop Items ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shop_items (
  id           text PRIMARY KEY,
  name         text NOT NULL,
  description  text NOT NULL,
  price        int  NOT NULL,
  currency     text NOT NULL DEFAULT 'coins' CHECK (currency IN ('coins','gems')),
  category     text NOT NULL DEFAULT 'general',
  icon         text NOT NULL DEFAULT 'package',
  rarity       text NOT NULL DEFAULT 'common'
    CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  is_available boolean DEFAULT true,
  metadata     jsonb DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS user_inventory (
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id      text NOT NULL REFERENCES shop_items(id) ON DELETE CASCADE,
  quantity     int  DEFAULT 1,
  purchased_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, item_id)
);

CREATE TABLE IF NOT EXISTS user_balances (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  coins   bigint DEFAULT 500,
  gems    int    DEFAULT 0
);

-- Seed shop items
INSERT INTO shop_items (id, name, description, price, currency, category, icon, rarity, metadata) VALUES
  ('rod_bamboo',       'Bamboo Rod',          'A lightweight starter rod. Reliable and humble.',                          200,   'coins', 'rods',      'tool',        'common',    '{"catch_bonus": 0}'),
  ('rod_carbon',       'Carbon Fiber Rod',    'Modern engineering. +10% catch speed.',                                   1500,  'coins', 'rods',      'tool',        'uncommon',  '{"catch_bonus": 10}'),
  ('rod_titanium',     'Titanium Rod',        'Built for deep-water legends. +25% catch speed.',                         5000,  'coins', 'rods',      'tool',        'rare',      '{"catch_bonus": 25}'),
  ('rod_mythic',       'Mythic Rod',          'Forged in starlight. +50% catch speed, +rare fish chance.',               25000, 'coins', 'rods',      'tool',        'legendary', '{"catch_bonus": 50, "rare_boost": true}'),
  ('bait_worm',        'Earthworm Pack',      'Standard bait. 20 uses.',                                                100,   'coins', 'bait',      'bug',         'common',    '{"uses": 20}'),
  ('bait_shrimp',      'Shrimp Bait',         'Attracts mid-tier fish. 15 uses.',                                       350,   'coins', 'bait',      'bug',         'uncommon',  '{"uses": 15}'),
  ('bait_golden',      'Golden Lure',         'Significantly increases rare fish chance. 10 uses.',                      2000,  'coins', 'bait',      'sparkles',    'rare',      '{"uses": 10, "rare_boost": true}'),
  ('bait_phantom',     'Phantom Bait',        'Draws legendary fish from the void. 5 uses.',                             8000,  'coins', 'bait',      'ghost',       'epic',      '{"uses": 5, "legendary_boost": true}'),
  ('amulet_luck',      'Lucky Amulet',        'Slightly boosts rare drop rates while equipped.',                         3000,  'coins', 'amulets',   'gem',         'rare',      '{"luck_bonus": 5}'),
  ('amulet_xp',        'Wisdom Amulet',       'Earn 15% more XP from all activities.',                                  4500,  'coins', 'amulets',   'book-open',   'rare',      '{"xp_bonus": 15}'),
  ('amulet_void',      'Void Amulet',         'Unlocks the Aetherial Void biome.',                                      50000, 'coins', 'amulets',   'eye',         'legendary', '{"unlocks_biome": "aetherial_void"}'),
  ('boost_2x_coins',   'Double Coins (1hr)',  'All coin earnings doubled for 60 minutes.',                               1200,  'coins', 'boosts',    'zap',         'uncommon',  '{"duration_min": 60, "multiplier": 2}'),
  ('boost_2x_xp',      'Double XP (1hr)',     'All XP earnings doubled for 60 minutes.',                                1200,  'coins', 'boosts',    'trending-up', 'uncommon',  '{"duration_min": 60, "multiplier": 2}'),
  ('boost_auto_fish',  'Auto-Fish (30min)',   'Fish are caught automatically for 30 minutes.',                           3000,  'gems',  'boosts',    'cpu',         'rare',      '{"duration_min": 30}'),
  ('cosmetic_hat_1',   'Sailor Hat',          'A classic maritime look for your profile.',                               800,   'coins', 'cosmetics', 'anchor',      'common',    '{"slot": "hat"}'),
  ('cosmetic_hat_2',   'Pirate Tricorn',      'Arr! Strike fear into the fish.',                                         2500,  'coins', 'cosmetics', 'skull',       'uncommon',  '{"slot": "hat"}'),
  ('cosmetic_frame_1', 'Ocean Frame',         'A wave-patterned profile frame.',                                         1500,  'coins', 'cosmetics', 'frame',       'uncommon',  '{"slot": "frame"}'),
  ('cosmetic_frame_2', 'Golden Frame',        'A prestigious golden border for your profile.',                           15000, 'coins', 'cosmetics', 'award',       'epic',      '{"slot": "frame"}'),
  ('cosmetic_title_1', 'Title: The Fisher',   'Display "The Fisher" on your profile.',                                   500,   'coins', 'cosmetics', 'tag',         'common',    '{"title": "The Fisher"}'),
  ('cosmetic_title_2', 'Title: Legend of the Deep', 'Display "Legend of the Deep" on your profile.',                     20000, 'coins', 'cosmetics', 'crown',       'legendary', '{"title": "Legend of the Deep"}')
ON CONFLICT (id) DO NOTHING;

-- ── Chat System ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_rooms (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text,
  type       text NOT NULL DEFAULT 'dm' CHECK (type IN ('dm','group','global')),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat_members (
  room_id   uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id    uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content    text NOT NULL CHECK (char_length(content) <= 2000),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at DESC);

-- Seed global chat room
INSERT INTO chat_rooms (id, name, type) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Global Chat', 'global')
ON CONFLICT (id) DO NOTHING;

-- ── Admin Logs ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_logs (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id       uuid NOT NULL REFERENCES auth.users(id),
  action         text NOT NULL,
  target_user_id uuid REFERENCES auth.users(id),
  details        jsonb DEFAULT '{}',
  created_at     timestamptz DEFAULT now()
);

-- ── Platform Settings (weather, announcements, etc.) ────────
CREATE TABLE IF NOT EXISTS platform_settings (
  key        text PRIMARY KEY,
  value      jsonb NOT NULL DEFAULT '{}',
  updated_by uuid REFERENCES auth.users(id),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO platform_settings (key, value) VALUES
  ('global_weather', '{"condition": "clear", "intensity": 1}'),
  ('motd', '{"message": "Welcome to Virtual Harvest Platform!"}')
ON CONFLICT (key) DO NOTHING;

-- ── Onboarding Progress ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS onboarding_progress (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  steps_completed text[] DEFAULT '{}',
  skipped         boolean DEFAULT false,
  completed_at    timestamptz
);

-- ── RLS Policies ────────────────────────────────────────────

-- Follows
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY follows_select ON follows FOR SELECT USING (true);
CREATE POLICY follows_insert ON follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_delete ON follows FOR DELETE USING (auth.uid() = follower_id);

-- Blocks
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY blocks_select ON blocks FOR SELECT USING (auth.uid() = blocker_id);
CREATE POLICY blocks_insert ON blocks FOR INSERT WITH CHECK (auth.uid() = blocker_id);
CREATE POLICY blocks_delete ON blocks FOR DELETE USING (auth.uid() = blocker_id);

-- Achievements (public read)
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY achievements_select ON achievements FOR SELECT USING (true);

-- User achievements
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_achievements_select ON user_achievements FOR SELECT USING (true);
CREATE POLICY user_achievements_insert ON user_achievements FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Shop items (public read)
ALTER TABLE shop_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY shop_items_select ON shop_items FOR SELECT USING (true);

-- User inventory
ALTER TABLE user_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_inventory_select ON user_inventory FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_inventory_insert ON user_inventory FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_inventory_update ON user_inventory FOR UPDATE USING (auth.uid() = user_id);

-- User balances
ALTER TABLE user_balances ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_balances_select ON user_balances FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_balances_update ON user_balances FOR UPDATE USING (auth.uid() = user_id);

-- Chat rooms (members can read)
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_rooms_select ON chat_rooms FOR SELECT USING (
  type = 'global' OR
  EXISTS (SELECT 1 FROM chat_members WHERE chat_members.room_id = id AND chat_members.user_id = auth.uid())
);

-- Chat members
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_members_select ON chat_members FOR SELECT USING (user_id = auth.uid() OR
  EXISTS (SELECT 1 FROM chat_members cm WHERE cm.room_id = chat_members.room_id AND cm.user_id = auth.uid()));
CREATE POLICY chat_members_insert ON chat_members FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY messages_select ON messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM chat_rooms WHERE chat_rooms.id = room_id AND chat_rooms.type = 'global') OR
  EXISTS (SELECT 1 FROM chat_members WHERE chat_members.room_id = messages.room_id AND chat_members.user_id = auth.uid())
);
CREATE POLICY messages_insert ON messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Admin logs (admin only)
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_logs_select ON admin_logs FOR SELECT USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);
CREATE POLICY admin_logs_insert ON admin_logs FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);

-- Platform settings (public read, admin write)
ALTER TABLE platform_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_settings_select ON platform_settings FOR SELECT USING (true);
CREATE POLICY platform_settings_update ON platform_settings FOR UPDATE USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);

-- Onboarding progress
ALTER TABLE onboarding_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY onboarding_select ON onboarding_progress FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY onboarding_insert ON onboarding_progress FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY onboarding_update ON onboarding_progress FOR UPDATE USING (auth.uid() = user_id);

-- ── Enable Realtime for chat ────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
