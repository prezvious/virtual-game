/**
 * MOBIUS STRIP STREAM - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_MOBIUS_STRIP_STREAM = {
    common: [
        ["Mobius Drift Minnow", 0.21, 0.35, 9.01, 30.99],
        ["Loop Ripple Smelt", 0.24, 0.48, 9.68, 33.88],
        ["Ribbon Wake Darter", 0.3, 0.57, 11.87, 24.96],
        ["Twist Current Chub", 0.33, 0.71, 20.16, 55.91],
        ["One-Sided Foam Loach", 0.37, 0.9, 12.87, 40.53],
        ["Topology Mist Bream", 0.4, 1.01, 24.92, 64.25],
        ["Inversion Glimmer Trout", 0.44, 1.18, 18.79, 65.43],
        ["Backflow Sway Guppy", 0.49, 1.33, 23.7, 61.52],
        ["Unbound Trace Perch", 0.53, 1.24, 24.47, 63.03],
        ["Foldline Whorl Shiner", 0.59, 1.38, 28.83, 76.72],
        ["Strip Flow Carp", 0.65, 1.67, 42.05, 89.7],
        ["Continuum Pulse Eel", 0.69, 1.71, 33.15, 99.55],
        ["Knot Glint Gar", 0.71, 1.93, 26.92, 77.48],
        ["Reversal Lilt Ray", 0.75, 1.95, 29.14, 100.12],
        ["Endless Bloom Snapper", 0.8, 2.16, 29.36, 56.05]
    ],

    uncommon: [
        ["Mobius Glide Perch", 1.06, 1.87, 62.65, 156.66],
        ["Loop Arc Carp", 1.3, 2.47, 76.87, 292.89],
        ["Ribbon Spiral Pike", 1.51, 2.9, 127.38, 377.99],
        ["Twist Flux Catfish", 1.57, 3.43, 144.16, 550.43],
        ["One-Sided Echo Grouper", 1.83, 4.35, 147.21, 284.32],
        ["Topology Glare Salmon", 2.03, 4.66, 202.51, 567.47],
        ["Inversion Bend Arowana", 2.33, 5.4, 231.75, 837.48],
        ["Backflow Sweep Sturgeon", 2.44, 6.31, 204.29, 627.37],
        ["Unbound Orbit Manta", 2.74, 6.52, 162.73, 595.33],
        ["Foldline Volley Barracuda", 2.81, 6.51, 215.14, 800.17],
        ["Strip Shift Mackerel", 3.08, 8.4, 200.91, 388.36],
        ["Continuum Weave Swordfish", 3.21, 8.45, 198.75, 499.6],
        ["Knot Vault Tuna", 3.51, 9.34, 244.91, 878.46],
        ["Reversal Ridge Coelacanth", 3.7, 9.24, 299.89, 1090.44],
        ["Endless Surge Leviathan", 3.89, 10.82, 229.02, 592.78]
    ],

    rare: [
        ["Mobius Fringe Trout", 2.96, 5.39, 505.4, 1539.17],
        ["Loop Halo Pike", 3.87, 7.57, 408.89, 820.61],
        ["Ribbon Prism Catfish", 4.42, 8.64, 528.19, 1659.75],
        ["Twist Nova Grouper", 4.95, 10.25, 770.69, 1738.23],
        ["One-Sided Paradox Eel", 5.59, 12.8, 582.57, 1179.09],
        ["Topology Vector Ray", 6.02, 15.1, 773.89, 1706.35],
        ["Inversion Axiom Arowana", 6.49, 14.69, 865.95, 3154.52],
        ["Backflow Quill Mackerel", 7.13, 16.39, 1237.29, 4602.15],
        ["Unbound Ember Marlin", 7.71, 21.14, 1046.01, 3366.36],
        ["Foldline Mirage Shark", 8.35, 22.45, 1213.81, 4151.59],
        ["Strip Rift Tuna", 9.25, 24.31, 1022.25, 2756.66],
        ["Continuum Cipherline Sturgeon", 9.89, 24.86, 1494.7, 2717.92],
        ["Knot Vortex Manta", 10.52, 26.99, 1112.87, 2343.97],
        ["Reversal Cipher Swordfish", 10.89, 30.12, 1512.64, 5650.44],
        ["Endless Phantom Leviathan", 11.65, 33.15, 1801.45, 3386.82]
    ],

    epic: [
        ["Mobius Dominion Gar", 10.12, 17.14, 1869.35, 3618.02],
        ["Loop Maelstrom Snapper", 9.86, 18.8, 2513.37, 8726.5],
        ["Ribbon Supra Eel", 11.78, 24.64, 1994.38, 4223.03],
        ["Twist Arcane Ray", 13.53, 29.29, 3609.47, 10699.65],
        ["One-Sided Dynast Arowana", 16.31, 37.48, 4532.91, 11391.71],
        ["Topology Monolith Mackerel", 17.53, 42.39, 3255.72, 11553.03],
        ["Inversion Oblivion Marlin", 18.27, 43.01, 4394.84, 13569.65],
        ["Backflow Catalyst Shark", 20.25, 48.02, 4891.29, 17692.5],
        ["Unbound Overtide Tuna", 21.76, 57.06, 5420.82, 13592.43],
        ["Foldline Hyperion Sturgeon", 23.47, 60.19, 5986.36, 21884.85],
        ["Strip Zenith Manta", 26.13, 60.26, 4716.94, 11249.3],
        ["Continuum Cataclysm Barracuda", 27.46, 64.78, 7340.06, 17861.08],
        ["Knot Crown Swordfish", 28.28, 78.17, 5711.83, 16290.43],
        ["Reversal Titan Coelacanth", 30.94, 73.67, 7891.43, 16295.07],
        ["Endless Apex Leviathan", 31.39, 81.83, 6470.66, 17182.45]
    ],

    legendary: [
        ["Mobius Ancestral Snapper", 26.46, 43.82, 7041.6, 15306.93],
        ["Loop Grand Arowana", 28.69, 53.92, 12992.46, 48328.97],
        ["Ribbon Luminous Mackerel", 33.35, 65.39, 9154.98, 27270.49],
        ["Twist Imperial Marlin", 40.13, 85.72, 12795.47, 44078.06],
        ["One-Sided Epoch Shark", 42.02, 92, 11765.03, 45193.18],
        ["Topology Absolute Tuna", 47.83, 115.97, 15344.18, 53144.03],
        ["Inversion Myriad Sturgeon", 56.12, 138.05, 23738.15, 42338.66],
        ["Backflow Paragon Manta", 56.55, 129.61, 18536.72, 43873.47],
        ["Unbound Oracle Barracuda", 61.69, 147.93, 19689.14, 75144.47],
        ["Foldline Ascendant Swordfish", 70.09, 182.72, 24673.19, 66660.63],
        ["Strip Inviolable Coelacanth", 70.52, 198.5, 24910.48, 48559.77],
        ["Continuum Eternal Leviathan", 78.71, 209.2, 32774.17, 71792.98],
        ["Knot Sovereign Wyrm", 83.3, 230.35, 24143.71, 48075.39],
        ["Reversal Prime Colossus", 86.16, 213.69, 28539.5, 103508.92],
        ["Endless Celestial Behemoth", 90.59, 223.56, 38645.38, 72894.66]
    ],

    mythic: [
        ["Mobius Impossible Arowana", 60.96, 109.86, 26202.48, 51056.48],
        ["Loop Infinite Marlin", 78.14, 139.19, 54887.08, 102715.63],
        ["Ribbon Singularity Shark", 88.94, 171.45, 62757.17, 208078.12],
        ["Twist Unbound Tuna", 92.06, 204.77, 48111.9, 152285.28],
        ["One-Sided Origin Sturgeon", 114.51, 243.12, 90902.81, 333017.76],
        ["Topology Apexvoid Manta", 125.98, 277.78, 57368.51, 148290.62],
        ["Inversion Archetype Barracuda", 135.01, 308.94, 74195.08, 250362.57],
        ["Backflow Meta Swordfish", 154.33, 384.12, 113730.04, 431350.62],
        ["Unbound Eschaton Coelacanth", 163.16, 392.18, 110868.17, 211921.61],
        ["Foldline Zeropoint Leviathan", 171.64, 477.54, 123206.06, 399050.92],
        ["Strip Cosmic Wyrm", 192.93, 534.34, 125860.86, 342006.01],
        ["Continuum Transcendent Colossus", 208.9, 488.13, 108573.64, 337888.81],
        ["Knot Abyssal Behemoth", 221.43, 615.06, 98450.73, 362471.89],
        ["Reversal Godfold Monarch", 226.77, 630.65, 155278.47, 592026.49],
        ["Endless Mythborn Paragon", 244.21, 701.65, 114588.82, 201805.8]
    ]

};
