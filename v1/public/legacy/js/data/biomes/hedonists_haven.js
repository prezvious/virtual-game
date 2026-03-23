/**
 * HEDONIST'S HAVEN - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_HEDONISTS_HAVEN = {
    common: [
        ["Euphoria Drift Minnow", 0.2, 0.34, 9.81, 21.07],
        ["Rapture Ripple Smelt", 0.27, 0.47, 13.76, 49.75],
        ["Rush Wake Darter", 0.27, 0.56, 12.53, 29.68],
        ["Neon Current Chub", 0.31, 0.7, 11.82, 28.78],
        ["Pulse Foam Loach", 0.36, 0.88, 17.12, 43.53],
        ["Velvet Mist Bream", 0.42, 1, 21.94, 59.66],
        ["Crimson Glimmer Trout", 0.44, 1.17, 23.61, 87.73],
        ["Ecstasy Sway Guppy", 0.52, 1.21, 19.76, 38.69],
        ["Sonic Trace Perch", 0.54, 1.45, 27.22, 79.87],
        ["Lush Whorl Shiner", 0.58, 1.38, 34.15, 60.02],
        ["Candyflash Flow Carp", 0.64, 1.69, 33.83, 105.38],
        ["Overdrive Pulse Eel", 0.68, 1.67, 25.85, 81.47],
        ["Thrill Glint Gar", 0.74, 1.76, 35.45, 134.65],
        ["Saturation Lilt Ray", 0.78, 2.15, 34.36, 110.88],
        ["Dopamine Bloom Snapper", 0.82, 1.98, 41.55, 138.63]
    ],

    uncommon: [
        ["Euphoria Glide Perch", 1.11, 1.85, 114.33, 300.5],
        ["Rapture Arc Carp", 1.22, 2.33, 72.22, 153.58],
        ["Rush Spiral Pike", 1.41, 3.07, 96.07, 281.85],
        ["Neon Flux Catfish", 1.61, 3.73, 98.61, 306.35],
        ["Pulse Echo Grouper", 1.79, 3.93, 138.21, 496.28],
        ["Velvet Glare Salmon", 1.97, 4.9, 209, 781.62],
        ["Crimson Bend Arowana", 2.17, 5.71, 147.91, 371.09],
        ["Ecstasy Sweep Sturgeon", 2.35, 5.52, 136.04, 429.1],
        ["Sonic Orbit Manta", 2.63, 6.59, 246.09, 464.36],
        ["Lush Volley Barracuda", 2.76, 7.49, 285.14, 1015.84],
        ["Candyflash Shift Mackerel", 3.03, 7.49, 229.92, 866.47],
        ["Overdrive Weave Swordfish", 3.17, 8.31, 323.22, 963.51],
        ["Thrill Vault Tuna", 3.48, 9.1, 318.64, 987.67],
        ["Saturation Ridge Coelacanth", 3.75, 10.11, 373.25, 1145.27],
        ["Dopamine Surge Leviathan", 3.78, 10.17, 405.38, 1559.36]
    ],

    rare: [
        ["Euphoria Fringe Trout", 3.23, 5.5, 416.3, 958.19],
        ["Rapture Halo Pike", 3.68, 6.76, 410.74, 934.05],
        ["Rush Prism Catfish", 4.38, 8.82, 721.64, 2662.46],
        ["Neon Nova Grouper", 4.92, 10.33, 583.53, 1112.46],
        ["Pulse Paradox Eel", 5.57, 12.9, 842.21, 2755.69],
        ["Velvet Vector Ray", 5.97, 14.62, 704.01, 2537.65],
        ["Crimson Axiom Arowana", 7.06, 15.72, 1149.7, 3734.21],
        ["Ecstasy Quill Mackerel", 7.67, 19.77, 938.67, 2417.18],
        ["Sonic Ember Marlin", 8.1, 19.09, 1255.18, 2590.07],
        ["Lush Mirage Shark", 8.83, 20.33, 879.39, 2111.37],
        ["Candyflash Rift Tuna", 9.38, 22.74, 1386.24, 3994.52],
        ["Overdrive Cipherline Sturgeon", 10.03, 26.8, 1092.01, 3180.39],
        ["Thrill Vortex Manta", 10.2, 26.94, 1510.09, 4271.72],
        ["Saturation Cipher Swordfish", 11.01, 26.54, 1908, 5721.83],
        ["Dopamine Phantom Leviathan", 11.9, 29.1, 1642.36, 4559.08]
    ],

    epic: [
        ["Euphoria Dominion Gar", 9.98, 16.79, 1940.31, 6221.82],
        ["Rapture Maelstrom Snapper", 10.06, 21.5, 2036.41, 4207.93],
        ["Rush Supra Eel", 12.54, 25.72, 3372.23, 11154.04],
        ["Neon Arcane Ray", 14.99, 31.33, 2833.8, 7519.2],
        ["Pulse Dynast Arowana", 15.68, 34.25, 2682.87, 4823.29],
        ["Velvet Monolith Mackerel", 17.04, 43.34, 3324.17, 7216.59],
        ["Crimson Oblivion Marlin", 18.86, 46.38, 3781.74, 12877.38],
        ["Ecstasy Catalyst Shark", 20.3, 49.36, 4475.79, 10625.74],
        ["Sonic Overtide Tuna", 21.96, 52.76, 5164.42, 19101.99],
        ["Lush Hyperion Sturgeon", 23.91, 59.67, 5114.81, 11229.24],
        ["Candyflash Zenith Manta", 24.96, 61.32, 3887.75, 12559.43],
        ["Overdrive Cataclysm Barracuda", 26.89, 73.96, 6673.04, 22806.21],
        ["Thrill Crown Swordfish", 29.66, 77.82, 4895.81, 11312.21],
        ["Saturation Titan Coelacanth", 30.59, 73.05, 7032.03, 17588.02],
        ["Dopamine Apex Leviathan", 31.77, 79.38, 7162.22, 17338.05]
    ],

    legendary: [
        ["Euphoria Ancestral Snapper", 27.15, 43.86, 11222.37, 24850.47],
        ["Rapture Grand Arowana", 30.55, 54.93, 9664.05, 35316.05],
        ["Rush Luminous Mackerel", 34.46, 73.37, 12011.35, 26788.47],
        ["Neon Imperial Marlin", 39.7, 86.18, 12012.33, 27503.36],
        ["Pulse Epoch Shark", 45.76, 101.34, 12947.93, 48185.82],
        ["Velvet Absolute Tuna", 50.52, 108.71, 20176.1, 42144.55],
        ["Crimson Myriad Sturgeon", 54.06, 129.24, 22784.43, 64413.62],
        ["Ecstasy Paragon Manta", 57.76, 149.51, 16509.08, 29007.77],
        ["Sonic Oracle Barracuda", 61.43, 144.35, 23044.47, 48909.33],
        ["Lush Ascendant Swordfish", 68.38, 164.41, 27724.6, 84967.88],
        ["Candyflash Inviolable Coelacanth", 74.07, 185.07, 31330.94, 69449.92],
        ["Overdrive Eternal Leviathan", 76.76, 198.93, 27765.94, 61748.16],
        ["Thrill Sovereign Wyrm", 84.44, 209.96, 28373.02, 84108.47],
        ["Saturation Prime Colossus", 88.48, 230.08, 42008.28, 92516.91],
        ["Dopamine Celestial Behemoth", 93.26, 258.5, 25157.6, 61673.07]
    ],

    mythic: [
        ["Euphoria Impossible Arowana", 59.54, 99.84, 46304.65, 81376.41],
        ["Rapture Infinite Marlin", 70.98, 148.88, 54516.08, 127384.62],
        ["Rush Singularity Shark", 86.07, 172.39, 61873.6, 178300.17],
        ["Neon Unbound Tuna", 96.55, 218.91, 49656.26, 169096.01],
        ["Pulse Origin Sturgeon", 113.68, 245, 86141.79, 297749.54],
        ["Velvet Apexvoid Manta", 119.89, 286.13, 79786.05, 151466.33],
        ["Crimson Archetype Barracuda", 139.02, 343.01, 67088.29, 227620.34],
        ["Ecstasy Meta Swordfish", 151.88, 368.83, 120034.28, 442902.16],
        ["Sonic Eschaton Coelacanth", 163.64, 423.21, 70776.58, 220728.04],
        ["Lush Zeropoint Leviathan", 173.97, 453.85, 126871.91, 472037.78],
        ["Candyflash Cosmic Wyrm", 186.55, 480.52, 99821.14, 189990.17],
        ["Overdrive Transcendent Colossus", 203.59, 518.51, 130671.89, 289033.66],
        ["Thrill Abyssal Behemoth", 214.03, 529.43, 144417.31, 441771.68],
        ["Saturation Godfold Monarch", 234.09, 576.72, 171552.32, 407307.31],
        ["Dopamine Mythborn Paragon", 248.98, 592.08, 109679.66, 252699.42]
    ]

};
