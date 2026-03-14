/**
 * SILHOUETTE STRAIT - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_SILHOUETTE_STRAIT = {
    common: [
        ["Shadow Drift Minnow", 0.2, 0.36, 8.89, 22.99],
        ["Ink Ripple Smelt", 0.23, 0.43, 9.45, 23.23],
        ["Outline Wake Darter", 0.27, 0.59, 10.33, 31.53],
        ["Obsidian Current Chub", 0.33, 0.68, 20.24, 75.2],
        ["Monochrome Foam Loach", 0.37, 0.79, 18.25, 46.82],
        ["Voidline Mist Bream", 0.41, 0.91, 24.12, 69.64],
        ["Ebon Glimmer Trout", 0.46, 1.03, 29.8, 112.28],
        ["Contrast Sway Guppy", 0.48, 1.23, 26.57, 55.87],
        ["Flatlight Trace Perch", 0.54, 1.26, 32.19, 104.67],
        ["Negative Whorl Shiner", 0.59, 1.46, 37.09, 140.65],
        ["Sable Flow Carp", 0.64, 1.65, 32.44, 108.55],
        ["Noir Pulse Eel", 0.66, 1.78, 28.36, 57.66],
        ["Pitch Glint Gar", 0.71, 1.74, 37.27, 135.49],
        ["Hollow Lilt Ray", 0.74, 2.11, 34.57, 125.96],
        ["Darktrace Bloom Snapper", 0.81, 2.22, 36.85, 69.77]
    ],

    uncommon: [
        ["Shadow Glide Perch", 1, 1.8, 85.02, 297.47],
        ["Ink Arc Carp", 1.21, 2.34, 82.36, 211.12],
        ["Outline Spiral Pike", 1.46, 3.07, 115.68, 255.22],
        ["Obsidian Flux Catfish", 1.59, 3.75, 157.79, 368.79],
        ["Monochrome Echo Grouper", 1.94, 4.53, 194.19, 365.76],
        ["Voidline Glare Salmon", 2.1, 4.47, 143.81, 270.23],
        ["Ebon Bend Arowana", 2.17, 5.4, 140.23, 351.32],
        ["Contrast Sweep Sturgeon", 2.49, 6.01, 224.11, 453.42],
        ["Flatlight Orbit Manta", 2.53, 6.47, 180.81, 474.23],
        ["Negative Volley Barracuda", 2.73, 7.54, 292.88, 1075.99],
        ["Sable Shift Mackerel", 2.96, 7.02, 232.56, 694.91],
        ["Noir Weave Swordfish", 3.26, 8.89, 212.31, 372.98],
        ["Pitch Vault Tuna", 3.46, 9.18, 324.2, 816.04],
        ["Hollow Ridge Coelacanth", 3.64, 10.2, 316.28, 1046.68],
        ["Darktrace Surge Leviathan", 3.71, 10.5, 294.9, 779.89]
    ],

    rare: [
        ["Shadow Fringe Trout", 3.19, 5.26, 469.25, 1131.35],
        ["Ink Halo Pike", 3.54, 6.74, 505.71, 1718.71],
        ["Outline Prism Catfish", 4.42, 9.37, 570.19, 1929.74],
        ["Obsidian Nova Grouper", 4.99, 11.16, 809.01, 2323.57],
        ["Monochrome Paradox Eel", 5.74, 12.58, 677.26, 2261.29],
        ["Voidline Vector Ray", 6.14, 14.79, 886.85, 1602.2],
        ["Ebon Axiom Arowana", 6.49, 16.56, 648.74, 1472.28],
        ["Contrast Quill Mackerel", 7.11, 17.45, 1086.4, 3272.28],
        ["Flatlight Ember Marlin", 8.2, 20.83, 818.16, 1600.04],
        ["Negative Mirage Shark", 8.63, 21.11, 1291.17, 3867.35],
        ["Sable Rift Tuna", 9.14, 25.35, 1443.95, 3647.49],
        ["Noir Cipherline Sturgeon", 9.98, 24.32, 986.26, 3174.08],
        ["Pitch Vortex Manta", 10.29, 26.48, 1166.27, 4044.83],
        ["Hollow Cipher Swordfish", 10.86, 28.1, 1825.12, 6418.8],
        ["Darktrace Phantom Leviathan", 11.74, 30.03, 2034.25, 6237.22]
    ],

    epic: [
        ["Shadow Dominion Gar", 8.87, 15.55, 1567.28, 3589.17],
        ["Ink Maelstrom Snapper", 10.32, 20.42, 2166.66, 4150.17],
        ["Outline Supra Eel", 13.18, 25.42, 2342.2, 4132.74],
        ["Obsidian Arcane Ray", 14.69, 29.22, 3760.08, 10112.65],
        ["Monochrome Dynast Arowana", 15.84, 33.37, 2456.36, 5381.41],
        ["Voidline Monolith Mackerel", 16.93, 39.46, 3850.13, 8490.82],
        ["Ebon Oblivion Marlin", 18.69, 44.68, 2956.51, 10534.33],
        ["Contrast Catalyst Shark", 21.11, 51.12, 5466.36, 16353.75],
        ["Flatlight Overtide Tuna", 22.51, 56.94, 3730.67, 13628.43],
        ["Negative Hyperion Sturgeon", 24.11, 58.45, 5487, 17599.56],
        ["Sable Zenith Manta", 25.56, 66.13, 4141.53, 12550.32],
        ["Noir Cataclysm Barracuda", 28.03, 73.12, 4396.45, 8751.84],
        ["Pitch Crown Swordfish", 29.84, 78.4, 6155.71, 11190.88],
        ["Hollow Titan Coelacanth", 30.83, 76.25, 4821.08, 8706.2],
        ["Darktrace Apex Leviathan", 32.55, 91.44, 8343.51, 28339.21]
    ],

    legendary: [
        ["Shadow Ancestral Snapper", 26.99, 45.08, 10902.8, 37967.31],
        ["Ink Grand Arowana", 31.39, 61.58, 10646.3, 38383.47],
        ["Outline Luminous Mackerel", 32.97, 70.4, 11346.88, 24307.54],
        ["Obsidian Imperial Marlin", 37.22, 79.38, 13488.69, 51404.22],
        ["Monochrome Epoch Shark", 42.61, 103.49, 13765.97, 50184.61],
        ["Voidline Absolute Tuna", 48.48, 113.71, 22780.26, 65027.01],
        ["Ebon Myriad Sturgeon", 51.81, 132.99, 23356.06, 67521.88],
        ["Contrast Paragon Manta", 59.36, 137.06, 28144.02, 79455.17],
        ["Flatlight Oracle Barracuda", 63.64, 168.3, 20446.05, 69286.54],
        ["Negative Ascendant Swordfish", 66.38, 180.37, 21418.7, 64917.65],
        ["Sable Inviolable Coelacanth", 74.5, 179.36, 33301.77, 83165.8],
        ["Noir Eternal Leviathan", 78.52, 192.93, 33800.5, 79870.25],
        ["Pitch Sovereign Wyrm", 80.86, 204.46, 34395.25, 60794.53],
        ["Hollow Prime Colossus", 90.11, 230.78, 40401.99, 137026.87],
        ["Darktrace Celestial Behemoth", 94.43, 228.65, 26719.46, 73369.96]
    ],

    mythic: [
        ["Shadow Impossible Arowana", 55.87, 93.21, 42786.3, 106388.78],
        ["Ink Infinite Marlin", 66.96, 129.56, 38046.04, 103509.57],
        ["Outline Singularity Shark", 85.38, 189.01, 47824.66, 151382.44],
        ["Obsidian Unbound Tuna", 98.9, 213.22, 52091.73, 101948.56],
        ["Monochrome Origin Sturgeon", 105.44, 255.9, 57671.22, 110076.38],
        ["Voidline Apexvoid Manta", 124.47, 305.68, 76915.36, 248723.56],
        ["Ebon Archetype Barracuda", 143.64, 335.35, 98586.16, 227864.82],
        ["Contrast Meta Swordfish", 153.44, 384.47, 83877.17, 287221.26],
        ["Flatlight Eschaton Coelacanth", 160.55, 418.4, 96481.86, 214785.74],
        ["Negative Zeropoint Leviathan", 176.62, 484.3, 140609.56, 538953.78],
        ["Sable Cosmic Wyrm", 194.59, 510.06, 87329.76, 258142.22],
        ["Noir Transcendent Colossus", 206.08, 543.78, 153494.05, 498445.4],
        ["Pitch Abyssal Behemoth", 212.11, 603.52, 107191.12, 220418.3],
        ["Hollow Godfold Monarch", 232.52, 600.45, 167871.31, 349004.02],
        ["Darktrace Mythborn Paragon", 238.04, 622.22, 103407.85, 255831.35]
    ]

};
