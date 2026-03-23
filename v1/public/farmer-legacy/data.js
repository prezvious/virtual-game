// ==================== DATA DEFINITIONS ====================
const BASE_HOE_NAMES = [
    "Wooden Hoe",
    "Stone Hoe",
    "Lapis Hoe",
    "Gold Hoe",
    "Iron Hoe",
    "Diamond Hoe",
    "Netherite Hoe",
    "Special Hoe",
    "Emerald Hoe",
    "Obsidian Hoe",
    "Mythic Hoe",
    "Platinum Hoe",
    "Titanium Hoe",
    "God Hoe",
    "Dark Matter Hoe",
    "Quantum Hoe",
    "Singularity Hoe",
    "Plasma Cutter",
    "Solar Flare Hoe",
    "Nebula Harvester",
    "String Theory Hoe",
    "Antimatter Scythe",
    "Time-Weaver's Tool",
    "Reality Glitch",
    "The Developer's Cursor",
    "Admin Console",
    "The 'NULL' Pointer",
];

const NEW_HOE_NAMES = [
    "Copper-Tipped Hoe",
    "Tempered Steel Hoe",
    "Bone-Handle Hoe",
    "River Stone Hoe",
    "Hammered Iron Hoe",
    "Forged Bronze Hoe",
    "Charcoal Hoe",
    "Clay-Fired Hoe",
    "Tungsten Hoe",
    "Layered Alloy Hoe",
    "Polished Granite Hoe",
    "Chilled Iron Hoe",
    "Woven Fiber Hoe",
    "Dense Marble Hoe",
    "Sharpened Flint Hoe",
    "Double-Edged Hoe",
    "Hollow Reed Hoe",
    "Iron-Bone Composite Hoe",
    "Pressed Timber Hoe",
    "Slotted Titanium Hoe",
    "Midnight Steel Hoe",
    "Etched Copper Hoe",
    "Braided Alloy Hoe",
    "Refined Obsidian Hoe",
    "Core-Drilled Hoe",
    "Fractured Crystal Hoe",
    "Hollow Bone Hoe",
    "Silver-Inlaid Hoe",
    "Petrified Wood Hoe",
    "Magnetic Core Hoe",
    "Quartz-Tipped Hoe",
    "Pressure-Cast Hoe",
    "Layered Carbon Hoe",
    "Spun Glass Hoe",
    "Resonant Steel Hoe",
    "Tempered Jade Hoe",
    "Hollow Carbon Hoe",
    "Phase-Treated Hoe",
    "Crystalline Shaft Hoe",
    "Compressed Slate Hoe",
    "Wound Wire Hoe",
    "Cold-Pressed Hoe",
    "Stacked Plate Hoe",
    "Threaded Coil Hoe",
    "Engraved Basalt Hoe",
    "Sealed Chamber Hoe",
    "Helical Edge Hoe",
    "Solid Iridium Hoe",
    "Fracture-Set Hoe",
    "Deep-Forged Hoe",
    "Lattice Frame Hoe",
    "Orbital Ring Hoe",
    "Bound Mineral Hoe",
    "Vaulted Steel Hoe",
    "Micro-Etched Hoe",
    "Segmented Alloy Hoe",
    "Pulse-Hardened Hoe",
    "Grooved Titanium Hoe",
    "Cross-Hatched Hoe",
    "Tempered Rhodium Hoe",
    "Riveted Plate Hoe",
    "Vacuum-Cast Hoe",
    "Spindle-Core Hoe",
    "Arc-Welded Hoe",
    "Dense Iridium Hoe",
    "Tensioned Wire Hoe",
    "Annealed Edge Hoe",
    "Coiled Spring Hoe",
    "Hollow Sphere Hoe",
    "Differential Blade Hoe",
    "Sintered Carbide Hoe",
    "Stabilized Core Hoe",
    "Tapered Alloy Hoe",
    "Pressure-Sintered Hoe",
    "Fluted Edge Hoe",
    "Radial Groove Hoe",
    "Laminated Steel Hoe",
    "Torsion-Wound Hoe",
    "Milled Plate Hoe",
    "Impact-Forged Hoe",
    "Hardened Zirconium Hoe",
    "Composite Lattice Hoe",
    "Gradient Alloy Hoe",
    "Precision-Ground Hoe",
    "Stiff-Spine Hoe",
    "Friction-Welded Hoe",
    "Hollow Tungsten Hoe",
    "Layered Platinum Hoe",
    "Core-Spun Hoe",
    "Micro-Alloy Hoe",
    "Differential Mesh Hoe",
    "Woven Carbide Hoe",
    "Suspended Core Hoe",
    "Reinforced Lattice Hoe",
    "Stratified Steel Hoe",
    "Dense Osmium Hoe",
    "Coaxial Blade Hoe",
    "Fractured Osmium Hoe",
    "Crystallized Iron Hoe",
    "Absolute Forged Hoe",
];

const HOE_NAMES = [...BASE_HOE_NAMES, ...NEW_HOE_NAMES];

// Rebalance knobs: edit anchor values to reshape the full progression curve.
const HOE_MULTIPLIER_ANCHORS = [
    { index: 0, value: 1 },
    { index: 3, value: 2.6 },
    { index: 7, value: 5.8 },
    { index: 11, value: 14 },
    { index: 15, value: 52 },
    { index: 19, value: 260 },
    { index: 21, value: 1200 },
    { index: 23, value: 6000 },
    { index: 26, value: 60000 },
    { index: 40, value: 900000 },
    { index: 60, value: 12000000 },
    { index: 80, value: 135000000 },
    { index: 100, value: 1300000000 },
    { index: 126, value: 6200000000 },
];

const HOE_COST_ANCHORS = [
    { index: 0, value: 0 },
    { index: 1, value: 500 },
    { index: 5, value: 5000 },
    { index: 11, value: 120000 },
    { index: 15, value: 4500000 },
    { index: 19, value: 250000000 },
    { index: 21, value: 25000000000 },
    { index: 23, value: 850000000000 },
    { index: 26, value: 8000000000000 },
    { index: 40, value: 30000000000000 },
    { index: 60, value: 800000000000000 },
    { index: 80, value: 15000000000000000 },
    { index: 100, value: 250000000000000000 },
    { index: 126, value: 12000000000000000000 },
];

function roundToSignificant(value, digits = 3) {
    if (value === 0) return 0;
    const abs = Math.abs(value);
    const exponent = Math.floor(Math.log10(abs));
    const factor = Math.pow(10, exponent - digits + 1);
    return Math.round(value / factor) * factor;
}

function getProgressionStep(previous) {
    if (previous < 10) return 0.1;
    if (previous < 100) return 0.5;
    if (previous < 1000) return 1;
    return Math.max(1, roundToSignificant(previous * 0.01, 1));
}

function buildAnchoredProgression(length, anchors, roundFn) {
    const sortedAnchors = [...anchors].sort((a, b) => a.index - b.index);
    const firstAnchor = sortedAnchors[0];
    const lastAnchor = sortedAnchors[sortedAnchors.length - 1];

    if (!firstAnchor || !lastAnchor || firstAnchor.index !== 0 || lastAnchor.index !== length - 1) {
        throw new Error("Progression anchors must start at index 0 and end at the final index.");
    }

    const values = new Array(length).fill(0);

    for (let segment = 0; segment < sortedAnchors.length - 1; segment++) {
        const start = sortedAnchors[segment];
        const end = sortedAnchors[segment + 1];
        const span = end.index - start.index;

        for (let offset = 0; offset <= span; offset++) {
            const index = start.index + offset;
            if (offset === 0 && segment > 0) continue;

            const t = span === 0 ? 0 : offset / span;
            let value;
            if (start.value > 0 && end.value > 0) {
                value = Math.exp(Math.log(start.value) + (Math.log(end.value) - Math.log(start.value)) * t);
            } else {
                value = start.value + ((end.value - start.value) * t);
            }
            values[index] = roundFn(value);
        }
    }

    for (let i = 1; i < values.length; i++) {
        if (values[i] <= values[i - 1]) {
            values[i] = roundFn(values[i - 1] + getProgressionStep(values[i - 1]));
        }
    }

    return values;
}

