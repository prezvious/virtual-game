/**
 * UTILITARIAN UTOPIA - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_UTILITARIAN_UTOPIA = {
    common: [
        ["Optimal Drift Minnow", 0.21, 0.36, 10.1, 37.87],
        ["Efficient Ripple Smelt", 0.23, 0.46, 12.96, 27.92],
        ["Metric Wake Darter", 0.3, 0.6, 13.15, 43.39],
        ["Utility Current Chub", 0.32, 0.77, 14.22, 50.19],
        ["Gridline Foam Loach", 0.38, 0.81, 14.75, 33.32],
        ["Algorithm Mist Bream", 0.44, 1, 23.32, 43.97],
        ["Rational Glimmer Trout", 0.47, 1.06, 27.3, 68.31],
        ["Balanced Sway Guppy", 0.5, 1.31, 30.89, 89.48],
        ["Uniform Trace Perch", 0.57, 1.39, 24.5, 81.34],
        ["Precise Whorl Shiner", 0.57, 1.39, 20.78, 78.66],
        ["Calibrated Flow Carp", 0.66, 1.76, 32.94, 87.86],
        ["Standard Pulse Eel", 0.66, 1.66, 28.81, 90.35],
        ["Cleanroom Glint Gar", 0.74, 1.83, 34.17, 60.7],
        ["Protocol Lilt Ray", 0.78, 2, 34.59, 69.13],
        ["Objective Bloom Snapper", 0.8, 2.01, 43.78, 164.08]
    ],

    uncommon: [
        ["Optimal Glide Perch", 0.95, 1.83, 73.01, 136.54],
        ["Efficient Arc Carp", 1.37, 2.43, 132.31, 383.07],
        ["Metric Spiral Pike", 1.53, 2.94, 145.12, 267.96],
        ["Utility Flux Catfish", 1.56, 3.49, 125.63, 336.92],
        ["Gridline Echo Grouper", 1.81, 4.1, 118.74, 280.08],
        ["Algorithm Glare Salmon", 2.14, 4.49, 163.58, 314.21],
        ["Rational Bend Arowana", 2.33, 5.54, 202.29, 569.52],
        ["Balanced Sweep Sturgeon", 2.35, 5.98, 203.7, 498.17],
        ["Uniform Orbit Manta", 2.61, 6.04, 239.22, 441.89],
        ["Precise Volley Barracuda", 2.91, 6.66, 221.34, 676.23],
        ["Calibrated Shift Mackerel", 3.1, 7.4, 222.46, 670.57],
        ["Standard Weave Swordfish", 3.35, 7.83, 324.84, 1145.91],
        ["Cleanroom Vault Tuna", 3.4, 8.48, 270.79, 729.66],
        ["Protocol Ridge Coelacanth", 3.75, 9.64, 315.78, 966.19],
        ["Objective Surge Leviathan", 3.73, 10.15, 272.97, 980.65]
    ],

    rare: [
        ["Optimal Fringe Trout", 3.47, 5.53, 396.01, 728.11],
        ["Efficient Halo Pike", 4.09, 7.3, 514.81, 919.52],
        ["Metric Prism Catfish", 4.08, 8.77, 689.58, 1381.12],
        ["Utility Nova Grouper", 4.84, 10.38, 696.9, 2491.17],
        ["Gridline Paradox Eel", 5.75, 13.27, 546.91, 1212.83],
        ["Algorithm Vector Ray", 6.29, 14.38, 863.63, 1519.27],
        ["Rational Axiom Arowana", 6.95, 16.01, 782.3, 2985.6],
        ["Balanced Quill Mackerel", 7.75, 16.96, 1185.07, 2429.95],
        ["Uniform Ember Marlin", 8.05, 19.6, 1044.77, 1892.23],
        ["Precise Mirage Shark", 8.35, 22.58, 1000.61, 2519.52],
        ["Calibrated Rift Tuna", 9.17, 21.78, 958.25, 1944.28],
        ["Standard Cipherline Sturgeon", 9.6, 27.27, 1136.61, 4204.48],
        ["Cleanroom Vortex Manta", 10.24, 25.75, 1199.72, 2333.7],
        ["Protocol Cipher Swordfish", 11.14, 30.94, 1338.03, 4199.85],
        ["Objective Phantom Leviathan", 11.36, 32.68, 1752.47, 5459.84]
    ],

    epic: [
        ["Optimal Dominion Gar", 9.68, 16.01, 1697.24, 5989.93],
        ["Efficient Maelstrom Snapper", 11.39, 22.03, 2210.14, 5298.46],
        ["Metric Supra Eel", 13.04, 24.59, 1991.61, 5282.26],
        ["Utility Arcane Ray", 14.41, 30.99, 2929.59, 6079.82],
        ["Gridline Dynast Arowana", 15.79, 36.44, 3585.78, 12067.09],
        ["Algorithm Monolith Mackerel", 16.51, 37.49, 4050.01, 7177.52],
        ["Rational Oblivion Marlin", 19.95, 46.25, 3613.71, 12098.25],
        ["Balanced Catalyst Shark", 21.33, 54.38, 5489.12, 15159.18],
        ["Uniform Overtide Tuna", 22.85, 52.12, 6087.34, 12944.35],
        ["Precise Hyperion Sturgeon", 24.61, 56.34, 6777.78, 18828.19],
        ["Calibrated Zenith Manta", 25.57, 63.57, 4052.72, 10770.91],
        ["Standard Cataclysm Barracuda", 26.9, 65.2, 4496.88, 11248.72],
        ["Cleanroom Crown Swordfish", 28.22, 74.44, 7640.61, 28275.57],
        ["Protocol Titan Coelacanth", 30.42, 76.69, 5377.18, 14436.42],
        ["Objective Apex Leviathan", 31.92, 86.62, 6486.76, 11572.75]
    ],

    legendary: [
        ["Optimal Ancestral Snapper", 24.84, 40.85, 6658.96, 21457.51],
        ["Efficient Grand Arowana", 27.44, 52.1, 10236.28, 21026.27],
        ["Metric Luminous Mackerel", 34.73, 76.21, 15809.59, 36162.51],
        ["Utility Imperial Marlin", 40.93, 93.45, 16181.52, 38004.77],
        ["Gridline Epoch Shark", 46.45, 107.13, 17808.8, 57638.76],
        ["Algorithm Absolute Tuna", 47.96, 118.04, 22834.95, 51775.23],
        ["Rational Myriad Sturgeon", 52.88, 135.49, 21421.42, 58942.95],
        ["Balanced Paragon Manta", 57.91, 151.42, 18379.64, 57487.92],
        ["Uniform Oracle Barracuda", 64.5, 152.35, 16751.12, 30250.47],
        ["Precise Ascendant Swordfish", 66.11, 182.52, 27331.57, 78541.67],
        ["Calibrated Inviolable Coelacanth", 71.99, 195.68, 27056.34, 58753.19],
        ["Standard Eternal Leviathan", 78.29, 207.9, 21529.66, 80338.96],
        ["Cleanroom Sovereign Wyrm", 84.54, 228.59, 23752.48, 42645.44],
        ["Protocol Prime Colossus", 85.34, 225.42, 33111.54, 97179.83],
        ["Objective Celestial Behemoth", 93.61, 246.62, 39721.96, 107757.45]
    ],

    mythic: [
        ["Optimal Impossible Arowana", 59.42, 106.51, 42139.6, 86482.14],
        ["Efficient Infinite Marlin", 67.11, 140.72, 33023.16, 109652.34],
        ["Metric Singularity Shark", 89.39, 190.12, 46943.62, 136615.66],
        ["Utility Unbound Tuna", 93.38, 213.75, 64796.7, 136009.26],
        ["Gridline Origin Sturgeon", 108.32, 256.74, 58193.22, 142237.53],
        ["Algorithm Apexvoid Manta", 124.48, 317.19, 90513.04, 161915.33],
        ["Rational Archetype Barracuda", 137.88, 335.33, 74794.51, 179293.75],
        ["Balanced Meta Swordfish", 146.75, 362.26, 94405.53, 200244.54],
        ["Uniform Eschaton Coelacanth", 166.35, 433.68, 94030.29, 326173.71],
        ["Precise Zeropoint Leviathan", 176.33, 412.35, 131265.06, 328964.88],
        ["Calibrated Cosmic Wyrm", 197.32, 484.27, 123686.06, 296829.62],
        ["Standard Transcendent Colossus", 207.58, 522.37, 138378.52, 286343.11],
        ["Cleanroom Abyssal Behemoth", 214.49, 559.68, 159684.79, 557937.35],
        ["Protocol Godfold Monarch", 227.35, 568.32, 102723.87, 354843.7],
        ["Objective Mythborn Paragon", 239.39, 614.17, 165428.12, 446421.78]
    ]

};
