/**
 * MANDELBROT MAELSTROM - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_MANDELBROT_MAELSTROM = {
    common: [
        ["Fractal Drift Minnow", 0.21, 0.34, 11.46, 29.26],
        ["Recursive Ripple Smelt", 0.24, 0.51, 14.79, 49.88],
        ["Mandel Wake Darter", 0.27, 0.57, 17.57, 33.27],
        ["Julia Current Chub", 0.32, 0.77, 16.84, 37.88],
        ["Spiral Foam Loach", 0.36, 0.83, 13.83, 36.8],
        ["Infinite Mist Bream", 0.44, 0.94, 17.79, 43.05],
        ["Zoom Glimmer Trout", 0.46, 1.19, 22.39, 66.64],
        ["Iteration Sway Guppy", 0.52, 1.2, 28.37, 64.25],
        ["Chaos Trace Perch", 0.53, 1.27, 24.38, 55.29],
        ["Complex Whorl Shiner", 0.58, 1.45, 33.24, 108.7],
        ["Tangent Flow Carp", 0.65, 1.61, 31.74, 79.26],
        ["Orbit Pulse Eel", 0.66, 1.67, 25.48, 58.97],
        ["Converge Glint Gar", 0.74, 1.77, 39.11, 91.56],
        ["Diverge Lilt Ray", 0.78, 1.87, 40.23, 85.19],
        ["Setline Bloom Snapper", 0.81, 2.11, 48.42, 140.56]
    ],

    uncommon: [
        ["Fractal Glide Perch", 1.13, 1.87, 104.2, 348.72],
        ["Recursive Arc Carp", 1.23, 2.35, 76.45, 173.53],
        ["Mandel Spiral Pike", 1.48, 2.89, 104.55, 267.42],
        ["Julia Flux Catfish", 1.57, 3.5, 120.33, 281.24],
        ["Spiral Echo Grouper", 1.89, 3.9, 114.93, 226.91],
        ["Infinite Glare Salmon", 2.1, 5.24, 167.98, 545.02],
        ["Zoom Bend Arowana", 2.33, 5.45, 189.96, 564.6],
        ["Iteration Sweep Sturgeon", 2.45, 5.71, 175.03, 414.27],
        ["Chaos Orbit Manta", 2.72, 6.2, 278.66, 646.96],
        ["Complex Volley Barracuda", 2.76, 6.83, 251.22, 637.49],
        ["Tangent Shift Mackerel", 3.08, 7.65, 242.67, 499.59],
        ["Orbit Weave Swordfish", 3.25, 8.15, 322.99, 902.72],
        ["Converge Vault Tuna", 3.47, 8.4, 243.49, 919.23],
        ["Diverge Ridge Coelacanth", 3.66, 9.36, 273.72, 1008.9],
        ["Setline Surge Leviathan", 3.79, 9.18, 273.99, 1044.45]
    ],

    rare: [
        ["Fractal Fringe Trout", 3.42, 5.6, 428.29, 1009.01],
        ["Recursive Halo Pike", 4.05, 7.91, 460.78, 1406.92],
        ["Mandel Prism Catfish", 4.41, 9.7, 544.1, 1076],
        ["Julia Nova Grouper", 4.75, 9.87, 733.32, 2587.3],
        ["Spiral Paradox Eel", 5.43, 12.48, 738.36, 2438.57],
        ["Infinite Vector Ray", 6.26, 15.31, 1068.75, 2398.61],
        ["Zoom Axiom Arowana", 6.61, 16.05, 943.88, 2546.12],
        ["Iteration Quill Mackerel", 7.47, 18.03, 1126.7, 2555.69],
        ["Chaos Ember Marlin", 7.95, 20.59, 1206.88, 4624.75],
        ["Complex Mirage Shark", 8.82, 22.94, 908.32, 1931.71],
        ["Tangent Rift Tuna", 9.01, 25.04, 1281.27, 2589.85],
        ["Orbit Cipherline Sturgeon", 10.09, 25.97, 1123.99, 3751.77],
        ["Converge Vortex Manta", 10.7, 26.69, 1028.99, 3500.94],
        ["Diverge Cipher Swordfish", 11.37, 28.73, 1998.94, 5352.89],
        ["Setline Phantom Leviathan", 11.47, 29.57, 2014.29, 5711.19]
    ],

    epic: [
        ["Fractal Dominion Gar", 9.88, 15.75, 1678.49, 4940.62],
        ["Recursive Maelstrom Snapper", 10.69, 20.33, 2685.39, 7102.08],
        ["Mandel Supra Eel", 11.82, 25.82, 2433.02, 9147.41],
        ["Julia Arcane Ray", 13.58, 30.71, 3614.27, 7489.01],
        ["Spiral Dynast Arowana", 16.24, 35.71, 2488.96, 5759.37],
        ["Infinite Monolith Mackerel", 17.47, 38.05, 4855.32, 18391.91],
        ["Zoom Oblivion Marlin", 19.01, 48.15, 3566.06, 11850.97],
        ["Iteration Catalyst Shark", 20.82, 46.31, 3116.52, 7000.53],
        ["Chaos Overtide Tuna", 22.01, 52.71, 5655.04, 9912.49],
        ["Complex Hyperion Sturgeon", 24.41, 64.62, 5127.49, 14848.1],
        ["Tangent Zenith Manta", 26.22, 69.53, 7188, 21529.87],
        ["Orbit Cataclysm Barracuda", 26.82, 72.58, 5722.07, 16065.01],
        ["Converge Crown Swordfish", 28.02, 75.57, 5446.91, 12450.47],
        ["Diverge Titan Coelacanth", 30.66, 83.66, 7832.56, 15801.85],
        ["Setline Apex Leviathan", 31.68, 89.88, 6915.92, 12574.29]
    ],

    legendary: [
        ["Fractal Ancestral Snapper", 26.68, 44.47, 8056.37, 23168.4],
        ["Recursive Grand Arowana", 30.69, 57.24, 11582.12, 40501.41],
        ["Mandel Luminous Mackerel", 36.16, 70.33, 11803.82, 34480.28],
        ["Julia Imperial Marlin", 38.32, 78.38, 17577.02, 38114.7],
        ["Spiral Epoch Shark", 42.8, 95.03, 14540.52, 34350.98],
        ["Infinite Absolute Tuna", 49.55, 124.46, 18739.99, 57884.95],
        ["Zoom Myriad Sturgeon", 51.42, 123.62, 19320.37, 65064.04],
        ["Iteration Paragon Manta", 56.86, 149.75, 25389.22, 95095.21],
        ["Chaos Oracle Barracuda", 62.16, 163.55, 22606.56, 42865.2],
        ["Complex Ascendant Swordfish", 68.74, 157.8, 29377.08, 80947.43],
        ["Tangent Inviolable Coelacanth", 74.36, 176.14, 31069.58, 115362.11],
        ["Orbit Eternal Leviathan", 77.38, 218.23, 22551.51, 55184.44],
        ["Converge Sovereign Wyrm", 80.63, 211.34, 23018.73, 64503.83],
        ["Diverge Prime Colossus", 89.92, 214.62, 41608.43, 97728.06],
        ["Setline Celestial Behemoth", 95.03, 268.47, 44445.91, 81865.81]
    ],

    mythic: [
        ["Fractal Impossible Arowana", 55.96, 97.02, 36165.7, 79005.29],
        ["Recursive Infinite Marlin", 69.99, 147.99, 45122.7, 157049.58],
        ["Mandel Singularity Shark", 83.12, 189.25, 60756.54, 115237.23],
        ["Julia Unbound Tuna", 98.68, 234.16, 49369.67, 98015.75],
        ["Spiral Origin Sturgeon", 106.58, 265.28, 83252.15, 160224.94],
        ["Infinite Apexvoid Manta", 130.48, 305.17, 56791.47, 122219.32],
        ["Zoom Archetype Barracuda", 140.29, 327.85, 92037.58, 269098.06],
        ["Iteration Meta Swordfish", 157.36, 371.39, 110781.06, 389142.81],
        ["Chaos Eschaton Coelacanth", 166.87, 397.94, 134262.23, 445057.8],
        ["Complex Zeropoint Leviathan", 184.02, 417.61, 110543.36, 359644.31],
        ["Tangent Cosmic Wyrm", 195.23, 511.68, 131874.18, 436795.26],
        ["Orbit Transcendent Colossus", 206.78, 526.12, 158185.5, 443803.23],
        ["Converge Abyssal Behemoth", 217.55, 545.52, 146411.63, 406543.04],
        ["Diverge Godfold Monarch", 229.54, 633.46, 148661.22, 495954.34],
        ["Setline Mythborn Paragon", 240.57, 664.1, 120311.22, 316923.03]
    ]

};
