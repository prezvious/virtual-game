/**
 * BROTH BASIN - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_BROTH_BASIN = {
    common: [
        ["Umami Drift Minnow", 0.2, 0.37, 8.57, 24.46],
        ["Simmer Ripple Smelt", 0.24, 0.49, 12.81, 22.46],
        ["Bouillon Wake Darter", 0.27, 0.58, 14.44, 32.49],
        ["Peppercorn Current Chub", 0.35, 0.71, 17.81, 48.45],
        ["Saffron Foam Loach", 0.39, 0.81, 15.29, 40.94],
        ["Anise Mist Bream", 0.42, 0.99, 16.53, 31.78],
        ["Miso Glimmer Trout", 0.47, 1.16, 21.75, 79.43],
        ["Stockpot Sway Guppy", 0.52, 1.28, 28.75, 104.14],
        ["Ginger Trace Perch", 0.55, 1.28, 27.11, 97.19],
        ["Clove Whorl Shiner", 0.58, 1.42, 36.09, 66.35],
        ["Chili Flow Carp", 0.62, 1.65, 25.05, 92.37],
        ["Coriander Pulse Eel", 0.69, 1.66, 42.47, 133.85],
        ["Noodle Glint Gar", 0.71, 1.86, 29.29, 101.76],
        ["Basil Lilt Ray", 0.76, 2.13, 34.9, 109.58],
        ["Brothfire Bloom Snapper", 0.79, 2.22, 43.57, 125.18]
    ],

    uncommon: [
        ["Umami Glide Perch", 1.15, 1.94, 115.82, 424.11],
        ["Simmer Arc Carp", 1.24, 2.55, 96.08, 280.28],
        ["Bouillon Spiral Pike", 1.48, 3, 84.82, 241.12],
        ["Peppercorn Flux Catfish", 1.59, 3.59, 152.16, 480.36],
        ["Saffron Echo Grouper", 1.78, 4.47, 156.83, 573.85],
        ["Anise Glare Salmon", 2.15, 5.2, 160.11, 303.48],
        ["Miso Bend Arowana", 2.15, 5, 179.44, 604.21],
        ["Stockpot Sweep Sturgeon", 2.46, 6.13, 214.36, 656.7],
        ["Ginger Orbit Manta", 2.74, 6.25, 248.98, 670.63],
        ["Clove Volley Barracuda", 2.79, 7.61, 159.43, 581.51],
        ["Chili Shift Mackerel", 3.09, 7.31, 331.17, 1092.81],
        ["Coriander Weave Swordfish", 3.18, 7.67, 203.05, 758.58],
        ["Noodle Vault Tuna", 3.55, 9.46, 322.63, 653.07],
        ["Basil Ridge Coelacanth", 3.65, 9.92, 350.04, 628.66],
        ["Brothfire Surge Leviathan", 3.9, 9.59, 248.27, 945.27]
    ],

    rare: [
        ["Umami Fringe Trout", 2.97, 5.22, 508.67, 1481.98],
        ["Simmer Halo Pike", 3.61, 7.49, 547, 1736.93],
        ["Bouillon Prism Catfish", 4.58, 9.64, 559.29, 1330.09],
        ["Peppercorn Nova Grouper", 4.82, 11.55, 766.87, 2810.22],
        ["Saffron Paradox Eel", 5.7, 12.81, 643.03, 1973.32],
        ["Anise Vector Ray", 6.22, 13.4, 605.29, 1124.04],
        ["Miso Axiom Arowana", 6.68, 16.34, 1171.59, 4077.62],
        ["Stockpot Quill Mackerel", 7.61, 18.31, 732.87, 1402.03],
        ["Ginger Ember Marlin", 7.96, 18.31, 1275.49, 4526.92],
        ["Clove Mirage Shark", 8.57, 21.89, 1050.66, 2263.84],
        ["Chili Rift Tuna", 8.98, 22.18, 1452.66, 5417.24],
        ["Coriander Cipherline Sturgeon", 9.55, 26.51, 952.4, 1924.84],
        ["Noodle Vortex Manta", 10.11, 27.9, 1237.01, 2586.94],
        ["Basil Cipher Swordfish", 11.08, 29.53, 1953.71, 7103.63],
        ["Brothfire Phantom Leviathan", 11.89, 32.89, 2058.46, 4608.41]
    ],

    epic: [
        ["Umami Dominion Gar", 8.4, 15.05, 2318.18, 6779.98],
        ["Simmer Maelstrom Snapper", 10.48, 20.75, 2020.55, 7732.87],
        ["Bouillon Supra Eel", 11.86, 23.48, 2524.42, 5215.46],
        ["Peppercorn Arcane Ray", 14.51, 31.73, 3812.02, 9187.75],
        ["Saffron Dynast Arowana", 15.22, 34.53, 3287.37, 7298.32],
        ["Anise Monolith Mackerel", 17.3, 42.96, 2640.19, 7790.87],
        ["Miso Oblivion Marlin", 19.25, 44.71, 3122.32, 7945.61],
        ["Stockpot Catalyst Shark", 21.67, 49.34, 4173.12, 9049.74],
        ["Ginger Overtide Tuna", 21.48, 57.78, 5321.04, 17804.94],
        ["Clove Hyperion Sturgeon", 23.32, 59.15, 3993.8, 12011.83],
        ["Chili Zenith Manta", 26.45, 69.95, 4498.15, 9129.1],
        ["Coriander Cataclysm Barracuda", 27.04, 67.09, 5519.4, 13498.8],
        ["Noodle Crown Swordfish", 28.2, 69.42, 6043.8, 22195.01],
        ["Basil Titan Coelacanth", 30.41, 85.54, 8035.56, 20318.91],
        ["Brothfire Apex Leviathan", 32.3, 84.78, 5977.2, 12507.33]
    ],

    legendary: [
        ["Umami Ancestral Snapper", 24.52, 42.06, 9760.61, 28868.32],
        ["Simmer Grand Arowana", 30.19, 55.27, 12442.38, 22642.66],
        ["Bouillon Luminous Mackerel", 31.8, 69.52, 14410.67, 27717.7],
        ["Peppercorn Imperial Marlin", 38.89, 87.33, 11954.15, 44672.87],
        ["Saffron Epoch Shark", 44.18, 96.43, 18383.19, 32794.21],
        ["Anise Absolute Tuna", 47.55, 113.46, 14567.52, 39038.6],
        ["Miso Myriad Sturgeon", 51.59, 126.74, 20529.05, 66612.22],
        ["Stockpot Paragon Manta", 60.02, 133.3, 21002.59, 56612.79],
        ["Ginger Oracle Barracuda", 66.16, 162.19, 27626.38, 83434.52],
        ["Clove Ascendant Swordfish", 70.04, 173.09, 19679.27, 57496.46],
        ["Chili Inviolable Coelacanth", 73, 194.83, 22605.96, 49722.69],
        ["Coriander Eternal Leviathan", 79.97, 220.3, 20676.82, 75192.37],
        ["Noodle Sovereign Wyrm", 82.33, 197.05, 39110.2, 96705.07],
        ["Basil Prime Colossus", 87.13, 227.65, 41696.62, 90860.68],
        ["Brothfire Celestial Behemoth", 94.91, 263.98, 37646.06, 134111.1]
    ],

    mythic: [
        ["Umami Impossible Arowana", 52.78, 90.42, 34913.57, 123322.29],
        ["Simmer Infinite Marlin", 77.82, 156.07, 55676.01, 157642.33],
        ["Bouillon Singularity Shark", 82.01, 170.82, 63153.23, 117641.79],
        ["Peppercorn Unbound Tuna", 104.74, 239.64, 61534.45, 164996.14],
        ["Saffron Origin Sturgeon", 115.7, 262.82, 50444.85, 91188.41],
        ["Anise Apexvoid Manta", 126.88, 277.12, 60789.06, 121265.26],
        ["Miso Archetype Barracuda", 142.04, 327.49, 101879.3, 210109.71],
        ["Stockpot Meta Swordfish", 152.69, 357.84, 71224.4, 200293.8],
        ["Ginger Eschaton Coelacanth", 160.05, 400.02, 72039.06, 256774.61],
        ["Clove Zeropoint Leviathan", 181.8, 422.92, 141168.39, 403340.12],
        ["Chili Cosmic Wyrm", 190.96, 447.81, 99343.6, 268585.36],
        ["Coriander Transcendent Colossus", 202.8, 557.19, 154519.85, 547192.67],
        ["Noodle Abyssal Behemoth", 219.54, 573.91, 163262.87, 457245.6],
        ["Basil Godfold Monarch", 235.15, 655.61, 161460.88, 348218.14],
        ["Brothfire Mythborn Paragon", 239.16, 665.63, 104525.36, 296510.76]
    ]

};