const roundHoeMultiplier = (value) => {
    if (value < 10) return Number(value.toFixed(2));
    if (value < 100) return Number(value.toFixed(1));
    if (value < 1000) return Math.round(value);
    return Math.max(1000, roundToSignificant(value, 4));
};

const roundHoeCost = (value) => {
    if (value <= 0) return 0;
    return Math.max(1, Math.round(roundToSignificant(value, 3)));
};

const HOE_MULTIPLIERS = buildAnchoredProgression(HOE_NAMES.length, HOE_MULTIPLIER_ANCHORS, roundHoeMultiplier);
const HOE_COSTS = buildAnchoredProgression(HOE_NAMES.length, HOE_COST_ANCHORS, roundHoeCost);

const HOES = HOE_NAMES.map((name, index) => ({
    name,
    multiplier: HOE_MULTIPLIERS[index],
    cost: HOE_COSTS[index]
}));

const BASE_HOES = HOES.slice(0, BASE_HOE_NAMES.length);
const NEW_HOES = HOES.slice(BASE_HOE_NAMES.length);

// List of Plant Rarity Levels:
// 01  common
// 02  uncommon
// 03  rare
// 04  epic
// 05  legendary
// 06  mythic
// 07  ancient
// 08  celestial
// 09  eldritch
// 10  eternal
// 11  divine
// 12  cosmic
// 13  primordial
// 14  singularity
// 15  null
const PLANT_RARITY_LEVELS = [
    "common",
    "uncommon",
    "rare",
    "epic",
    "legendary",
    "mythic",
    "ancient",
    "celestial",
    "eldritch",
    "eternal",
    "divine",
    "cosmic",
    "primordial",
    "singularity",
    "null"
];

