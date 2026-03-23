/**
 * ROD DEFINITIONS
 * All fishing rods with their stats: cost, luck bonus, weight capacity, and speed.
 */

const RODS = [
    { id: 'bamboo', name: 'Bamboo Pole', cost: 0, luck: 2, capacity: 15, speed: 5 },
    { id: 'fiberglass', name: 'Fiberglass Rod', cost: 450, luck: 12, capacity: 35, speed: 10 },
    { id: 'graphite', name: 'Graphite Precision', cost: 2500, luck: 18, capacity: 60, speed: 15 },
    { id: 'carbon', name: 'Carbon Striker', cost: 2500, luck: 30, capacity: 100, speed: 20 },
    {
        id: 'currentline',
        name: 'Currentline',
        cost: 6200,
        luck: 38,
        capacity: 135,
        speed: 46,
        tier: 'mid',
        passive: {
            summary: 'Faster auto cycles and hook timing, but control drops on heavy fish.',
            autoCycleMultiplier: 0.84,
            hookTimingMultiplier: 0.78,
            heavyThreshold: 0.72,
            heavyPenalty: 0.18
        }
    },
    {
        id: 'needlepoint',
        name: 'Needlepoint',
        cost: 7000,
        luck: 42,
        capacity: 175,
        speed: 34,
        tier: 'mid',
        passive: {
            summary: 'Lightly boosts Rare and Epic table weights. Mythic remains untouched.',
            rarityBias: {
                rare: 1.12,
                epic: 1.18
            }
        }
    },
    {
        id: 'trenchhaul',
        name: 'Trenchhaul',
        cost: 7600,
        luck: 36,
        capacity: 235,
        speed: 29,
        tier: 'mid',
        passive: {
            summary: 'Raises average fish weight rolls by roughly 8% to 15%.',
            weightMultiplierMin: 1.08,
            weightMultiplierMax: 1.15
        }
    },
    { id: 'alloy', name: 'Titanium Alloy', cost: 8000, luck: 45, capacity: 200, speed: 30 },
    { id: 'neofiber', name: 'Nano-Weave Pro', cost: 50000, luck: 65, capacity: 400, speed: 35 },
    { id: 'quantum', name: 'Quantum Weaver', cost: 25000, luck: 80, capacity: 600, speed: 40 },
    { id: 'starcaller', name: 'Starcaller', cost: 75000, luck: 150, capacity: 2000, speed: 50 },
    { id: 'void', name: 'Void Walker', cost: 250000, luck: 300, capacity: 10000, speed: 60 },
    { id: 'aether', name: 'Aether-Caster', cost: 2500000, luck: 200, capacity: 5000, speed: 55 },
    { id: 'chronos', name: 'Chrono-Spinner', cost: 25000000, luck: 450, capacity: 25000, speed: 70 },
    { id: 'omniverse', name: 'Omni-Verse Rod', cost: 500000000, luck: 800, capacity: 100000, speed: 90 },
    {
        id: 'burdenhook',
        name: 'The Burdenhook',
        cost: 850000000,
        luck: 760,
        capacity: 125000,
        speed: 78,
        passive: {
            mode: 'volatile',
            effectLabel: 'Deep Set',
            effectColor: '#f59e0b',
            triggerChance: 0.06,
            accessRarities: ['absolute'],
            effectRarityBias: {
                absolute: 1200,
                apotheosis: 1.12,
                transcendent: 1.06
            },
            salvageChance: 0.42,
            salvageRarities: ['absolute'],
            salvageWeightMultiplier: 0.92,
            salvageValueMultiplier: 0.82,
            targetWidthMultiplier: 0.82,
            summary: 'Deep Set rarely opens an Absolute cast and may crush an impossible load into line. Strong rescue potential, tighter reel zone, lighter payout.'
        }
    },
    {
        id: 'whispergauge',
        name: 'Whispergauge',
        cost: 1100000000,
        luck: 980,
        capacity: 105000,
        speed: 96,
        passive: {
            mode: 'volatile',
            effectLabel: 'Fine Seam',
            effectColor: '#22c55e',
            triggerChance: 0.05,
            accessRarities: ['singularity', 'absolute'],
            effectRarityBias: {
                singularity: 1450,
                absolute: 1.28,
                apotheosis: 1.1
            },
            salvageChance: 0.12,
            salvageRarities: ['singularity'],
            salvageWeightMultiplier: 0.96,
            salvageValueMultiplier: 0.94,
            summary: 'Fine Seam almost never shows twice in a row. When it appears, upper-tier odds jump for one cast, but oversized fish still usually tear free.'
        }
    },
    {
        id: 'contraryloom',
        name: 'Contrary Loom',
        cost: 1450000000,
        luck: 880,
        capacity: 118000,
        speed: 84,
        passive: {
            mode: 'volatile',
            effectLabel: 'Crossweave',
            effectColor: '#fb7185',
            triggerChance: 0.045,
            accessRarities: ['paradox', 'singularity', 'absolute'],
            effectRarityBias: {
                paradox: 1850,
                singularity: 1.32,
                absolute: 1.18
            },
            failureSaveChance: 0.18,
            failureDowngradeChance: 0.42,
            failureDowngradeRarities: ['absolute', 'singularity', 'paradox', 'null'],
            salvageWeightMultiplier: 0.95,
            salvageValueMultiplier: 0.86,
            summary: 'Crossweave seldom catches hold, but when it does a lost top-tier hook may stay live or soften one tier instead of vanishing outright.'
        }
    },
    {
        id: 'palemooring',
        name: 'Pale Mooring',
        cost: 1900000000,
        luck: 910,
        capacity: 112000,
        speed: 72,
        passive: {
            mode: 'volatile',
            effectLabel: 'Still Water',
            effectColor: '#e2e8f0',
            triggerChance: 0.04,
            accessRarities: ['null', 'paradox', 'singularity'],
            effectRarityBias: {
                null: 2600,
                paradox: 1.36,
                singularity: 1.12
            },
            salvageChance: 0.58,
            salvageRarities: ['null', 'paradox'],
            salvageWeightMultiplier: 0.94,
            salvageValueMultiplier: 0.9,
            targetWidthMultiplier: 0.68,
            summary: 'Still Water is rare and eerie. It occasionally pins Null-tier catches long enough to land them, but the manual reel window is merciless.'
        }
    },
    {
        id: 'tallyspool',
        name: 'Tallyspool',
        cost: 950000000,
        luck: 790,
        capacity: 120000,
        speed: 82,
        passive: {
            mode: 'measured',
            effectLabel: 'Turn of Thread',
            effectColor: '#14b8a6',
            favorGoal: 10,
            windowCasts: 4,
            favorOnEmpty: 2,
            favorOnEscape: 2,
            favorOnLowCatch: 1,
            lowCatchMaxRarity: 'epic',
            accessRarities: ['absolute', 'singularity', 'paradox'],
            effectRarityBias: {
                absolute: 650,
                singularity: 900,
                paradox: 1200,
                apotheosis: 1.08
            },
            salvageChance: 0.3,
            salvageRarities: ['absolute', 'singularity', 'paradox'],
            salvageWeightMultiplier: 0.93,
            salvageValueMultiplier: 0.88,
            summary: 'Measured rod. Misses and low-tier catches build Favor; a full spool opens Turn of Thread for a few richer casts without ever forcing a prize.'
        }
    }
];

// Re-sorting rods by cost to ensure logical progression in UI
RODS.sort((a, b) => a.cost - b.cost);
// Freeze static data to prevent console exploits
RODS.forEach(rod => {
    if (rod.passive && typeof rod.passive === 'object') {
        if (rod.passive.rarityBias && typeof rod.passive.rarityBias === 'object') {
            Object.freeze(rod.passive.rarityBias);
        }
        Object.freeze(rod.passive);
    }
    Object.freeze(rod);
});
Object.freeze(RODS);
