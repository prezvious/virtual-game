/**
 * TESSERACT TRENCH - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_TESSERACT_TRENCH = {
    common: [
        ["Tesseract Drift Minnow", 0.22, 0.35, 11.47, 30.66],
        ["Hypercube Ripple Smelt", 0.25, 0.49, 13.76, 43.1],
        ["Fourth-Axis Wake Darter", 0.27, 0.57, 13.95, 37.26],
        ["Foldspace Current Chub", 0.33, 0.76, 11.63, 22.3],
        ["Quantum-Edge Foam Loach", 0.38, 0.9, 20.28, 71.36],
        ["Orthogonal Mist Bream", 0.41, 0.94, 23.08, 83.19],
        ["Vector Glimmer Trout", 0.45, 1.08, 23.61, 61.47],
        ["Node Sway Guppy", 0.52, 1.34, 27.35, 61.35],
        ["Phase Trace Perch", 0.53, 1.25, 20.11, 35.93],
        ["Crossplane Whorl Shiner", 0.58, 1.38, 23.83, 47.29],
        ["Dimension Flow Carp", 0.64, 1.71, 27.19, 64.1],
        ["Vertex Pulse Eel", 0.69, 1.88, 34.1, 94.25],
        ["Prismfold Glint Gar", 0.71, 1.8, 31.21, 80.87],
        ["Axiom Lilt Ray", 0.75, 1.96, 32.23, 122.7],
        ["Cubewake Bloom Snapper", 0.81, 2.2, 46.01, 107.96]
    ],

    uncommon: [
        ["Tesseract Glide Perch", 1.08, 1.81, 90.15, 170.33],
        ["Hypercube Arc Carp", 1.29, 2.59, 110.63, 254.68],
        ["Fourth-Axis Spiral Pike", 1.38, 2.82, 91.35, 205.64],
        ["Foldspace Flux Catfish", 1.7, 3.89, 178.68, 485.03],
        ["Quantum-Edge Echo Grouper", 1.94, 4.28, 207.83, 596.72],
        ["Orthogonal Glare Salmon", 2.15, 5.22, 213.12, 553.85],
        ["Vector Bend Arowana", 2.24, 5.55, 237.71, 429.92],
        ["Node Sweep Sturgeon", 2.54, 6.29, 234.09, 594.44],
        ["Phase Orbit Manta", 2.57, 6.86, 251.37, 676.1],
        ["Crossplane Volley Barracuda", 2.87, 6.63, 212.06, 793.78],
        ["Dimension Shift Mackerel", 2.96, 7.17, 289.95, 863.76],
        ["Vertex Weave Swordfish", 3.26, 8.4, 227.99, 463.38],
        ["Prismfold Vault Tuna", 3.45, 8.31, 302.32, 929.63],
        ["Axiom Ridge Coelacanth", 3.65, 9.04, 229.15, 437.27],
        ["Cubewake Surge Leviathan", 3.95, 10.61, 229.56, 494.75]
    ],

    rare: [
        ["Tesseract Fringe Trout", 3.04, 5.64, 320.31, 908.08],
        ["Hypercube Halo Pike", 3.8, 7.12, 425.52, 1003.61],
        ["Fourth-Axis Prism Catfish", 4.7, 9.29, 498.54, 1319.17],
        ["Foldspace Nova Grouper", 4.64, 10.34, 731.31, 1835.3],
        ["Quantum-Edge Paradox Eel", 5.84, 13.87, 609.81, 2334.47],
        ["Orthogonal Vector Ray", 6.45, 14.68, 824.36, 2803.83],
        ["Vector Axiom Arowana", 7.15, 15.4, 818.3, 2010.21],
        ["Node Quill Mackerel", 7.14, 17.29, 753.72, 1478.84],
        ["Phase Ember Marlin", 8, 18.65, 1286.09, 4032],
        ["Crossplane Mirage Shark", 8.52, 20.7, 1044.93, 2491.32],
        ["Dimension Rift Tuna", 9.37, 23.04, 1272.56, 2462.82],
        ["Vertex Cipherline Sturgeon", 9.74, 26.39, 1285.85, 4232.98],
        ["Prismfold Vortex Manta", 10.28, 26.86, 1030.07, 3328.9],
        ["Axiom Cipher Swordfish", 11.13, 28.28, 1329.2, 2823.04],
        ["Cubewake Phantom Leviathan", 11.74, 28.99, 1827.26, 3580.69]
    ],

    epic: [
        ["Tesseract Dominion Gar", 9.34, 15.87, 2362.37, 5172.99],
        ["Hypercube Maelstrom Snapper", 10.18, 19.72, 1825.6, 6348.65],
        ["Fourth-Axis Supra Eel", 12.98, 26.33, 2489.86, 9466.2],
        ["Foldspace Arcane Ray", 13.25, 29.02, 2032.07, 4966.08],
        ["Quantum-Edge Dynast Arowana", 15.63, 35.13, 3214.56, 9377.03],
        ["Orthogonal Monolith Mackerel", 17.95, 43.2, 3292.71, 10193.89],
        ["Vector Oblivion Marlin", 18.88, 42.32, 3535.58, 11275.47],
        ["Node Catalyst Shark", 21.49, 48.71, 5542.85, 18817.8],
        ["Phase Overtide Tuna", 22.49, 57.44, 4140.36, 7572.93],
        ["Crossplane Hyperion Sturgeon", 24.65, 65.16, 5765.9, 16801.99],
        ["Dimension Zenith Manta", 25.86, 64.18, 6536.75, 24118.98],
        ["Vertex Cataclysm Barracuda", 27.97, 69.97, 7768.66, 21353.92],
        ["Prismfold Crown Swordfish", 29.71, 77.04, 8138.4, 24166.42],
        ["Axiom Titan Coelacanth", 31.68, 85.81, 8520.63, 30888.39],
        ["Cubewake Apex Leviathan", 32.55, 90.99, 5481.28, 13108.79]
    ],

    legendary: [
        ["Tesseract Ancestral Snapper", 26.59, 45.22, 9917.38, 21733.19],
        ["Hypercube Grand Arowana", 30.85, 59.67, 14080.81, 48272.69],
        ["Fourth-Axis Luminous Mackerel", 31.86, 69.27, 12831.01, 36528.07],
        ["Foldspace Imperial Marlin", 37.17, 87.43, 14523.11, 30317.73],
        ["Quantum-Edge Epoch Shark", 46.67, 103.48, 13019.24, 28200.42],
        ["Orthogonal Absolute Tuna", 50.68, 124.32, 21135.32, 65587.4],
        ["Vector Myriad Sturgeon", 56.33, 121.35, 23333.2, 78453.83],
        ["Node Paragon Manta", 60.29, 138.56, 16394.3, 53275.53],
        ["Phase Oracle Barracuda", 65.71, 169.6, 31497, 68236.55],
        ["Crossplane Ascendant Swordfish", 70.09, 175.41, 25997.04, 67177.22],
        ["Dimension Inviolable Coelacanth", 75.12, 190.24, 27565.62, 93394.29],
        ["Vertex Eternal Leviathan", 78.14, 217.74, 36669.3, 120424.7],
        ["Prismfold Sovereign Wyrm", 85.65, 237.38, 23025.19, 51521.2],
        ["Axiom Prime Colossus", 87.37, 241.77, 39973.8, 140897.42],
        ["Cubewake Celestial Behemoth", 94.05, 240.72, 40619.25, 101976.62]
    ],

    mythic: [
        ["Tesseract Impossible Arowana", 56.47, 101.09, 28317.07, 71717.42],
        ["Hypercube Infinite Marlin", 76.99, 142.35, 35809.84, 64218.45],
        ["Fourth-Axis Singularity Shark", 83.13, 175.13, 39785.95, 129772.05],
        ["Foldspace Unbound Tuna", 98.76, 205.03, 64328.57, 213888.3],
        ["Quantum-Edge Origin Sturgeon", 115.03, 259.05, 73141.34, 281306.89],
        ["Orthogonal Apexvoid Manta", 130.01, 292.46, 89918.67, 158328.31],
        ["Vector Archetype Barracuda", 135.96, 305.56, 70511.07, 201721.37],
        ["Node Meta Swordfish", 154.04, 388.61, 116449.99, 265293.53],
        ["Phase Eschaton Coelacanth", 159.66, 392.84, 123084.22, 402006.93],
        ["Crossplane Zeropoint Leviathan", 177.33, 438.09, 98051.09, 342022.41],
        ["Dimension Cosmic Wyrm", 186.98, 453.08, 130978.66, 366928.27],
        ["Vertex Transcendent Colossus", 207.59, 500.71, 155857.41, 483622.33],
        ["Prismfold Abyssal Behemoth", 220.22, 551.4, 120417.83, 439166.17],
        ["Axiom Godfold Monarch", 234.88, 577.05, 129531.29, 270016.07],
        ["Cubewake Mythborn Paragon", 247.8, 702.96, 146706.41, 523347.37]
    ]

};