const NEW_PLANTS = [

    // 01 COMMON - range: 5-15 | minHoe: 0
    { name: "Cabbage",       price: 6,   rarity: "common", minHoe: 0 },
    { name: "Zucchini",      price: 11,  rarity: "common", minHoe: 0 },
    { name: "Turnip",        price: 7,   rarity: "common", minHoe: 0 },
    { name: "Garlic",        price: 13,  rarity: "common", minHoe: 0 },
    { name: "Leek",          price: 9,   rarity: "common", minHoe: 0 },
    { name: "Cauliflower",   price: 14,  rarity: "common", minHoe: 0 },
    { name: "Parsnip",       price: 8,   rarity: "common", minHoe: 0 },
    { name: "Celery",        price: 12,  rarity: "common", minHoe: 0 },
    { name: "Asparagus",     price: 5,   rarity: "common", minHoe: 0 },
    { name: "Lemongrass",    price: 10,  rarity: "common", minHoe: 0 },
    { name: "Clove",         price: 15,  rarity: "common", minHoe: 0 },
    { name: "Green Bean",    price: 7,   rarity: "common", minHoe: 0 },
    { name: "White Onion",   price: 11,  rarity: "common", minHoe: 0 },
    { name: "Radish",        price: 6,   rarity: "common", minHoe: 0 },
    { name: "Artichoke",     price: 13,  rarity: "common", minHoe: 0 },

    // 02 UNCOMMON - range: 17-43 | minHoe: 1-2
    { name: "Honeycrisp Apple", price: 23,  rarity: "uncommon", minHoe: 1 },
    { name: "Purple Yam",       price: 37,  rarity: "uncommon", minHoe: 1 },
    { name: "Cherry Tomato",    price: 19,  rarity: "uncommon", minHoe: 1 },
    { name: "Snow Pea",         price: 41,  rarity: "uncommon", minHoe: 1 },
    { name: "Blood Orange",     price: 28,  rarity: "uncommon", minHoe: 1 },
    { name: "Blue Corn",        price: 17,  rarity: "uncommon", minHoe: 1 },
    { name: "Starfruit",        price: 34,  rarity: "uncommon", minHoe: 1 },
    { name: "Pomegranate",      price: 22,  rarity: "uncommon", minHoe: 1 },
    { name: "Rhubarb",          price: 43,  rarity: "uncommon", minHoe: 2 },
    { name: "Bok Choy",         price: 31,  rarity: "uncommon", minHoe: 2 },
    { name: "Taro Root",        price: 18,  rarity: "uncommon", minHoe: 2 },
    { name: "Tiger Nut",        price: 39,  rarity: "uncommon", minHoe: 2 },
    { name: "Persimmon",        price: 26,  rarity: "uncommon", minHoe: 2 },
    { name: "Fig",              price: 21,  rarity: "uncommon", minHoe: 2 },
    { name: "Yellow Squash",    price: 33,  rarity: "uncommon", minHoe: 2 },

    // 03 RARE - range: 48-117 | minHoe: 2-4
    { name: "Sapphire Grape",    price: 73,   rarity: "rare", minHoe: 2 },
    { name: "Frost Mint",        price: 91,   rarity: "rare", minHoe: 2 },
    { name: "Ghost Pepper",      price: 54,   rarity: "rare", minHoe: 2 },
    { name: "Golden Beet",       price: 117,  rarity: "rare", minHoe: 3 },
    { name: "Crystal Rose",      price: 62,   rarity: "rare", minHoe: 3 },
    { name: "Ironcap Mushroom",  price: 84,   rarity: "rare", minHoe: 3 },
    { name: "Silver Leaf",       price: 48,   rarity: "rare", minHoe: 3 },
    { name: "Azure Kelp",        price: 107,  rarity: "rare", minHoe: 3 },
    { name: "Crimson Lotus",     price: 69,   rarity: "rare", minHoe: 3 },
    { name: "Ember Spice",       price: 96,   rarity: "rare", minHoe: 4 },
    { name: "Twilight Plum",     price: 51,   rarity: "rare", minHoe: 4 },
    { name: "Obsidian Cacao",    price: 113,  rarity: "rare", minHoe: 4 },
    { name: "Sun-Kissed Melon",  price: 77,   rarity: "rare", minHoe: 4 },
    { name: "Coral Berry",       price: 58,   rarity: "rare", minHoe: 4 },
    { name: "Silk Vine",         price: 88,   rarity: "rare", minHoe: 4 },

    // 04 EPIC - range: 124-318 | minHoe: 4-6
    { name: "Lava Melon",          price: 241,  rarity: "epic", minHoe: 4 },
    { name: "Whispering Reed",     price: 163,  rarity: "epic", minHoe: 5 },
    { name: "Sunsilk Corn",        price: 307,  rarity: "epic", minHoe: 5 },
    { name: "Thunderbloom",        price: 189,  rarity: "epic", minHoe: 5 },
    { name: "Glacier Berry",       price: 124,  rarity: "epic", minHoe: 5 },
    { name: "Venomous Pitcher",    price: 274,  rarity: "epic", minHoe: 5 },
    { name: "Shimmering Fig",      price: 147,  rarity: "epic", minHoe: 5 },
    { name: "Wind-Dancer Grass",   price: 318,  rarity: "epic", minHoe: 6 },
    { name: "Starflower",          price: 211,  rarity: "epic", minHoe: 6 },
    { name: "Bloodmoon Pumpkin",   price: 136,  rarity: "epic", minHoe: 6 },
    { name: "Magma Pod",           price: 258,  rarity: "epic", minHoe: 6 },
    { name: "Nightshade Orchid",   price: 178,  rarity: "epic", minHoe: 6 },
    { name: "Echoing Spore",       price: 293,  rarity: "epic", minHoe: 6 },
    { name: "Mirage Pear",         price: 154,  rarity: "epic", minHoe: 6 },
    { name: "Storm Kelp",          price: 226,  rarity: "epic", minHoe: 6 },

    // 05 LEGENDARY - range: 341-893 | minHoe: 7-9
    { name: "Phoenix Sprout",        price: 583,  rarity: "legendary", minHoe: 7 },
    { name: "Titan Root",            price: 412,  rarity: "legendary", minHoe: 7 },
    { name: "Dragon's Breath Chili", price: 761,  rarity: "legendary", minHoe: 7 },
    { name: "Midas Wheat",           price: 341,  rarity: "legendary", minHoe: 7 },
    { name: "Siren's Kelp",          price: 847,  rarity: "legendary", minHoe: 8 },
    { name: "Kraken Vine",           price: 476,  rarity: "legendary", minHoe: 8 },
    { name: "Gorgon's Basil",        price: 629,  rarity: "legendary", minHoe: 8 },
    { name: "Pegasus Grass",         price: 374,  rarity: "legendary", minHoe: 8 },
    { name: "Chimera Fruit",         price: 718,  rarity: "legendary", minHoe: 8 },
    { name: "Nectar Blossom",        price: 893,  rarity: "legendary", minHoe: 9 },
    { name: "Yeti's Frost-Bite",     price: 512,  rarity: "legendary", minHoe: 9 },
    { name: "Basilisk Scale Berry",  price: 667,  rarity: "legendary", minHoe: 9 },
    { name: "Unicorn Horn Root",     price: 438,  rarity: "legendary", minHoe: 9 },
    { name: "Griffin's Beak Seed",   price: 791,  rarity: "legendary", minHoe: 9 },
    { name: "Leviathan Core",        price: 554,  rarity: "legendary", minHoe: 9 },

    // 06 MYTHIC - range: 947-2483 | minHoe: 10-11
    { name: "Spirit Blossom",      price: 1673,  rarity: "mythic", minHoe: 10 },
    { name: "Fairy Tear Dew",      price: 947,   rarity: "mythic", minHoe: 10 },
    { name: "World Tree Acorn",    price: 2217,  rarity: "mythic", minHoe: 10 },
    { name: "Yggdrasil Bark",      price: 1384,  rarity: "mythic", minHoe: 10 },
    { name: "Valhalla Berry",      price: 2483,  rarity: "mythic", minHoe: 10 },
    { name: "Nirvana Lotus",       price: 1091,  rarity: "mythic", minHoe: 10 },
    { name: "Styx Lily",           price: 1856,  rarity: "mythic", minHoe: 11 },
    { name: "Elysian Grass",       price: 1243,  rarity: "mythic", minHoe: 11 },
    { name: "Ambrosia Apple",      price: 2074,  rarity: "mythic", minHoe: 11 },
    { name: "Nymph's Delight",     price: 1518,  rarity: "mythic", minHoe: 11 },
    { name: "Dryad's Heart",       price: 978,   rarity: "mythic", minHoe: 11 },
    { name: "Banshee Orchid",      price: 2341,  rarity: "mythic", minHoe: 11 },
    { name: "Will-o'-Wisp Bud",    price: 1127,  rarity: "mythic", minHoe: 11 },
    { name: "Muse's Inspiration",  price: 1762,  rarity: "mythic", minHoe: 11 },
    { name: "Pandora's Seed",      price: 2089,  rarity: "mythic", minHoe: 11 },

    // 07 ANCIENT - range: 2614-7183 | minHoe: 12-13
    { name: "Petrified Spore",        price: 4871,  rarity: "ancient", minHoe: 12 },
    { name: "First-Era Fern",         price: 2614,  rarity: "ancient", minHoe: 12 },
    { name: "Amber Bark",             price: 6347,  rarity: "ancient", minHoe: 12 },
    { name: "Mammoth Tusk Root",      price: 3782,  rarity: "ancient", minHoe: 12 },
    { name: "Fossilized Frond",       price: 7183,  rarity: "ancient", minHoe: 12 },
    { name: "Jurassic Amber",         price: 2943,  rarity: "ancient", minHoe: 12 },
    { name: "Dawn Moss",              price: 5614,  rarity: "ancient", minHoe: 13 },
    { name: "Proterozoic Algae",      price: 3217,  rarity: "ancient", minHoe: 13 },
    { name: "Stone-Fruit",            price: 6728,  rarity: "ancient", minHoe: 13 },
    { name: "Cave-Painter's Pigment", price: 4193,  rarity: "ancient", minHoe: 13 },
    { name: "Saber-Tooth Thorn",      price: 2871,  rarity: "ancient", minHoe: 13 },
    { name: "Neanderthal Nut",        price: 5439,  rarity: "ancient", minHoe: 13 },
    { name: "Ice-Age Lichen",         price: 7041,  rarity: "ancient", minHoe: 13 },
    { name: "Paleo-Plum",             price: 3564,  rarity: "ancient", minHoe: 13 },
    { name: "Forgotten Sprout",       price: 4807,  rarity: "ancient", minHoe: 13 },

    // 08 CELESTIAL - range: 7841-21673 | minHoe: 14-15
    { name: "Comet Dust",           price: 14382,  rarity: "celestial", minHoe: 14 },
    { name: "Starfall Berry",       price: 7841,   rarity: "celestial", minHoe: 14 },
    { name: "Lunar Lotus",          price: 19247,  rarity: "celestial", minHoe: 14 },
    { name: "Solar Flare Chili",    price: 11563,  rarity: "celestial", minHoe: 14 },
    { name: "Asteroid Bean",        price: 8374,   rarity: "celestial", minHoe: 14 },
    { name: "Milky Way Gourd",      price: 21673,  rarity: "celestial", minHoe: 14 },
    { name: "Constellation Vine",   price: 16091,  rarity: "celestial", minHoe: 15 },
    { name: "Shooting Star-Fruit",  price: 9618,   rarity: "celestial", minHoe: 15 },
    { name: "Aurora Bloom",         price: 13274,  rarity: "celestial", minHoe: 15 },
    { name: "Meteorite Mushroom",   price: 18432,  rarity: "celestial", minHoe: 15 },
    { name: "Orbiting Olive",       price: 7993,   rarity: "celestial", minHoe: 15 },
    { name: "Zodiac Zucchini",      price: 20814,  rarity: "celestial", minHoe: 15 },
    { name: "Eclipse Eggplant",     price: 12047,  rarity: "celestial", minHoe: 15 },
    { name: "Supermoon Strawberry", price: 17639,  rarity: "celestial", minHoe: 15 },
    { name: "Galaxy Grape",         price: 10283,  rarity: "celestial", minHoe: 15 },

    // 09 ELDRITCH - range: 23814-61273 | minHoe: 16-17
    { name: "Whispering Eye-Stalk",     price: 41837,  rarity: "eldritch", minHoe: 16 },
    { name: "Abyssal Kelp",             price: 23814,  rarity: "eldritch", minHoe: 16 },
    { name: "Madman's Gourd",           price: 57492,  rarity: "eldritch", minHoe: 16 },
    { name: "Tentacled Turnip",         price: 31658,  rarity: "eldritch", minHoe: 16 },
    { name: "Cthulhu's Cabbage",        price: 48374,  rarity: "eldritch", minHoe: 16 },
    { name: "Non-Euclidean Carrot",     price: 26193,  rarity: "eldritch", minHoe: 16 },
    { name: "Void-Watcher's Vine",      price: 61273,  rarity: "eldritch", minHoe: 17 },
    { name: "Deep-One's Delight",       price: 37841,  rarity: "eldritch", minHoe: 17 },
    { name: "R'lyeh Radish",            price: 24917,  rarity: "eldritch", minHoe: 17 },
    { name: "Madness Spore",            price: 53618,  rarity: "eldritch", minHoe: 17 },
    { name: "Shoggoth Slime",           price: 29473,  rarity: "eldritch", minHoe: 17 },
    { name: "Crawling Chaos Corn",      price: 44291,  rarity: "eldritch", minHoe: 17 },
    { name: "Unnamable Onion",          price: 34758,  rarity: "eldritch", minHoe: 17 },
    { name: "Color-Out-Of-Space Berry", price: 59014,  rarity: "eldritch", minHoe: 17 },
    { name: "Innsmouth Herb",           price: 27346,  rarity: "eldritch", minHoe: 17 },

    // 10 ETERNAL - range: 67483-184729 | minHoe: 18-19
    { name: "Timeless Blossom",   price: 112847,  rarity: "eternal", minHoe: 18 },
    { name: "Infinity Sprout",    price: 67483,   rarity: "eternal", minHoe: 18 },
    { name: "Chrono-Vine",        price: 158362,  rarity: "eternal", minHoe: 18 },
    { name: "Undying Acorn",      price: 84917,   rarity: "eternal", minHoe: 18 },
    { name: "Everlasting Ember",  price: 143758,  rarity: "eternal", minHoe: 18 },
    { name: "Ouroboros Root",     price: 73291,   rarity: "eternal", minHoe: 18 },
    { name: "Perma-Frost Peach",  price: 184729,  rarity: "eternal", minHoe: 19 },
    { name: "Immortal Iris",      price: 96143,   rarity: "eternal", minHoe: 19 },
    { name: "Endless Echo",       price: 127584,  rarity: "eternal", minHoe: 19 },
    { name: "Hourglass Herb",     price: 71836,   rarity: "eternal", minHoe: 19 },
    { name: "Millennium Melon",   price: 163491,  rarity: "eternal", minHoe: 19 },
    { name: "Eon Eggplant",       price: 89274,   rarity: "eternal", minHoe: 19 },
    { name: "Ageless Apple",      price: 137628,  rarity: "eternal", minHoe: 19 },
    { name: "Forever Fig",        price: 104857,  rarity: "eternal", minHoe: 19 },
    { name: "Time-Loop Tomato",   price: 178364,  rarity: "eternal", minHoe: 19 },

    // 11 DIVINE - range: 193847-548291 | minHoe: 20-21
    { name: "Ambrosia Bean",      price: 348291,  rarity: "divine", minHoe: 20 },
    { name: "Seraphim Petal",     price: 193847,  rarity: "divine", minHoe: 20 },
    { name: "God's Tear",         price: 471836,  rarity: "divine", minHoe: 20 },
    { name: "Archangel's Halo",   price: 264173,  rarity: "divine", minHoe: 20 },
    { name: "Holy Lily",          price: 517294,  rarity: "divine", minHoe: 20 },
    { name: "Eden's Apple",       price: 214638,  rarity: "divine", minHoe: 20 },
    { name: "Blessed Herb",       price: 392847,  rarity: "divine", minHoe: 21 },
    { name: "Retribution Pepper", price: 237594,  rarity: "divine", minHoe: 21 },
    { name: "Miracle Mustard",    price: 548291,  rarity: "divine", minHoe: 21 },
    { name: "Prophet's Peach",    price: 304817,  rarity: "divine", minHoe: 21 },
    { name: "Sacred Papyrus",     price: 427563,  rarity: "divine", minHoe: 21 },
    { name: "Benediction Berry",  price: 281947,  rarity: "divine", minHoe: 21 },
    { name: "Heavenly Chive",     price: 196384,  rarity: "divine", minHoe: 21 },
    { name: "Celestial Choir",    price: 463817,  rarity: "divine", minHoe: 21 },
    { name: "Omnipotent Onion",   price: 318472,  rarity: "divine", minHoe: 21 },

    // 12 COSMIC - range: 587463-1637284 | minHoe: 22-23
    { name: "Quasar Citrus",       price: 1247836,  rarity: "cosmic", minHoe: 22 },
    { name: "Supernova Plum",      price: 587463,   rarity: "cosmic", minHoe: 22 },
    { name: "Pulsar Pod",          price: 1483927,  rarity: "cosmic", minHoe: 22 },
    { name: "Dark Matter Melon",   price: 784291,   rarity: "cosmic", minHoe: 22 },
    { name: "Nebula Nectarine",    price: 1073648,  rarity: "cosmic", minHoe: 22 },
    { name: "Event Horizon Berry", price: 637184,   rarity: "cosmic", minHoe: 22 },
    { name: "Gravity Pumpkin",     price: 1637284,  rarity: "cosmic", minHoe: 23 },
    { name: "Interstellar Ivy",    price: 914873,   rarity: "cosmic", minHoe: 23 },
    { name: "Wormhole Wheat",      price: 1382947,  rarity: "cosmic", minHoe: 23 },
    { name: "Tachyon Tomato",      price: 712638,   rarity: "cosmic", minHoe: 23 },
    { name: "Cosmic Dust Carrot",  price: 1194827,  rarity: "cosmic", minHoe: 23 },
    { name: "Anti-Matter Apple",   price: 843917,   rarity: "cosmic", minHoe: 23 },
    { name: "Red Giant Radish",    price: 593748,   rarity: "cosmic", minHoe: 23 },
    { name: "White Dwarf Walnut",  price: 1528364,  rarity: "cosmic", minHoe: 23 },
    { name: "Background Bean",     price: 974182,   rarity: "cosmic", minHoe: 23 },

    // 13 PRIMORDIAL - range: 1738492-4927361 | minHoe: 24-25
    { name: "Genesis Seed",          price: 3284917,  rarity: "primordial", minHoe: 24 },
    { name: "Chaos Root",            price: 1738492,  rarity: "primordial", minHoe: 24 },
    { name: "First-Spark Cabbage",   price: 4193847,  rarity: "primordial", minHoe: 24 },
    { name: "Big Bang Berry",        price: 2374816,  rarity: "primordial", minHoe: 24 },
    { name: "Elemental Earth",       price: 3847291,  rarity: "primordial", minHoe: 24 },
    { name: "Raw Fire Pod",          price: 1924738,  rarity: "primordial", minHoe: 24 },
    { name: "Unshaped Water Kelp",   price: 4627183,  rarity: "primordial", minHoe: 25 },
    { name: "Howling Wind Reed",     price: 2847361,  rarity: "primordial", minHoe: 25 },
    { name: "Void-Before-Time Vine", price: 4927361,  rarity: "primordial", minHoe: 25 },
    { name: "The First Spore",       price: 2193847,  rarity: "primordial", minHoe: 25 },
    { name: "Alpha Adamant",         price: 3617284,  rarity: "primordial", minHoe: 25 },
    { name: "Ooze-Plant",            price: 1847362,  rarity: "primordial", minHoe: 25 },
    { name: "Spark of Life",         price: 4284917,  rarity: "primordial", minHoe: 25 },
    { name: "Base Reality Root",     price: 2638471,  rarity: "primordial", minHoe: 25 },
    { name: "Origin Orange",         price: 3974182,  rarity: "primordial", minHoe: 25 },

    // 14 SINGULARITY - range: 5284917-15847362 | minHoe: 25-26
    { name: "Horizon Peach",            price: 9473861,   rarity: "singularity", minHoe: 25 },
    { name: "Graviton Grape",           price: 5284917,   rarity: "singularity", minHoe: 25 },
    { name: "Schwarzschild Fig",        price: 13847291,  rarity: "singularity", minHoe: 25 },
    { name: "Spaghettification Squash", price: 7382941,   rarity: "singularity", minHoe: 25 },
    { name: "Infinite Density Plum",    price: 11294738,  rarity: "singularity", minHoe: 25 },
    { name: "Time-Dilation Tomato",     price: 6174382,   rarity: "singularity", minHoe: 26 },
    { name: "Hawking Radish",           price: 14738291,  rarity: "singularity", minHoe: 26 },
    { name: "Wormhole Watermelon",      price: 8473619,   rarity: "singularity", minHoe: 26 },
    { name: "Entangled Eggplant",       price: 5847362,   rarity: "singularity", minHoe: 26 },
    { name: "Absolute Zero Zucchini",   price: 12738491,  rarity: "singularity", minHoe: 26 },
    { name: "Light-Bending Berry",      price: 7193847,   rarity: "singularity", minHoe: 26 },
    { name: "Singularity Spore",        price: 15847362,  rarity: "singularity", minHoe: 26 },
    { name: "Collapsed Star-Fruit",     price: 9284731,   rarity: "singularity", minHoe: 26 },
    { name: "Macro-Gravity Melon",      price: 6473819,   rarity: "singularity", minHoe: 26 },
    { name: "Point of No Return",       price: 13284917,  rarity: "singularity", minHoe: 26 },

    // 15 NULL - range: 17384729-53847362 | minHoe: 26
    { name: "MissingNo Berry",           price: 34817293,  rarity: "null", minHoe: 26 },
    { name: "undefined_crop",            price: 17384729,  rarity: "null", minHoe: 26 },
    { name: "The Void Shard",            price: 48273641,  rarity: "null", minHoe: 26 },
    { name: "Zero-State Spore",          price: 23847162,  rarity: "null", minHoe: 26 },
    { name: "NaN Banana",                price: 53847362,  rarity: "null", minHoe: 26 },
    { name: "Syntax Error Sprout",       price: 19283746,  rarity: "null", minHoe: 26 },
    { name: "404 Fruit Not Found",       price: 41738291,  rarity: "null", minHoe: 26 },
    { name: "Segmentation Seed",         price: 27364819,  rarity: "null", minHoe: 26 },
    { name: "Null Pointer Plum",         price: 18473628,  rarity: "null", minHoe: 26 },
    { name: "Glitched Gourd",            price: 46283917,  rarity: "null", minHoe: 26 },
    { name: "[REDACTED] Root",           price: 32847163,  rarity: "null", minHoe: 26 },
    { name: "Memory Leak Melon",         price: 21947382,  rarity: "null", minHoe: 26 },
    { name: "Binary Bean",               price: 38174926,  rarity: "null", minHoe: 26 },
    { name: "Stack Overflow Strawberry", price: 51283746,  rarity: "null", minHoe: 26 },
    { name: "End of Execution",          price: 29473816,  rarity: "null", minHoe: 26 }
];

