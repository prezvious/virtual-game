/**
 * SHIP OF THESEUS SHOALS - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_SHIP_OF_THESEUS_SHOALS = {
    common: [
        ["Theseus Drift Minnow", 0.21, 0.35, 7.79, 29.22],
        ["Plank Ripple Smelt", 0.24, 0.48, 13.04, 29.4],
        ["Nail Wake Darter", 0.3, 0.65, 18.37, 33.2],
        ["Timber Current Chub", 0.35, 0.74, 13.74, 43.04],
        ["Hull Foam Loach", 0.39, 0.86, 22.18, 52.21],
        ["Keel Mist Bream", 0.42, 0.98, 18.83, 48.52],
        ["Driftwood Glimmer Trout", 0.47, 1.21, 23.29, 76.75],
        ["Barnacle Sway Guppy", 0.49, 1.28, 20.38, 38.19],
        ["Relic Trace Perch", 0.53, 1.42, 32.86, 89.38],
        ["Identity Whorl Shiner", 0.57, 1.51, 20.95, 63.47],
        ["Refit Flow Carp", 0.64, 1.54, 40.06, 89.66],
        ["Paradox Pulse Eel", 0.68, 1.67, 33.42, 74.28],
        ["Mast Glint Gar", 0.74, 1.86, 45.63, 117.05],
        ["Shipwright Lilt Ray", 0.75, 1.92, 43.91, 100.84],
        ["Replaced Bloom Snapper", 0.82, 2.3, 50.95, 181.15]
    ],

    uncommon: [
        ["Theseus Glide Perch", 1.18, 1.88, 115.84, 376.72],
        ["Plank Arc Carp", 1.25, 2.49, 78.2, 263.19],
        ["Nail Spiral Pike", 1.38, 3.1, 128.52, 491.27],
        ["Timber Flux Catfish", 1.56, 3.79, 122.39, 422.99],
        ["Hull Echo Grouper", 1.74, 3.86, 111.97, 352.35],
        ["Keel Glare Salmon", 2.02, 4.97, 168.18, 531.31],
        ["Driftwood Bend Arowana", 2.34, 5.78, 166.96, 559.46],
        ["Barnacle Sweep Sturgeon", 2.52, 6.39, 224.49, 471.19],
        ["Relic Orbit Manta", 2.66, 6.5, 275.04, 639.23],
        ["Identity Volley Barracuda", 2.81, 7.06, 238.28, 591.52],
        ["Refit Shift Mackerel", 3.14, 7.64, 203.87, 507.91],
        ["Paradox Weave Swordfish", 3.24, 8.96, 345.18, 1145.7],
        ["Mast Vault Tuna", 3.49, 9.45, 227.03, 514.15],
        ["Shipwright Ridge Coelacanth", 3.69, 9.05, 316.39, 986.9],
        ["Replaced Surge Leviathan", 3.73, 9.89, 256.73, 899]
    ],

    rare: [
        ["Theseus Fringe Trout", 3.08, 5.28, 349.99, 1119.1],
        ["Plank Halo Pike", 3.87, 7.1, 561.76, 1686.47],
        ["Nail Prism Catfish", 4.06, 9.06, 599.11, 2132.87],
        ["Timber Nova Grouper", 4.9, 11.43, 793.99, 2498.88],
        ["Hull Paradox Eel", 5.27, 12.04, 630.91, 2198.37],
        ["Keel Vector Ray", 5.95, 14.74, 842.14, 2358.22],
        ["Driftwood Axiom Arowana", 6.76, 15.19, 1144.88, 3130.27],
        ["Barnacle Quill Mackerel", 7.51, 18.42, 982.39, 3363.4],
        ["Relic Ember Marlin", 8.14, 18.81, 1176.99, 3894.91],
        ["Identity Mirage Shark", 8.67, 20.13, 1165.18, 3732.81],
        ["Refit Rift Tuna", 9.35, 24.94, 1497.54, 3528.61],
        ["Paradox Cipherline Sturgeon", 9.78, 26.37, 1406.12, 3535.07],
        ["Mast Vortex Manta", 10.57, 27.79, 1830.57, 4193.53],
        ["Shipwright Cipher Swordfish", 11.28, 30.67, 1833.56, 6809.52],
        ["Replaced Phantom Leviathan", 11.6, 33.39, 1467.22, 2875.78]
    ],

    epic: [
        ["Theseus Dominion Gar", 9.84, 17.42, 2515.67, 5499.52],
        ["Plank Maelstrom Snapper", 9.91, 19.02, 1977.19, 5512.12],
        ["Nail Supra Eel", 12.34, 25.29, 2883.11, 7089.98],
        ["Timber Arcane Ray", 13.55, 30.95, 2570.6, 5852.09],
        ["Hull Dynast Arowana", 15.52, 36.54, 3516.96, 11636.89],
        ["Keel Monolith Mackerel", 16.53, 37.43, 3771.89, 8395.1],
        ["Driftwood Oblivion Marlin", 18.48, 42.55, 2856.05, 7493.17],
        ["Barnacle Catalyst Shark", 21.75, 48.9, 5344.83, 11228.9],
        ["Relic Overtide Tuna", 23.1, 55.21, 3614.67, 7769.06],
        ["Identity Hyperion Sturgeon", 24.67, 60.16, 6734.33, 19867.97],
        ["Refit Zenith Manta", 25.73, 68.64, 4397.06, 8704.09],
        ["Paradox Cataclysm Barracuda", 27.85, 67.97, 6733.84, 22859.13],
        ["Mast Crown Swordfish", 29.23, 75.62, 4969.34, 16530.66],
        ["Shipwright Titan Coelacanth", 31.12, 73.7, 6010.23, 11386.15],
        ["Replaced Apex Leviathan", 32.12, 83.87, 7266.39, 21211.67]
    ],

    legendary: [
        ["Theseus Ancestral Snapper", 25.65, 45.16, 10077.43, 19981.79],
        ["Plank Grand Arowana", 28.95, 56.87, 9277.97, 20430.07],
        ["Nail Luminous Mackerel", 36.81, 77.6, 15158.26, 33410.69],
        ["Timber Imperial Marlin", 39.44, 81.88, 16558.03, 33888.62],
        ["Hull Epoch Shark", 45.15, 109.2, 17748.75, 56787.09],
        ["Keel Absolute Tuna", 51.3, 108.88, 14316.27, 42395.78],
        ["Driftwood Myriad Sturgeon", 53.72, 127.56, 16713.87, 58232.46],
        ["Barnacle Paragon Manta", 59.62, 144.97, 17097.91, 34196.38],
        ["Relic Oracle Barracuda", 63.09, 152.64, 26441.52, 83945.8],
        ["Identity Ascendant Swordfish", 66.38, 160.11, 21593.54, 71416.38],
        ["Refit Inviolable Coelacanth", 72.19, 174.84, 18780.13, 58890.85],
        ["Paradox Eternal Leviathan", 77.82, 189.83, 30775.36, 59068.26],
        ["Mast Sovereign Wyrm", 81.61, 232.43, 31895.06, 101874.84],
        ["Shipwright Prime Colossus", 88.07, 219.8, 25328.36, 93916.11],
        ["Replaced Celestial Behemoth", 93.05, 259.49, 35427.09, 66757.38]
    ],

    mythic: [
        ["Theseus Impossible Arowana", 59.25, 106.17, 25637.9, 87900.61],
        ["Plank Infinite Marlin", 65.71, 143.2, 45893.56, 119457.7],
        ["Nail Singularity Shark", 84.55, 182.16, 61204.46, 167204.74],
        ["Timber Unbound Tuna", 95.6, 218.33, 44079.69, 117513.65],
        ["Hull Origin Sturgeon", 117.94, 256.22, 62941.33, 200556.39],
        ["Keel Apexvoid Manta", 128.83, 277.46, 74477.2, 209391.5],
        ["Driftwood Archetype Barracuda", 143.85, 367.87, 98810.58, 174883.17],
        ["Barnacle Meta Swordfish", 155.95, 350.1, 82741.08, 237851.96],
        ["Relic Eschaton Coelacanth", 170.81, 412.14, 95358.34, 253824.26],
        ["Identity Zeropoint Leviathan", 174.09, 452.13, 116084.27, 385868.42],
        ["Refit Cosmic Wyrm", 189.52, 496.84, 134443.29, 344763.54],
        ["Paradox Transcendent Colossus", 199.66, 535.24, 135215.16, 483222.76],
        ["Mast Abyssal Behemoth", 214.31, 517.49, 135226.85, 462975.44],
        ["Shipwright Godfold Monarch", 226.53, 617.67, 150081.11, 435239.41],
        ["Replaced Mythborn Paragon", 247.63, 647.66, 160805.09, 364815.28]
    ]

};
