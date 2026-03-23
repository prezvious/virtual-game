/**
 * BAIT DEFINITIONS
 * All bait types with their cost and luck bonus.
 */

const BAITS = [
    { id: 'worm', name: 'Worm', cost: 0, luck: 1 },
    { id: 'cricket', name: 'Cricket', cost: 150, luck: 7 },
    { id: 'glow_grub', name: 'Biolume Grub', cost: 800, luck: 10 },
    { id: 'minnow', name: 'Live Minnow', cost: 3000, luck: 18 },
    {
        id: 'ribbon_shiner',
        name: 'Ribbon Shiner',
        cost: 4200,
        luck: 12,
        passive: {
            summary: 'Mid-tier rods only. Faster bite pace and auto cycle, with a small weight-down bias.',
            midTierOnly: true,
            bestWithRod: 'currentline',
            offSynergyScale: 0.7,
            autoCycleMultiplier: 0.93,
            hookTimingMultiplier: 0.95,
            weightMultiplierMin: 0.94,
            weightMultiplierMax: 0.98
        }
    },
    {
        id: 'silt_shrimp',
        name: 'Silt Shrimp',
        cost: 4700,
        luck: 10,
        passive: {
            summary: 'Mid-tier rods only. Pushes average fish weight rolls up by around 10% to 12%.',
            midTierOnly: true,
            bestWithRod: 'trenchhaul',
            offSynergyScale: 0.72,
            weightMultiplierMin: 1.10,
            weightMultiplierMax: 1.12
        }
    },
    { id: 'flux_jelly', name: 'Flux Jelly', cost: 5000, luck: 25 },
    { id: 'spinner', name: 'Neon Spinner', cost: 5000, luck: 30 },
    {
        id: 'bright_fry',
        name: 'Bright Fry',
        cost: 5200,
        luck: 14,
        passive: {
            summary: 'Mid-tier rods only. Light Rare/Epic table boost, Mythic untouched.',
            midTierOnly: true,
            bestWithRod: 'needlepoint',
            offSynergyScale: 0.72,
            rarityBias: {
                rare: 1.1,
                epic: 1.14
            }
        }
    },
    { id: 'magic', name: 'Magic Paste', cost: 20000, luck: 60 },
    { id: 'void_shrimp', name: 'Abyssal Shrimp', cost: 25000, luck: 50 },
    { id: 'void_essence', name: 'Void Essence', cost: 50000, luck: 120 },
    { id: 'star_dust', name: 'Stardust Cluster', cost: 200000, luck: 90 },
    { id: 'singularity', name: 'Singularity Lure', cost: 2000000, luck: 200 }
];

const BAIT_BENCH_BREAKDOWN_BY_RARITY = {
    common: 'cut_bait',
    rare: 'cut_bait',
    epic: 'bait_oil',
    legendary: 'essence_bait'
};

const BAIT_BENCH_RESOURCES = [
    {
        id: 'cut_bait',
        name: 'Cut Bait',
        desc: 'Trimmed strips from common and rare fish. Core material for practical bench baits.'
    },
    {
        id: 'bait_oil',
        name: 'Bait Oil',
        desc: 'Concentrated oil from Epic fish. Used for selective table-bias blends.'
    },
    {
        id: 'essence_bait',
        name: 'Essence Bait',
        desc: 'Condensed Legendary essence. High-impact ingredient for premium bench bait.'
    }
];

const BAIT_BENCH_FAMILIES = [
    {
        id: 'cut_minnow',
        name: 'Cut Minnow',
        effectSummary: 'Slightly better bite frequency and better speed/auto-farm performance.',
        fishNames: [
            'Silver Dart',
            'Frost Minnow',
            'Moon Minnow',
            'Clear Minnow',
            'Gust Minnow',
            'Artifact Minnow',
            'Silkworm Minnow',
            'Ticking Tetra',
            'Pixel Prawn',
            'Moss Nibbler'
        ],
        craft: {
            makesCharges: 8,
            costs: {
                cut_bait: 6
            }
        },
        effects: {
            autoCycleMultiplier: 0.92,
            hookTimingMultiplier: 0.94
        }
    },
    {
        id: 'predator_strip',
        name: 'Predator Strip',
        effectSummary: 'Modest upward bias on fish weight rolls for heavier catches.',
        fishNames: [
            'Golden Trout',
            'Raging Trout',
            'Timeline Trout',
            'Polish Pike',
            'Emerald Reaver',
            'Holo-Halibut',
            'Permafrost Eel',
            'Tempest Striker',
            'Boiler Bass'
        ],
        craft: {
            makesCharges: 7,
            costs: {
                cut_bait: 9
            }
        },
        effects: {
            weightMultiplierMin: 1.06,
            weightMultiplierMax: 1.10
        }
    },
    {
        id: 'storm_oil',
        name: 'Storm Oil',
        effectSummary: 'Small boost to Rare and Epic table weights, with no Mythic bonus.',
        fishNames: [
            'Stormborn Marlin',
            'Paradox Pike',
            'Neon Needlefish',
            'Blizzard Shark',
            'Kimono Koi',
            'Resonance Behemoth',
            'Verdant Titan',
            'Architrave Beast',
            'Mainframe Marlin'
        ],
        craft: {
            makesCharges: 6,
            costs: {
                bait_oil: 4
            }
        },
        effects: {
            rarityBias: {
                rare: 1.10,
                epic: 1.14
            }
        }
    },
    {
        id: 'leviathan_essence',
        name: 'Leviathan Essence',
        effectSummary: 'Strong crafted blend: light Rare/Epic bias plus a small heavy-fish bias for a few casts.',
        fishNames: [
            'Leviathan Ray',
            'Stone Reaper',
            'Chronos Keeper',
            'Frozen Leviathan',
            'Midnight Gorger',
            'Zephyr King',
            'Citadel Warden',
            'Primordial Feeder',
            'Wavelength Whale'
        ],
        craft: {
            makesCharges: 4,
            costs: {
                essence_bait: 3,
                bait_oil: 2
            }
        },
        effects: {
            rarityBias: {
                rare: 1.08,
                epic: 1.12
            },
            weightMultiplierMin: 1.05,
            weightMultiplierMax: 1.09
        }
    }
];

// Re-sorting baits by cost
BAITS.sort((a, b) => a.cost - b.cost);
// Freeze static data to prevent console exploits
BAITS.forEach((bait) => {
    if (bait.passive && typeof bait.passive === 'object') {
        if (bait.passive.rarityBias && typeof bait.passive.rarityBias === 'object') {
            Object.freeze(bait.passive.rarityBias);
        }
        Object.freeze(bait.passive);
    }
    Object.freeze(bait);
});
Object.freeze(BAITS);

Object.freeze(BAIT_BENCH_BREAKDOWN_BY_RARITY);
BAIT_BENCH_RESOURCES.forEach((resource) => Object.freeze(resource));
Object.freeze(BAIT_BENCH_RESOURCES);
BAIT_BENCH_FAMILIES.forEach((family) => {
    if (Array.isArray(family.fishNames)) Object.freeze(family.fishNames);
    if (family.craft?.costs && typeof family.craft.costs === 'object') {
        Object.freeze(family.craft.costs);
    }
    if (family.craft && typeof family.craft === 'object') Object.freeze(family.craft);
    if (family.effects?.rarityBias && typeof family.effects.rarityBias === 'object') {
        Object.freeze(family.effects.rarityBias);
    }
    if (family.effects && typeof family.effects === 'object') Object.freeze(family.effects);
    Object.freeze(family);
});
Object.freeze(BAIT_BENCH_FAMILIES);