const PLANTS = NEW_PLANTS;

const BASE_FERTILIZERS = [
    { name: "Mud", bonus: 1, cost: 50 },
    { name: "Soil", bonus: 2, cost: 100 },
    { name: "Compost", bonus: 3, cost: 200 },
    { name: "Manure", bonus: 5, cost: 300 },
    { name: "Organic", bonus: 8, cost: 500 },
    { name: "Bio", bonus: 10, cost: 800 },
    { name: "Vermicompost", bonus: 12, cost: 1000 },
    { name: "Liquid", bonus: 15, cost: 1200 },
    { name: "Chemical", bonus: 30, cost: 1500 },
    { name: "Superphosphate", bonus: 40, cost: 1800 },
    { name: "Growth Serum", bonus: 100, cost: 5000 },
    { name: "Magic Dust", bonus: 250, cost: 15000 },
    { name: "Time Warp", bonus: 1000, cost: 50000 },
    { name: "Radioactive Waste", bonus: 2500, cost: 150000 },
    { name: "Nanobots Swarm", bonus: 6000, cost: 450000 },
    { name: "Phoenix Ash", bonus: 15000, cost: 1200000 },
    { name: "Dragon's Breath", bonus: 40000, cost: 3500000 },
    { name: "Liquid Luck", bonus: 100000, cost: 15000000 },
    { name: "Dark Energy", bonus: 250000, cost: 75000000 },
    { name: "Condensed Star", bonus: 777777, cost: 350000000 },
    { name: "Source Code Leak", bonus: 2500000, cost: 1500000000 },
    { name: "Cheat Engine", bonus: 10000000, cost: 8000000000 },
    { name: "Game Master's Blessing", bonus: 50000000, cost: 50000000000 }
];
const NEW_FERTILIZERS = [
    { name: "Kelp Meal",              bonus: 68,        cost: 1847 },
    { name: "Wood Ash",               bonus: 42,        cost: 1293 },
    { name: "Bone Char",              bonus: 57,        cost: 1638 },
    { name: "Fish Emulsion",          bonus: 83,        cost: 2174 },
    { name: "Rice Husk",              bonus: 35,        cost: 963 },
    { name: "Feather Meal",           bonus: 91,        cost: 2483 },
    { name: "Blood Flour",            bonus: 74,        cost: 1927 },
    { name: "Peat Blend",             bonus: 118,       cost: 3174 },
    { name: "Cottonseed Meal",        bonus: 63,        cost: 1748 },
    { name: "Mineral Grit",           bonus: 147,       cost: 4283 },
    { name: "Volcanic Pumice",        bonus: 193,       cost: 5847 },
    { name: "Enzyme Activator",       bonus: 264,       cost: 7384 },
    { name: "Cold Compost",           bonus: 138,       cost: 3917 },
    { name: "Trace Mineral Mix",      bonus: 317,       cost: 9173 },
    { name: "Pressed Algae",          bonus: 218,       cost: 6284 },
    { name: "Rooted Bark Extract",    bonus: 384,       cost: 11473 },
    { name: "Sulfur Dust",            bonus: 273,       cost: 7938 },
    { name: "Molasses Drench",        bonus: 461,       cost: 13847 },
    { name: "Microbe Inoculant",      bonus: 342,       cost: 9874 },
    { name: "Silica Powder",          bonus: 538,       cost: 16284 },
    { name: "Humic Acid",             bonus: 417,       cost: 12473 },
    { name: "Fulvic Blend",           bonus: 693,       cost: 20384 },
    { name: "Worm Castings",          bonus: 512,       cost: 15473 },
    { name: "Biochar Pellet",         bonus: 847,       cost: 24917 },
    { name: "Liquid Seaweed",         bonus: 634,       cost: 18473 },
    { name: "Calcium Nitrate",        bonus: 1038,      cost: 30174 },
    { name: "Fermented Bran",         bonus: 783,       cost: 22847 },
    { name: "Mycorrhizal Powder",     bonus: 1274,      cost: 37384 },
    { name: "Potassium Sulfate",      bonus: 947,       cost: 27638 },
    { name: "Root Stimulant",         bonus: 1583,      cost: 46173 },
    { name: "Gibberellin Extract",    bonus: 1184,      cost: 34729 },
    { name: "Cytokinin Drip",         bonus: 1938,      cost: 57384 },
    { name: "Chelated Iron Mix",      bonus: 1427,      cost: 41847 },
    { name: "Auxin Spray",            bonus: 2374,      cost: 69173 },
    { name: "Nitrogen Capsule",       bonus: 1783,      cost: 52384 },
    { name: "Phosphorus Gel",         bonus: 2917,      cost: 85473 },
    { name: "Mineral Suspension",     bonus: 2183,      cost: 63847 },
    { name: "Ionic Booster",          bonus: 3584,      cost: 104738 },
    { name: "Soil Enzyme Pack",       bonus: 2748,      cost: 80173 },
    { name: "Growth Catalyst",        bonus: 4293,      cost: 125847 },
    { name: "Carbon Polymer Feed",    bonus: 3417,      cost: 99384 },
    { name: "Metabolic Primer",       bonus: 5273,      cost: 153847 },
    { name: "Bacterial Inoculant",    bonus: 4183,      cost: 121473 },
    { name: "Peptide Fertilizer",     bonus: 6384,      cost: 186173 },
    { name: "Amino Acid Complex",     bonus: 5047,      cost: 147382 },
    { name: "Protein Hydrolysate",    bonus: 7738,      cost: 226847 },
    { name: "Trichoderma Blend",      bonus: 6193,      cost: 180473 },
    { name: "Proton-Rich Mineral",    bonus: 9384,      cost: 273847 },
    { name: "Organic Acid Drench",    bonus: 7438,      cost: 217384 },
    { name: "Quantum Mineral",        bonus: 11473,     cost: 334817 },
    { name: "Ion Exchange Pellet",    bonus: 9127,      cost: 266384 },
    { name: "Cellular Activator",     bonus: 13847,     cost: 404173 },
    { name: "Membrane Feed",          bonus: 11284,     cost: 328473 },
    { name: "Photon Soil Charge",     bonus: 16738,     cost: 488291 },
    { name: "Polymer Root Wrap",      bonus: 13947,     cost: 407384 },
    { name: "Enzymatic Catalyst",     bonus: 20384,     cost: 594738 },
    { name: "Density Feed",           bonus: 17293,     cost: 504817 },
    { name: "Synthetic Humus",        bonus: 24917,     cost: 727384 },
    { name: "Structured Water Feed",  bonus: 21384,     cost: 624173 },
    { name: "Particle Suspension",    bonus: 30473,     cost: 889274 },
    { name: "Pressure-Dissolved Feed",bonus: 26184,     cost: 763847 },
    { name: "Resonant Mineral",       bonus: 37284,     cost: 1083947 },
    { name: "Gradient Soil Pack",     bonus: 31847,     cost: 929384 },
    { name: "Electromagnetic Drip",   bonus: 45738,     cost: 1334817 },
    { name: "Composite Mineral",      bonus: 38293,     cost: 1117384 },
    { name: "Phase Soil Activator",   bonus: 56174,     cost: 1638291 },
    { name: "Lattice Nutrient",       bonus: 47382,     cost: 1382174 },
    { name: "Deep Core Extract",      bonus: 68473,     cost: 1994738 },
    { name: "Fused Mineral Blend",    bonus: 57839,     cost: 1687384 },
    { name: "Crystal Nutrient Gel",   bonus: 83947,     cost: 2447382 },
    { name: "Thermal Soil Pack",      bonus: 70384,     cost: 2053847 },
    { name: "Stabilized Mineral",     bonus: 102738,    cost: 2994817 },
    { name: "Compressed Root Feed",   bonus: 86293,     cost: 2517384 },
    { name: "Dense Mineral Core",     bonus: 124917,    cost: 3644173 },
    { name: "Vacuum-Sealed Nutrient", bonus: 104738,    cost: 3053847 },
    { name: "Pressurized Humus",      bonus: 152384,    cost: 4444817 },
    { name: "Hardened Soil Matrix",   bonus: 127293,    cost: 3714738 },
    { name: "Subzero Mineral Drip",   bonus: 185473,    cost: 5413847 },
    { name: "Reinforced Feed Pack",   bonus: 154917,    cost: 4522384 },
    { name: "Condensed Root Enzyme",  bonus: 226384,    cost: 6604817 },
    { name: "Molecular Activator",    bonus: 189738,    cost: 5539173 },
    { name: "Plasma-Treated Soil",    bonus: 274917,    cost: 8023847 },
    { name: "Hyper-Dense Feed",       bonus: 231284,    cost: 6752384 },
    { name: "Core Mineral Injection", bonus: 334738,    cost: 9768291 },
    { name: "Inverted Root Feed",     bonus: 282193,    cost: 8232174 },
    { name: "Supercharged Humus",     bonus: 407384,    cost: 11888291 },
    { name: "Fused Carbon Feed",      bonus: 341847,    cost: 9978473 },
    { name: "Hyper Enzyme Matrix",    bonus: 497283,    cost: 14512847 },
    { name: "Refined Core Extract",   bonus: 418293,    cost: 12204738 },
    { name: "Magnetic Feed",          bonus: 604817,    cost: 17648291 },
    { name: "Pressured Carbon Gel",   bonus: 508473,    cost: 14833847 },
    { name: "Stratified Core Feed",   bonus: 737284,    cost: 21513847 },
    { name: "Layered Mineral Boost",  bonus: 619382,    cost: 18082174 },
    { name: "Absolute Mineral Feed",  bonus: 893847,    cost: 26088291 },
    { name: "Fractured Core Drip",    bonus: 748293,    cost: 21848473 },
    { name: "Dense Synthesis Feed",   bonus: 1083947,   cost: 31651847 },
    { name: "Concentrated Core Gel",  bonus: 912384,    cost: 26634738 },
    { name: "Terminal Growth Serum",  bonus: 1317284,   cost: 38468291 },
    { name: "Apex Mineral Extract",   bonus: 1104817,   cost: 32264738 },
    { name: "Final Form Feed",        bonus: 1600000,   cost: 46728291 },
];
const FERTILIZERS = [...BASE_FERTILIZERS, ...NEW_FERTILIZERS];

