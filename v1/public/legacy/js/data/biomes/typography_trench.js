/**
 * TYPOGRAPHY TRENCH - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_TYPOGRAPHY_TRENCH = {
    common: [
        ["Glyph Drift Minnow", 0.2, 0.34, 9.93, 35.98],
        ["Serif Ripple Smelt", 0.25, 0.49, 9.63, 22.68],
        ["Kerning Wake Darter", 0.3, 0.62, 16.24, 48.62],
        ["Ligature Current Chub", 0.33, 0.72, 16.72, 48.23],
        ["Pica Foam Loach", 0.36, 0.83, 13.26, 31.87],
        ["Comma Mist Bream", 0.43, 0.97, 26.74, 59.89],
        ["Apostrophe Glimmer Trout", 0.45, 1.04, 27.7, 97.44],
        ["Rune Sway Guppy", 0.49, 1.24, 26.52, 71.59],
        ["Letterpress Trace Perch", 0.55, 1.48, 25.21, 76.15],
        ["Typebar Whorl Shiner", 0.58, 1.59, 31.02, 100.67],
        ["Italic Flow Carp", 0.62, 1.47, 24.28, 65.51],
        ["Boldface Pulse Eel", 0.7, 1.88, 29.27, 52.59],
        ["Script Glint Gar", 0.73, 1.8, 30.67, 76.98],
        ["Monospace Lilt Ray", 0.75, 1.88, 30.41, 106.54],
        ["Baseliner Bloom Snapper", 0.81, 2.19, 37.21, 89.32]
    ],

    uncommon: [
        ["Glyph Glide Perch", 1.07, 1.92, 81.33, 268.31],
        ["Serif Arc Carp", 1.18, 2.43, 112.78, 390.94],
        ["Kerning Spiral Pike", 1.56, 2.94, 92.62, 260.62],
        ["Ligature Flux Catfish", 1.67, 3.82, 135.14, 249.21],
        ["Pica Echo Grouper", 1.88, 4.45, 156.71, 414.94],
        ["Comma Glare Salmon", 2.12, 5.03, 206.76, 729.53],
        ["Apostrophe Bend Arowana", 2.28, 5.45, 178.76, 571.69],
        ["Rune Sweep Sturgeon", 2.44, 6.36, 182.86, 425.49],
        ["Letterpress Orbit Manta", 2.57, 6.32, 243.72, 461.98],
        ["Typebar Volley Barracuda", 2.9, 7.02, 231.73, 707.49],
        ["Italic Shift Mackerel", 3, 7.72, 301.04, 641.01],
        ["Boldface Weave Swordfish", 3.14, 7.78, 337.12, 1047.2],
        ["Script Vault Tuna", 3.37, 8.39, 207.1, 562.66],
        ["Monospace Ridge Coelacanth", 3.59, 10.19, 322.43, 891.91],
        ["Baseliner Surge Leviathan", 3.94, 11.02, 241.33, 844.73]
    ],

    rare: [
        ["Glyph Fringe Trout", 3.11, 5.1, 371.72, 839.41],
        ["Serif Halo Pike", 3.43, 7.27, 412.55, 915],
        ["Kerning Prism Catfish", 4.37, 9.68, 699.45, 2337.66],
        ["Ligature Nova Grouper", 4.87, 10.33, 789.06, 1679.52],
        ["Pica Paradox Eel", 5.53, 13.63, 797.95, 2508.9],
        ["Comma Vector Ray", 6.15, 14.88, 676.32, 1807.92],
        ["Apostrophe Axiom Arowana", 6.63, 16.23, 824.14, 2226.08],
        ["Rune Quill Mackerel", 7.23, 18.83, 712.15, 1336.32],
        ["Letterpress Ember Marlin", 8.14, 21.5, 1432.73, 2765.77],
        ["Typebar Mirage Shark", 8.76, 22.43, 826.89, 1777.04],
        ["Italic Rift Tuna", 9.35, 25.27, 901.16, 1597.26],
        ["Boldface Cipherline Sturgeon", 9.92, 23.26, 1555.41, 4661.89],
        ["Script Vortex Manta", 10.12, 27.02, 1238.87, 4122.33],
        ["Monospace Cipher Swordfish", 10.98, 30.59, 1057.76, 3694.33],
        ["Baseliner Phantom Leviathan", 11.91, 31.43, 1400.02, 3855.12]
    ],

    epic: [
        ["Glyph Dominion Gar", 9.64, 15.97, 1963.56, 6089.92],
        ["Serif Maelstrom Snapper", 11.88, 21.16, 2411.87, 5137.51],
        ["Kerning Supra Eel", 13.12, 27.02, 2513.98, 6650.26],
        ["Ligature Arcane Ray", 13.21, 29.26, 3644.05, 12944.96],
        ["Pica Dynast Arowana", 15.53, 34.88, 2654.73, 8885.29],
        ["Comma Monolith Mackerel", 16.97, 39.93, 2832.05, 10487.15],
        ["Apostrophe Oblivion Marlin", 19.13, 43.69, 3804.31, 13757.57],
        ["Rune Catalyst Shark", 21.64, 54.01, 4440.57, 16409.96],
        ["Letterpress Overtide Tuna", 22.43, 57.5, 5693.64, 19220.24],
        ["Typebar Hyperion Sturgeon", 24.38, 56.36, 5441.86, 18187.64],
        ["Italic Zenith Manta", 26.27, 67.59, 6759.6, 12240.21],
        ["Boldface Cataclysm Barracuda", 27.11, 68.47, 5652.36, 18786.73],
        ["Script Crown Swordfish", 28.34, 78.14, 7278.52, 27382.45],
        ["Monospace Titan Coelacanth", 30.99, 82.45, 7302.87, 13210.92],
        ["Baseliner Apex Leviathan", 31.68, 84.11, 4868.93, 10104.44]
    ],

    legendary: [
        ["Glyph Ancestral Snapper", 23.65, 40.71, 6787.15, 15190.41],
        ["Serif Grand Arowana", 29.91, 60.42, 13393.52, 43511.42],
        ["Kerning Luminous Mackerel", 34.28, 75.19, 15903.11, 52213.33],
        ["Ligature Imperial Marlin", 41.37, 91.45, 17635.87, 37770.95],
        ["Pica Epoch Shark", 43.18, 95.36, 11011.49, 34545.93],
        ["Comma Absolute Tuna", 51.75, 117.24, 19011.79, 56938.81],
        ["Apostrophe Myriad Sturgeon", 52.66, 126.83, 24992.67, 58175.47],
        ["Rune Paragon Manta", 56.91, 137.64, 20373.03, 40949.08],
        ["Letterpress Oracle Barracuda", 60.96, 157.22, 21973.86, 39814.4],
        ["Typebar Ascendant Swordfish", 70.28, 167.08, 27809.75, 67714.77],
        ["Italic Inviolable Coelacanth", 75.39, 187.91, 29164.48, 105857.52],
        ["Boldface Eternal Leviathan", 78.85, 216.67, 21979.23, 52311.38],
        ["Script Sovereign Wyrm", 81.14, 211.5, 23945.21, 66222.55],
        ["Monospace Prime Colossus", 89.1, 221.35, 32028.62, 98110.19],
        ["Baseliner Celestial Behemoth", 94.23, 228.51, 40597.81, 136534.92]
    ],

    mythic: [
        ["Glyph Impossible Arowana", 57.36, 94.24, 35339.71, 110340.7],
        ["Serif Infinite Marlin", 72.17, 147.33, 55240.28, 117895.01],
        ["Kerning Singularity Shark", 90.7, 196.73, 50433.18, 158624.22],
        ["Ligature Unbound Tuna", 102.18, 224.95, 80554.39, 302381.13],
        ["Pica Origin Sturgeon", 107.77, 244.3, 84875.71, 245460.9],
        ["Comma Apexvoid Manta", 118.77, 265.62, 85259.48, 230360.39],
        ["Apostrophe Archetype Barracuda", 144.28, 330.79, 64925.08, 232791.7],
        ["Rune Meta Swordfish", 157.83, 394.53, 83935.38, 167572.2],
        ["Letterpress Eschaton Coelacanth", 161.03, 414.34, 105049.24, 329109.34],
        ["Typebar Zeropoint Leviathan", 176.31, 476.66, 79065.85, 233639.62],
        ["Italic Cosmic Wyrm", 185.59, 510.72, 113705.91, 279927.77],
        ["Boldface Transcendent Colossus", 201.3, 564.65, 93476.56, 174944.86],
        ["Script Abyssal Behemoth", 223.6, 617.01, 142625.41, 452984.45],
        ["Monospace Godfold Monarch", 234.41, 586.43, 177082.84, 659546.72],
        ["Baseliner Mythborn Paragon", 250.58, 622.39, 141683.8, 336814.6]
    ]

};
