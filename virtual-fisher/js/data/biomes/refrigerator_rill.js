/**
 * REFRIGERATOR RILL - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_REFRIGERATOR_RILL = {
    common: [
        ["Freon Drift Minnow", 0.21, 0.37, 11.84, 23.04],
        ["Frost Ripple Smelt", 0.22, 0.47, 8.84, 30.69],
        ["Coolant Wake Darter", 0.29, 0.58, 11.96, 45.05],
        ["Icebox Current Chub", 0.34, 0.74, 14.82, 41.69],
        ["Compressor Foam Loach", 0.37, 0.89, 20.34, 63.03],
        ["Shelf Mist Bream", 0.42, 1.04, 20.4, 70.9],
        ["Frozen Glimmer Trout", 0.44, 1.09, 22.44, 42.44],
        ["Chiller Sway Guppy", 0.52, 1.32, 33.29, 67.29],
        ["Glacier Trace Perch", 0.54, 1.29, 27.48, 89.36],
        ["Condense Whorl Shiner", 0.57, 1.4, 32.14, 107.52],
        ["Crystalline Flow Carp", 0.65, 1.55, 26.85, 71.89],
        ["Arctic Pulse Eel", 0.68, 1.69, 42.12, 107.02],
        ["Rime Glint Gar", 0.73, 1.8, 45.87, 104.68],
        ["Defrost Lilt Ray", 0.76, 2.15, 46.54, 101.21],
        ["Coldlight Bloom Snapper", 0.82, 2.02, 35.31, 113.6]
    ],

    uncommon: [
        ["Freon Glide Perch", 1.1, 1.77, 83.75, 148.24],
        ["Frost Arc Carp", 1.31, 2.43, 113.52, 256.65],
        ["Coolant Spiral Pike", 1.5, 3.12, 92.75, 320.96],
        ["Icebox Flux Catfish", 1.69, 3.4, 151.98, 370.54],
        ["Compressor Echo Grouper", 1.92, 4.08, 121.28, 395.49],
        ["Shelf Glare Salmon", 2.08, 4.67, 133.3, 299.01],
        ["Frozen Bend Arowana", 2.22, 5.38, 137.66, 421.77],
        ["Chiller Sweep Sturgeon", 2.44, 5.58, 259.03, 732.24],
        ["Glacier Orbit Manta", 2.71, 6.8, 266.22, 802.79],
        ["Condense Volley Barracuda", 2.73, 6.97, 288.88, 1021.74],
        ["Crystalline Shift Mackerel", 3.04, 8.38, 282.4, 620.28],
        ["Arctic Weave Swordfish", 3.17, 7.94, 229.06, 714.03],
        ["Rime Vault Tuna", 3.38, 9.43, 271.18, 902.4],
        ["Defrost Ridge Coelacanth", 3.55, 9.1, 376.27, 663.13],
        ["Coldlight Surge Leviathan", 3.93, 10.16, 358.23, 1056]
    ],

    rare: [
        ["Freon Fringe Trout", 2.87, 4.99, 331.58, 691.5],
        ["Frost Halo Pike", 3.77, 6.83, 378.05, 879.23],
        ["Coolant Prism Catfish", 4.07, 8.96, 659.39, 1974.6],
        ["Icebox Nova Grouper", 5.08, 10.92, 605.44, 1388.76],
        ["Compressor Paradox Eel", 5.78, 11.85, 597.47, 1047.03],
        ["Shelf Vector Ray", 6.25, 14.24, 798.86, 2650.43],
        ["Frozen Axiom Arowana", 6.94, 15.99, 792.51, 1795.93],
        ["Chiller Quill Mackerel", 7.36, 17.35, 1174.55, 2790.98],
        ["Glacier Ember Marlin", 7.93, 18.1, 1016.41, 2947.2],
        ["Condense Mirage Shark", 8.97, 21.77, 1324.33, 3239.57],
        ["Crystalline Rift Tuna", 8.88, 24.23, 1343.7, 3473.66],
        ["Arctic Cipherline Sturgeon", 9.93, 27.44, 1189.2, 3408.1],
        ["Rime Vortex Manta", 10.44, 26.4, 1258.91, 2926.37],
        ["Defrost Cipher Swordfish", 10.92, 26.54, 1921.99, 6055.06],
        ["Coldlight Phantom Leviathan", 11.66, 31.47, 1665.02, 6168.63]
    ],

    epic: [
        ["Freon Dominion Gar", 9.07, 16.33, 1494.82, 3019.51],
        ["Frost Maelstrom Snapper", 11.47, 21.61, 2884.57, 7642.05],
        ["Coolant Supra Eel", 11.96, 25.34, 2723.63, 9094.34],
        ["Icebox Arcane Ray", 13.35, 31.37, 2072.53, 7352.08],
        ["Compressor Dynast Arowana", 16.35, 33.73, 4321.76, 12019.18],
        ["Shelf Monolith Mackerel", 16.62, 39.25, 4620.66, 13357.16],
        ["Frozen Oblivion Marlin", 18.86, 42.57, 4537.83, 10195.4],
        ["Chiller Catalyst Shark", 21.53, 54.83, 5197.89, 19438.83],
        ["Glacier Overtide Tuna", 22.17, 55.65, 3829.36, 12305.63],
        ["Condense Hyperion Sturgeon", 24.81, 65.22, 5890.51, 12649.37],
        ["Crystalline Zenith Manta", 24.82, 65.13, 6614.85, 16775.08],
        ["Arctic Cataclysm Barracuda", 27.76, 70.33, 5690.98, 10331.92],
        ["Rime Crown Swordfish", 29.89, 78.33, 6272.46, 12872.08],
        ["Defrost Titan Coelacanth", 31.55, 74.83, 7538.25, 26668.59],
        ["Coldlight Apex Leviathan", 32.62, 83.04, 8751.7, 21888.81]
    ],

    legendary: [
        ["Freon Ancestral Snapper", 26.19, 45.35, 12489.9, 41445.54],
        ["Frost Grand Arowana", 30.94, 60.56, 10801.59, 33546.85],
        ["Coolant Luminous Mackerel", 36.67, 78.02, 13188.32, 26925.49],
        ["Icebox Imperial Marlin", 41.97, 82.59, 17677.57, 39962.25],
        ["Compressor Epoch Shark", 42.66, 100.79, 16388.28, 35052.45],
        ["Shelf Absolute Tuna", 51.71, 117.5, 15835.65, 48129.81],
        ["Frozen Myriad Sturgeon", 56.38, 132.09, 22047.67, 82365.91],
        ["Chiller Paragon Manta", 56.59, 146.56, 19362.72, 44351.67],
        ["Glacier Oracle Barracuda", 61.83, 148.82, 28226.61, 106328.85],
        ["Condense Ascendant Swordfish", 70.67, 174, 28323.06, 77389.89],
        ["Crystalline Inviolable Coelacanth", 71.27, 197.93, 30478.33, 116956.26],
        ["Arctic Eternal Leviathan", 79.29, 189.9, 27039.58, 62613.2],
        ["Rime Sovereign Wyrm", 81.93, 218.92, 33387.81, 61299.17],
        ["Defrost Prime Colossus", 90.12, 227.58, 24592.5, 92777.08],
        ["Coldlight Celestial Behemoth", 93.03, 256.72, 29401.52, 76749.15]
    ],

    mythic: [
        ["Freon Impossible Arowana", 59.27, 99.88, 43671.14, 151171.07],
        ["Frost Infinite Marlin", 77.88, 138.26, 33921.18, 129139.91],
        ["Coolant Singularity Shark", 88.27, 189.46, 61274.65, 204270.08],
        ["Icebox Unbound Tuna", 92.92, 215.59, 40769.35, 150344],
        ["Compressor Origin Sturgeon", 114.57, 243, 58246.11, 171409.4],
        ["Shelf Apexvoid Manta", 123.96, 311.48, 75419.75, 147742.9],
        ["Frozen Archetype Barracuda", 135.82, 352.74, 100074.4, 307827.24],
        ["Chiller Meta Swordfish", 147.04, 369.38, 91524.12, 204230.62],
        ["Glacier Eschaton Coelacanth", 169.68, 443.27, 125577.14, 383573.86],
        ["Condense Zeropoint Leviathan", 180.2, 479.61, 125561.76, 251185.84],
        ["Crystalline Cosmic Wyrm", 185.5, 471.1, 89697.6, 234340.33],
        ["Arctic Transcendent Colossus", 206.77, 504.54, 130482.01, 311606.8],
        ["Rime Abyssal Behemoth", 220.86, 614.27, 149333.2, 548653.38],
        ["Defrost Godfold Monarch", 237.49, 619, 141033.07, 540494.42],
        ["Coldlight Mythborn Paragon", 241.53, 662.1, 150421.19, 433924.1]
    ]

};