// Upgrade categories for UI grouping
const UPGRADE_CATEGORIES = {
    farming: { label: "Farming", ids: ["sharperTools", "expertFarmer", "businessman", "marketSpecialist", "irrigationSystem", "automatedSprinkler", "duplicator", "experienced", "fertilizerEfficiency", "seedMultiplier", "advancedAnalytics"] },
    efficiency: { label: "Efficiency & Utility", ids: ["timeDilator", "recyclingProtocol", "geneticMutation", "rootExpansion", "autoNegotiator"] },
    economy: { label: "Economy & Wealth", ids: ["lobbying", "treasureHunter", "inflationMastery", "offshoreAccount", "taxEvasion"] },
    scifi: { label: "Anomaly & Sci-Fi", ids: ["quantumEntanglement", "cosmicRay", "realityAnchor", "darkMatterSoil", "singularityEngine"] }
};

const UPGRADES = [
    // Farming
    { id: "sharperTools", name: "Sharper Tools", desc: "+1 yield per level", maxLevel: 20, baseCost: 250 },
    { id: "expertFarmer", name: "Expert Farmer", desc: "+10% sell price per level", maxLevel: 10, baseCost: 250 },
    { id: "businessman", name: "Businessman", desc: "+5% sell price per level", maxLevel: 20, baseCost: 500 },
    { id: "marketSpecialist", name: "Market Specialist", desc: "+5% sell price per level", maxLevel: 10, baseCost: 750 },
    { id: "irrigationSystem", name: "Irrigation System", desc: "x1.2 yield per level", maxLevel: 5, baseCost: 1000 },
    { id: "automatedSprinkler", name: "Automated Sprinkler", desc: "+2 yield per level", maxLevel: 10, baseCost: 2000 },
    { id: "duplicator", name: "Duplicator", desc: "+5% double yield chance per level", maxLevel: 3, baseCost: 2500 },
    { id: "experienced", name: "Experienced", desc: "+20% XP per level", maxLevel: 5, baseCost: 2500 },
    { id: "fertilizerEfficiency", name: "Fertilizer Efficiency", desc: "+10% fertilizer bonus per level", maxLevel: 5, baseCost: 1500 },
    { id: "seedMultiplier", name: "Seed Multiplier", desc: "+5% yield per level", maxLevel: 20, baseCost: 4000 },
    { id: "advancedAnalytics", name: "Advanced Analytics", desc: "+3% to all bonuses per level", maxLevel: 40, baseCost: 3000 },
    // Efficiency & Utility
    { id: "timeDilator", name: "Time Dilator", desc: "-0.05s cooldown per level", maxLevel: 10, baseCost: 15000 },
    { id: "recyclingProtocol", name: "Recycling Protocol", desc: "5% chance to save fertilizer per level", maxLevel: 10, baseCost: 8000 },
    { id: "geneticMutation", name: "Genetic Mutation", desc: "0.5% chance for 10x Yield per level", maxLevel: 20, baseCost: 12000 },
    { id: "rootExpansion", name: "Root Expansion", desc: "+1 Yield for every 100 XP you have", maxLevel: 5, baseCost: 25000 },
    { id: "autoNegotiator", name: "Auto Negotiator", desc: "+2% sell price per Achievement unlocked", maxLevel: 10, baseCost: 30000 },
    // Economy & Wealth
    { id: "lobbying", name: "Lobbying", desc: "Reduces Hoe prices by 2% per level", maxLevel: 20, baseCost: 50000 },
    { id: "treasureHunter", name: "Treasure Hunter", desc: "1% chance to find direct Cash while farming", maxLevel: 10, baseCost: 10000 },
    { id: "inflationMastery", name: "Inflation Mastery", desc: "Sell price increases as you hold more items", maxLevel: 15, baseCost: 75000 },
    { id: "offshoreAccount", name: "Offshore Account", desc: "Keep 1% of Balance after Prestige per level", maxLevel: 10, baseCost: 500000 },
    { id: "taxEvasion", name: "Tax Evasion", desc: "+10% Money but -5% XP per level", maxLevel: 5, baseCost: 200000 },
    // Anomaly & Sci-Fi
    { id: "quantumEntanglement", name: "Quantum Entanglement", desc: "Harvesting gives 1 random owned crop too", maxLevel: 5, baseCost: 1000000 },
    { id: "cosmicRay", name: "Cosmic Ray", desc: "Permanently adds +0.1 to Hoe Multiplier per level", maxLevel: 20, baseCost: 5000000 },
    { id: "realityAnchor", name: "Reality Anchor", desc: "Prestige Bonus is 5% more effective per level", maxLevel: 10, baseCost: 25000000 },
    { id: "darkMatterSoil", name: "Dark Matter Soil", desc: "Base Yield +50 but Fertilizer costs double", maxLevel: 5, baseCost: 100000000 },
    { id: "singularityEngine", name: "Singularity Engine", desc: "Multiplies FINAL yield by 1.1x per level", maxLevel: 10, baseCost: 500000000 }
];

