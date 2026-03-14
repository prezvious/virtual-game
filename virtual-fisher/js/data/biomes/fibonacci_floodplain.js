/**
 * FIBONACCI FLOODPLAIN - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_FIBONACCI_FLOODPLAIN = {
    common: [
        ["Fibonacci Drift Minnow", 0.18, 0.32, 9.22, 17.93],
        ["Golden Ripple Smelt", 0.24, 0.48, 9.16, 31.74],
        ["Spiral Wake Darter", 0.3, 0.65, 14.02, 41.15],
        ["Nautilus Current Chub", 0.33, 0.72, 17.62, 44.08],
        ["Sequence Foam Loach", 0.38, 0.81, 13.33, 42.73],
        ["Ratio Mist Bream", 0.41, 1.02, 22.75, 59.79],
        ["Phi Glimmer Trout", 0.46, 1.02, 25.2, 84.07],
        ["Helix Sway Guppy", 0.52, 1.26, 33.78, 107.57],
        ["Symmetry Trace Perch", 0.53, 1.24, 21.94, 67.97],
        ["Arc Whorl Shiner", 0.57, 1.56, 31.66, 100.03],
        ["Proportion Flow Carp", 0.63, 1.51, 34.41, 77.69],
        ["Series Pulse Eel", 0.67, 1.73, 27.91, 89.28],
        ["Pattern Glint Gar", 0.72, 1.88, 29.46, 60.58],
        ["Lattice Lilt Ray", 0.78, 1.95, 37.44, 103.86],
        ["Suncurve Bloom Snapper", 0.8, 2.15, 29.31, 103.27]
    ],

    uncommon: [
        ["Fibonacci Glide Perch", 1.08, 1.79, 101.22, 284.32],
        ["Golden Arc Carp", 1.19, 2.24, 93.24, 306.07],
        ["Spiral Spiral Pike", 1.44, 2.93, 127.37, 474.22],
        ["Nautilus Flux Catfish", 1.68, 3.64, 99.32, 182.31],
        ["Sequence Echo Grouper", 1.88, 4.14, 159.81, 486.99],
        ["Ratio Glare Salmon", 2.03, 4.49, 192.03, 359.6],
        ["Phi Bend Arowana", 2.19, 5.5, 155.49, 521.94],
        ["Helix Sweep Sturgeon", 2.55, 6.17, 271.52, 588.87],
        ["Symmetry Orbit Manta", 2.55, 6.07, 168.28, 472.36],
        ["Arc Volley Barracuda", 2.82, 7.07, 207.28, 430.47],
        ["Proportion Shift Mackerel", 3, 8, 258.87, 502.21],
        ["Series Weave Swordfish", 3.25, 8.25, 245.98, 900.04],
        ["Pattern Vault Tuna", 3.43, 8.62, 354.26, 828.68],
        ["Lattice Ridge Coelacanth", 3.68, 10.37, 304.65, 544.08],
        ["Suncurve Surge Leviathan", 3.94, 10.21, 389.52, 833.59]
    ],

    rare: [
        ["Fibonacci Fringe Trout", 3.29, 5.7, 388.95, 726.34],
        ["Golden Halo Pike", 3.63, 6.69, 573.32, 1623.1],
        ["Spiral Prism Catfish", 4.33, 8.97, 653.05, 2091.33],
        ["Nautilus Nova Grouper", 4.86, 10.14, 792.44, 2438.58],
        ["Sequence Paradox Eel", 5.24, 12.75, 528.01, 1241.25],
        ["Ratio Vector Ray", 5.97, 13.24, 907.37, 3285.11],
        ["Phi Axiom Arowana", 7.08, 17.25, 1057.37, 2035.32],
        ["Helix Quill Mackerel", 7.55, 19.04, 755.27, 2881.33],
        ["Symmetry Ember Marlin", 7.7, 18.6, 1343.75, 4920.21],
        ["Arc Mirage Shark", 8.64, 21.06, 1046.54, 2950.06],
        ["Proportion Rift Tuna", 9.47, 24.79, 1034.6, 3550.01],
        ["Series Cipherline Sturgeon", 9.53, 27.25, 1223.32, 3355.6],
        ["Pattern Vortex Manta", 10.38, 29.14, 1519.42, 5586.06],
        ["Lattice Cipher Swordfish", 10.87, 27.01, 1258.26, 2212.7],
        ["Suncurve Phantom Leviathan", 11.76, 29.07, 1692.95, 4065.49]
    ],

    epic: [
        ["Fibonacci Dominion Gar", 9.41, 15.25, 1747.12, 6422.79],
        ["Golden Maelstrom Snapper", 10.3, 19.52, 2397.48, 5456.32],
        ["Spiral Supra Eel", 13.27, 28.26, 3272.53, 7120.84],
        ["Nautilus Arcane Ray", 15.1, 30.73, 2734.71, 6216.8],
        ["Sequence Dynast Arowana", 15.54, 33.77, 3435.29, 9583.13],
        ["Ratio Monolith Mackerel", 16.77, 38.96, 3480.52, 10434.83],
        ["Phi Oblivion Marlin", 19.53, 45.06, 4643.23, 16111.79],
        ["Helix Catalyst Shark", 20.64, 54.34, 4180.34, 14758.26],
        ["Symmetry Overtide Tuna", 23.2, 55.77, 4870.59, 9823.83],
        ["Arc Hyperion Sturgeon", 24.79, 65.87, 6707.37, 20520.97],
        ["Proportion Zenith Manta", 24.72, 59.75, 6044.23, 12645.49],
        ["Series Cataclysm Barracuda", 27.47, 65.74, 4208.68, 8450.01],
        ["Pattern Crown Swordfish", 28.6, 71.7, 6612.53, 11582.82],
        ["Lattice Titan Coelacanth", 30.93, 74.75, 5680.03, 11002.46],
        ["Suncurve Apex Leviathan", 31.59, 79.88, 8167.8, 18493.9]
    ],

    legendary: [
        ["Fibonacci Ancestral Snapper", 23.58, 42.31, 10001.37, 27670.5],
        ["Golden Grand Arowana", 27.58, 59.14, 11395.57, 21255.62],
        ["Spiral Luminous Mackerel", 34.55, 72.29, 14076.65, 46487.35],
        ["Nautilus Imperial Marlin", 41.76, 82.22, 15786.14, 29397.47],
        ["Sequence Epoch Shark", 42.91, 94.86, 14741.33, 31564.5],
        ["Ratio Absolute Tuna", 49.66, 107.41, 21476.94, 53808.17],
        ["Phi Myriad Sturgeon", 54.85, 120.35, 20194.37, 47272.87],
        ["Helix Paragon Manta", 56.4, 133.38, 25474.34, 66971.14],
        ["Symmetry Oracle Barracuda", 64.53, 154.56, 19171, 70011.82],
        ["Arc Ascendant Swordfish", 70.93, 186.69, 29851.03, 105740.87],
        ["Proportion Inviolable Coelacanth", 72.59, 196.65, 23113.99, 54501.57],
        ["Series Eternal Leviathan", 75.77, 201.76, 24342.6, 93261.36],
        ["Pattern Sovereign Wyrm", 80.49, 212.44, 20879.39, 44402.69],
        ["Lattice Prime Colossus", 90.21, 243.16, 28873.12, 82854.03],
        ["Suncurve Celestial Behemoth", 95.02, 232, 25245.57, 70061.54]
    ],

    mythic: [
        ["Fibonacci Impossible Arowana", 59.57, 108.54, 45420.21, 95604.79],
        ["Golden Infinite Marlin", 67.23, 139.74, 31631.44, 97582.02],
        ["Spiral Singularity Shark", 90.72, 192.18, 49540.18, 158905.57],
        ["Nautilus Unbound Tuna", 100.61, 204.7, 69830.63, 153974.62],
        ["Sequence Origin Sturgeon", 112.05, 257.44, 85527.7, 158067.01],
        ["Ratio Apexvoid Manta", 121.93, 287.21, 84956.9, 164137.78],
        ["Phi Archetype Barracuda", 142.4, 322.9, 72291.52, 268568.61],
        ["Helix Meta Swordfish", 155.44, 396.71, 117809.87, 260363.3],
        ["Symmetry Eschaton Coelacanth", 163.62, 397.96, 104787.2, 297201],
        ["Arc Zeropoint Leviathan", 173.7, 475.73, 137846.77, 343828.55],
        ["Proportion Cosmic Wyrm", 189.3, 446.07, 98158.17, 338363.08],
        ["Series Transcendent Colossus", 200.83, 478.11, 108003.28, 387302.25],
        ["Pattern Abyssal Behemoth", 213.99, 519.08, 133097.55, 352825.72],
        ["Lattice Godfold Monarch", 228.27, 594.92, 150446.8, 462281.33],
        ["Suncurve Mythborn Paragon", 249.28, 612.73, 194905.28, 475651.07]
    ]

};
