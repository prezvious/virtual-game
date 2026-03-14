/**
 * SOMNAMBULIST SHALLOWS - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_SOMNAMBULIST_SHALLOWS = {
    common: [
        ["Dream Drift Minnow", 0.19, 0.33, 10.55, 22.19],
        ["Hypnic Ripple Smelt", 0.25, 0.46, 10.51, 29.77],
        ["Lucid Wake Darter", 0.28, 0.61, 13.63, 36.56],
        ["Moonwake Current Chub", 0.35, 0.72, 12.69, 26.17],
        ["Slumber Foam Loach", 0.38, 0.91, 16.97, 35.15],
        ["Nocturne Mist Bream", 0.43, 1.03, 16.14, 40.03],
        ["Echo Glimmer Trout", 0.47, 1.12, 23.16, 51.24],
        ["Veil Sway Guppy", 0.52, 1.23, 27.4, 91.75],
        ["Pillow Trace Perch", 0.55, 1.47, 29.75, 76.95],
        ["Drowse Whorl Shiner", 0.6, 1.61, 25.78, 87.17],
        ["Nightglass Flow Carp", 0.62, 1.62, 33.3, 93.86],
        ["REM Pulse Eel", 0.67, 1.69, 39.05, 149.3],
        ["Paradox Glint Gar", 0.74, 1.88, 31.62, 82.21],
        ["Phantom Lilt Ray", 0.76, 1.97, 27.04, 67.45],
        ["Somna Bloom Snapper", 0.82, 2.1, 31.94, 122.38]
    ],

    uncommon: [
        ["Dream Glide Perch", 1.09, 1.82, 66.3, 141.39],
        ["Hypnic Arc Carp", 1.18, 2.31, 83.43, 271.09],
        ["Lucid Spiral Pike", 1.52, 3.14, 120.34, 414.5],
        ["Moonwake Flux Catfish", 1.59, 3.81, 161.01, 501.93],
        ["Slumber Echo Grouper", 1.92, 4.55, 135.41, 424.78],
        ["Nocturne Glare Salmon", 1.97, 4.6, 192.46, 696.34],
        ["Echo Bend Arowana", 2.2, 5.77, 191.92, 446.78],
        ["Veil Sweep Sturgeon", 2.35, 5.61, 238.15, 594.63],
        ["Pillow Orbit Manta", 2.65, 7, 214.9, 631.19],
        ["Drowse Volley Barracuda", 2.73, 6.51, 172.16, 627.22],
        ["Nightglass Shift Mackerel", 2.97, 7.07, 220.62, 806.88],
        ["REM Weave Swordfish", 3.33, 8.54, 333.58, 623.38],
        ["Paradox Vault Tuna", 3.39, 8.94, 277.07, 988.42],
        ["Phantom Ridge Coelacanth", 3.7, 10.32, 221.17, 421.16],
        ["Somna Surge Leviathan", 3.73, 10.79, 311.64, 1174.8]
    ],

    rare: [
        ["Dream Fringe Trout", 3.14, 5.35, 505.62, 1044.29],
        ["Hypnic Halo Pike", 3.98, 7.47, 611.45, 2132.57],
        ["Lucid Prism Catfish", 4.21, 8.52, 422.66, 781.53],
        ["Moonwake Nova Grouper", 4.8, 10.65, 738.7, 2601.31],
        ["Slumber Paradox Eel", 5.31, 12.19, 873.27, 2312.28],
        ["Nocturne Vector Ray", 5.95, 15.16, 878.03, 3293.59],
        ["Echo Axiom Arowana", 7.12, 17.84, 1240.19, 2730.94],
        ["Veil Quill Mackerel", 7.66, 18.64, 1141.06, 3232.37],
        ["Pillow Ember Marlin", 8.24, 19.94, 1435.23, 4503.01],
        ["Drowse Mirage Shark", 8.79, 21.74, 1447.86, 2865.63],
        ["Nightglass Rift Tuna", 9.39, 22.29, 1595.82, 5189.59],
        ["REM Cipherline Sturgeon", 10.15, 27.69, 1036.81, 2425.52],
        ["Paradox Vortex Manta", 10.26, 24.52, 1135.25, 3056.94],
        ["Phantom Cipher Swordfish", 11.11, 27.87, 1759.63, 4612.72],
        ["Somna Phantom Leviathan", 11.84, 33.13, 1629.13, 3853.03]
    ],

    epic: [
        ["Dream Dominion Gar", 9.14, 15.62, 1547.36, 4976.75],
        ["Hypnic Maelstrom Snapper", 11.17, 21.98, 2449.77, 8060.5],
        ["Lucid Supra Eel", 13.43, 26.34, 2975.12, 6152.86],
        ["Moonwake Arcane Ray", 13.27, 30.35, 2748.25, 5748.33],
        ["Slumber Dynast Arowana", 15.06, 36.1, 4060.88, 11086.97],
        ["Nocturne Monolith Mackerel", 17.46, 38.35, 4224.85, 11759.79],
        ["Echo Oblivion Marlin", 19.48, 48.3, 5293.2, 18820.61],
        ["Veil Catalyst Shark", 21.32, 55.4, 5275.93, 18561.41],
        ["Pillow Overtide Tuna", 21.5, 58.17, 4619.67, 10115.25],
        ["Drowse Hyperion Sturgeon", 24.24, 64.33, 5731.93, 10628.58],
        ["Nightglass Zenith Manta", 26.14, 68.85, 7108, 21365.68],
        ["REM Cataclysm Barracuda", 27.93, 67.99, 5831.81, 12812.84],
        ["Paradox Crown Swordfish", 29.03, 77.2, 4340.5, 12902.7],
        ["Phantom Titan Coelacanth", 30.56, 77.39, 7291.02, 19012.08],
        ["Somna Apex Leviathan", 32.92, 86.63, 8620.39, 25449.25]
    ],

    legendary: [
        ["Dream Ancestral Snapper", 25.79, 43.88, 12327.01, 29652.73],
        ["Hypnic Grand Arowana", 31.99, 61.05, 14776.09, 32012.23],
        ["Lucid Luminous Mackerel", 34.47, 72.4, 12560.3, 47716.66],
        ["Moonwake Imperial Marlin", 36.82, 87.13, 17240.46, 39612.78],
        ["Slumber Epoch Shark", 41.51, 96.15, 15159.03, 39379.36],
        ["Nocturne Absolute Tuna", 46.55, 121.43, 18505.4, 41873.88],
        ["Echo Myriad Sturgeon", 55.53, 140.46, 19140.23, 69426.89],
        ["Veil Paragon Manta", 60.21, 151.71, 23538.44, 70570.31],
        ["Pillow Oracle Barracuda", 61.94, 161.79, 22009.66, 53887.87],
        ["Drowse Ascendant Swordfish", 67.42, 157.88, 17873.29, 66803.73],
        ["Nightglass Inviolable Coelacanth", 75.88, 188.06, 21310.43, 74384.15],
        ["REM Eternal Leviathan", 75.64, 202.31, 21907.51, 77472.93],
        ["Paradox Sovereign Wyrm", 85.26, 229.9, 25845.69, 53318.1],
        ["Phantom Prime Colossus", 88.8, 216, 29591.34, 61971.14],
        ["Somna Celestial Behemoth", 92.59, 252.61, 38325.05, 79690.79]
    ],

    mythic: [
        ["Dream Impossible Arowana", 62.76, 103.62, 33807.81, 112411.43],
        ["Hypnic Infinite Marlin", 65.33, 130.82, 46133.65, 118178.99],
        ["Lucid Singularity Shark", 84.14, 177.24, 66877.54, 207206.39],
        ["Moonwake Unbound Tuna", 102.43, 216.02, 66353.96, 160539.24],
        ["Slumber Origin Sturgeon", 112.14, 258.39, 60070.1, 162947.29],
        ["Nocturne Apexvoid Manta", 122.2, 301.02, 69064.53, 183203.4],
        ["Echo Archetype Barracuda", 135.37, 310.81, 77784.23, 145171.3],
        ["Veil Meta Swordfish", 147.83, 359.22, 65701.85, 131496.15],
        ["Pillow Eschaton Coelacanth", 158.82, 370.71, 127394.29, 223995.95],
        ["Drowse Zeropoint Leviathan", 181.19, 449.14, 118924.82, 349787.16],
        ["Nightglass Cosmic Wyrm", 197.14, 486.23, 135241.08, 450842.98],
        ["REM Transcendent Colossus", 199.13, 567.41, 150451.98, 545718.16],
        ["Paradox Abyssal Behemoth", 213.41, 549.52, 168748.66, 416037.59],
        ["Phantom Godfold Monarch", 234.11, 557.03, 169821.38, 410613.5],
        ["Somna Mythborn Paragon", 243.51, 589.9, 139346.22, 310612.59]
    ]

};