const UPGRADE_BY_ID = UPGRADES.reduce((map, upgrade) => {
    map[upgrade.id] = upgrade;
    return map;
}, {});

const ACHIEVEMENT_CHECKS = {
    totalInventory: (g) => Object.values(g.inventory).reduce((sum, qty) => sum + qty, 0),
    maxInventoryStack: (g) => Object.values(g.inventory).reduce((max, qty) => Math.max(max, qty), 0),
    totalUpgradeLevels: (g) => Object.values(g.upgrades).reduce((sum, level) => sum + level, 0),
    unlockedUpgradeCount: (g) => UPGRADES.reduce((count, upgrade) => count + ((g.upgrades[upgrade.id] || 0) > 0 ? 1 : 0), 0),
    harvestedByRarity: (s, rarity) => PLANTS.reduce((sum, plant) => {
        if (plant.rarity !== rarity) return sum;
        return sum + (s.plantsHarvestedTypes[plant.name] || 0);
    }, 0),
    discoveredRarityCount: (s) => {
        const discovered = new Set();
        for (const plant of PLANTS) {
            if ((s.plantsHarvestedTypes[plant.name] || 0) > 0) {
                discovered.add(plant.rarity);
            }
        }
        return discovered.size;
    },
    maxedCategory: (g, categoryId) => {
        const category = UPGRADE_CATEGORIES[categoryId];
        if (!category || !Array.isArray(category.ids)) return false;
        return category.ids.every(id => {
            const upgrade = UPGRADE_BY_ID[id];
            return upgrade && (g.upgrades[id] || 0) >= upgrade.maxLevel;
        });
    }
};

