/**
 * RARITY DEFINITIONS
 * Defines all fish rarity tiers with their colors, multipliers, XP, difficulty,
 * minigame speed, and scarcity-first absolute drop rates.
 */

const RARITY = {
    common:       { name: "Common",       color: "#94a3b8", mult: 4,       xp: 75,      difficulty: 0.80, speed: 1.00, baseChance: 1,          maxChance: 1 },
    uncommon:     { name: "Uncommon",     color: "#4ade80", mult: 9,       xp: 150,     difficulty: 0.62, speed: 1.10, baseChance: 0.28,       maxChance: 0.65 },
    rare:         { name: "Rare",         color: "#6dd6ff", mult: 25,      xp: 350,     difficulty: 0.50, speed: 1.25, baseChance: 0.12,       maxChance: 0.45 },
    epic:         { name: "Epic",         color: "#a78bfa", mult: 45,      xp: 800,     difficulty: 0.38, speed: 1.45, baseChance: 0.05,       maxChance: 0.28 },
    legendary:    { name: "Legendary",    color: "#fb7185", mult: 110,     xp: 2000,    difficulty: 0.28, speed: 2.00, baseChance: 0.02,       maxChance: 0.14 },
    liminal:      { name: "Liminal",      color: "#f97316", mult: 180,     xp: 3400,    difficulty: 0.23, speed: 2.30, baseChance: 0.008,      maxChance: 0.08 },
    mythic:       { name: "Mythic",       color: "#facc15", mult: 260,     xp: 5000,    difficulty: 0.19, speed: 2.70, baseChance: 0.0032,     maxChance: 0.04 },
    ascendant:    { name: "Ascendant",    color: "#84cc16", mult: 520,     xp: 9000,    difficulty: 0.16, speed: 3.00, baseChance: 0.00128,    maxChance: 0.02 },
    celestial:    { name: "Celestial",    color: "#22c55e", mult: 980,     xp: 15000,   difficulty: 0.14, speed: 3.30, baseChance: 0.000512,   maxChance: 0.01 },
    eldritch:     { name: "Eldritch",     color: "#14b8a6", mult: 1850,    xp: 25000,   difficulty: 0.12, speed: 3.60, baseChance: 0.000205,   maxChance: 0.005 },
    eternal:      { name: "Eternal",      color: "#06b6d4", mult: 3500,    xp: 42000,   difficulty: 0.11, speed: 3.90, baseChance: 0.000082,   maxChance: 0.0025 },
    divine:       { name: "Divine",       color: "#0ea5e9", mult: 6600,    xp: 70000,   difficulty: 0.10, speed: 4.20, baseChance: 0.000033,   maxChance: 0.0013 },
    cosmic:       { name: "Cosmic",       color: "#3b82f6", mult: 12500,   xp: 116000,  difficulty: 0.09, speed: 4.50, baseChance: 0.000013,   maxChance: 0.00065 },
    primordial:   { name: "Primordial",   color: "#6366f1", mult: 23600,   xp: 190000,  difficulty: 0.08, speed: 4.80, baseChance: 0.0000052,  maxChance: 0.00033 },
    transcendent: { name: "Transcendent", color: "#8b5cf6", mult: 44500,   xp: 310000,  difficulty: 0.07, speed: 5.10, baseChance: 0.0000021,  maxChance: 0.00017 },
    apotheosis:   { name: "Apotheosis",   color: "#a855f7", mult: 84000,   xp: 500000,  difficulty: 0.06, speed: 5.40, baseChance: 0.00000084, maxChance: 0.000085 },
    absolute:     { name: "Absolute",     color: "#d946ef", mult: 158000,  xp: 800000,  difficulty: 0.055, speed: 5.70, baseChance: 0.00000034, maxChance: 0.000043 },
    singularity:  { name: "Singularity",  color: "#ec4899", mult: 298000,  xp: 1280000, difficulty: 0.05, speed: 6.00, baseChance: 0.00000013, maxChance: 0.000022 },
    paradox:      { name: "Paradox",      color: "#f43f5e", mult: 562000,  xp: 2050000, difficulty: 0.05, speed: 6.30, baseChance: 0.000000052, maxChance: 0.000011 },
    null:         { name: "Null",         color: "#f8fafc", mult: 1060000, xp: 3300000, difficulty: 0.05, speed: 6.60, baseChance: 0.000000021, maxChance: 0.0000055 }
};

// Freeze rarity data to prevent console exploits
Object.values(RARITY).forEach(r => Object.freeze(r));
Object.freeze(RARITY);