const ACHIEVEMENTS = [
    { id: "firstSteps", name: "First Steps", desc: "Harvest your first plant", icon: "1", check: (g, s) => s.totalFarms >= 1 },
    { id: "businessman", name: "Businessman", desc: "Earn $10,000 in a single sale", icon: "$", check: (g, s) => s.bestSale >= 10000 },
    { id: "collector", name: "Collector", desc: `Harvest all ${PLANTS.length} plant types at least once`, icon: "C", check: (g, s) => s.uniquePlantsHarvested >= PLANTS.length },
    { id: "legendaryHarvest", name: "Legendary Harvest", desc: "Harvest a Tier 05 Legendary plant", icon: "L", check: (g, s) => s.legendaryHarvested > 0 },
    { id: "efficiencyExpert", name: "Efficiency Expert", desc: "Max out Fertilizer Efficiency", icon: "E", check: (g) => g.upgrades.fertilizerEfficiency >= 5 },
    { id: "toolMaster", name: "Tool Master", desc: `Unlock all ${HOES.length} hoes`, icon: "T", check: (g) => g.unlockedHoes.length >= HOES.length },
    { id: "greenThumb", name: "Green Thumb", desc: "Harvest 10,000 total plants", icon: "G", check: (g, s) => s.totalPlantsHarvested >= 10000 },
    { id: "millionaire", name: "Millionaire", desc: "Accumulate $1,000,000 total balance", icon: "M", check: (g, s) => s.totalEarned >= 1000000 },
    { id: "prestigeI", name: "Prestige I", desc: "Complete your first prestige", icon: "P", check: (g) => g.prestigeLevel >= 1 },
    { id: "prestigeV", name: "Prestige V", desc: "Reach prestige level 5", icon: "V", check: (g) => g.prestigeLevel >= 5 },
    { id: "fertilzerFanatic", name: "Fertilizer Fanatic", desc: "Use 1,000 fertilizer units", icon: "F", check: (g, s) => s.totalFertilizerUsed >= 1000 },
    { id: "speedRunner", name: "Speed Runner", desc: "Perform 100 farms in one session", icon: "S", check: (g, s) => s.sessionFarms >= 100 },
    { id: "richFarmer", name: "Rich Farmer", desc: "Have $50,000 balance at once", icon: "R", check: (g) => g.balance >= 50000 },
    { id: "upgradeAddict", name: "Upgrade Addict", desc: "Purchase 50 total upgrade levels", icon: "U", check: (g) => ACHIEVEMENT_CHECKS.totalUpgradeLevels(g) >= 50 },
    { id: "completionist", name: "Completionist", desc: "Max all upgrades", icon: "X", check: (g) => UPGRADES.every(u => g.upgrades[u.id] >= u.maxLevel) },
    { id: "legendaryFarmer", name: "Legendary Farmer", desc: "Harvest 100 Legendary plants", icon: "D", check: (g, s) => s.legendaryHarvested >= 100 },
    { id: "billionaire", name: "Billionaire", desc: "Reach 1 Billion balance", icon: "B", check: (g) => g.balance >= 1000000000 },
    { id: "prestigeMaster", name: "Prestige Master", desc: "Reach Prestige level 10", icon: "K", check: (g) => g.prestigeLevel >= 10 },

    // Session and scale
    { id: "marathonFarmer", name: "Marathon Farmer", desc: "Perform 1,000 farms in one session", icon: "H", check: (g, s) => s.sessionFarms >= 1000 },
    { id: "noDaysOff", name: "No Days Off", desc: "Reach 100,000 total farms", icon: "N", check: (g, s) => s.totalFarms >= 100000 },
    { id: "planetFeeder", name: "Planet Feeder", desc: "Harvest 1,000,000 total plants", icon: "Q", check: (g, s) => s.totalPlantsHarvested >= 1000000 },
    { id: "biosphereBuilder", name: "Biosphere Builder", desc: "Harvest 100,000,000 total plants", icon: "Y", check: (g, s) => s.totalPlantsHarvested >= 100000000 },

    // Inventory and fertilizer strategy
    { id: "warehouseTycoon", name: "Warehouse Tycoon", desc: "Hold 1,000,000 plants in inventory at once", icon: "W", check: (g) => ACHIEVEMENT_CHECKS.totalInventory(g) >= 1000000 },
    { id: "monocropMagnate", name: "Monocrop Magnate", desc: "Stockpile 250,000 of a single plant", icon: "O", check: (g) => ACHIEVEMENT_CHECKS.maxInventoryStack(g) >= 250000 },
    { id: "fertilizerRainbow", name: "Fertilizer Rainbow", desc: "Own at least 1 of every fertilizer at once", icon: "J", check: (g) => FERTILIZERS.every(f => (g.fertilizers[f.name] || 0) > 0) },
    { id: "fertilizerSilo", name: "Fertilizer Silo", desc: "Own 100,000 units of any fertilizer", icon: "Z", check: (g) => FERTILIZERS.some(f => (g.fertilizers[f.name] || 0) >= 100000) },

    // Money and market mastery
    { id: "sixFigureFlip", name: "Six Figure Flip", desc: "Earn $100,000 in a single sale", icon: "6", check: (g, s) => s.bestSale >= 100000 },
    { id: "nineFigureFlip", name: "Nine Figure Flip", desc: "Earn $100,000,000 in a single sale", icon: "9", check: (g, s) => s.bestSale >= 100000000 },
    { id: "trillionTrade", name: "Trillion Trade", desc: "Earn $1,000,000,000,000 in a single sale", icon: "T", check: (g, s) => s.bestSale >= 1000000000000 },
    { id: "seedCapital", name: "Seed Capital", desc: "Earn $100,000,000 total", icon: "A", check: (g, s) => s.totalEarned >= 100000000 },
    { id: "agriConglomerate", name: "Agri Conglomerate", desc: "Earn $10,000,000,000 total", icon: "G", check: (g, s) => s.totalEarned >= 10000000000 },
    { id: "ventureSpender", name: "Venture Spender", desc: "Spend $100,000,000 total", icon: "V", check: (g, s) => s.totalSpent >= 100000000 },
    { id: "blackHoleBudget", name: "Black Hole Budget", desc: "Spend $10,000,000,000 total", icon: "C", check: (g, s) => s.totalSpent >= 10000000000 },
    { id: "profitEngine", name: "Profit Engine", desc: "Maintain at least a 5x lifetime earn-to-spend ratio", icon: "P", check: (g, s) => s.totalSpent >= 1000000 && s.totalEarned >= (s.totalSpent * 5) },
    { id: "reserveKing", name: "Reserve King", desc: "Hold $1,000,000,000,000 balance at once", icon: "R", check: (g) => g.balance >= 1000000000000 },
    { id: "realityBank", name: "Reality Bank", desc: "Hold $1,000,000,000,000,000 balance at once", icon: "I", check: (g) => g.balance >= 1000000000000000 },

    // Yield and XP
    { id: "overclockedHarvest", name: "Overclocked Harvest", desc: "Reach 10,000 yield in one harvest", icon: "K", check: (g, s) => s.bestYield >= 10000 },
    { id: "singularYield", name: "Singular Yield", desc: "Reach 1,000,000 yield in one harvest", icon: "S", check: (g, s) => s.bestYield >= 1000000 },
    { id: "phdFarmer", name: "PhD in Photosynthesis", desc: "Reach 1,000,000 XP in one run", icon: "D", check: (g) => g.xp >= 1000000 },
    { id: "overflowFarmer", name: "Overflow Farmer", desc: "Reach 1,000,000,000 XP in one run", icon: "F", check: (g) => g.xp >= 1000000000 },

    // Tool and rarity progression
    { id: "arsenal15", name: "Field Arsenal I", desc: "Unlock 15 hoes", icon: "1", check: (g) => g.unlockedHoes.length >= 15 },
    { id: "arsenal25", name: "Field Arsenal II", desc: "Unlock 25 hoes", icon: "2", check: (g) => g.unlockedHoes.length >= 25 },
    { id: "nullPointerUnlocked", name: "Null Pointer Acquired", desc: "Unlock The 'NULL' Pointer", icon: "0", check: (g) => {
        const nullPointerIndex = HOES.findIndex(h => h.name === "The 'NULL' Pointer");
        return nullPointerIndex >= 0 && g.unlockedHoes.includes(nullPointerIndex);
    } },
    { id: "rarityGrandTour", name: "Rarity Grand Tour", desc: `Harvest at least one plant from all ${PLANT_RARITY_LEVELS.length} rarity tiers`, icon: "L", check: (g, s) => ACHIEVEMENT_CHECKS.discoveredRarityCount(s) >= PLANT_RARITY_LEVELS.length },
    { id: "divineGardener", name: "Divine Gardener", desc: "Harvest 1,000,000 Divine plants", icon: "E", check: (g, s) => ACHIEVEMENT_CHECKS.harvestedByRarity(s, "divine") >= 1000000 },
    { id: "nullCultivator", name: "Null Cultivator", desc: "Harvest 5,000,000 Null plants", icon: "U", check: (g, s) => ACHIEVEMENT_CHECKS.harvestedByRarity(s, "null") >= 5000000 },

    // Upgrade specialization and long-run mastery
    { id: "utilityVirtuoso", name: "Utility Virtuoso", desc: "Max all Efficiency & Utility upgrades", icon: "B", check: (g) => ACHIEVEMENT_CHECKS.maxedCategory(g, "efficiency") },
    { id: "anomalyVirtuoso", name: "Anomaly Virtuoso", desc: "Max all Anomaly & Sci-Fi upgrades", icon: "M", check: (g) => ACHIEVEMENT_CHECKS.maxedCategory(g, "scifi") },
    { id: "buildCrafter", name: "Build Crafter", desc: "Buy at least 1 level in 20 different upgrades", icon: "X", check: (g) => ACHIEVEMENT_CHECKS.unlockedUpgradeCount(g) >= 20 },
    { id: "levelStacker", name: "Level Stacker", desc: "Purchase 120 total upgrade levels", icon: "+", check: (g) => ACHIEVEMENT_CHECKS.totalUpgradeLevels(g) >= 120 },
    { id: "prestigeXXV", name: "Prestige XXV", desc: "Reach Prestige level 25", icon: "5", check: (g) => g.prestigeLevel >= 25 }
];

const RARITY_CONSUMPTION = {
    common: 1,
    uncommon: 2,
    rare: 3,
    epic: 4,
    legendary: 5,
    mythic: 8,
    ancient: 16,
    celestial: 32,
    eldritch: 64,
    eternal: 128,
    divine: 256,
    cosmic: 512,
    primordial: 1024,
    singularity: 2048,
    null: 4096
};
const RARITY_ORDER = {
    common: 0,
    uncommon: 1,
    rare: 2,
    epic: 3,
    legendary: 4,
    mythic: 5,
    ancient: 6,
    celestial: 7,
    eldritch: 8,
    eternal: 9,
    divine: 10,
    cosmic: 11,
    primordial: 12,
    singularity: 13,
    null: 14
};
const COOLDOWN_DURATION = 1500;
const MAX_NOTIFICATIONS = 5;


