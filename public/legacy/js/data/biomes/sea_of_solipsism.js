/**
 * SEA OF SOLIPSISM - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_SEA_OF_SOLIPSISM = {
    common: [
        ["Mirror Drift Minnow", 0.22, 0.37, 9.27, 32.66],
        ["Self Ripple Smelt", 0.23, 0.44, 13.31, 50.03],
        ["Reflection Wake Darter", 0.28, 0.61, 15.68, 54.01],
        ["Echo Current Chub", 0.34, 0.7, 12.79, 42.35],
        ["Solus Foam Loach", 0.37, 0.9, 14.14, 51.82],
        ["Introspect Mist Bream", 0.43, 1.01, 19.98, 68.82],
        ["Persona Glimmer Trout", 0.47, 1.15, 22.03, 68.75],
        ["Mindglass Sway Guppy", 0.5, 1.14, 21.36, 50.26],
        ["Narcissus Trace Perch", 0.57, 1.44, 34.71, 74.54],
        ["Interior Whorl Shiner", 0.58, 1.57, 28.67, 72.51],
        ["Facet Flow Carp", 0.63, 1.48, 34.22, 97.4],
        ["Replica Pulse Eel", 0.66, 1.61, 24.07, 42.85],
        ["Lonewave Glint Gar", 0.74, 2.05, 30.44, 79.78],
        ["Selfsame Lilt Ray", 0.77, 2.03, 34.9, 76.94],
        ["Gaze Bloom Snapper", 0.8, 2.24, 47.53, 165.03]
    ],

    uncommon: [
        ["Mirror Glide Perch", 1.13, 1.9, 98.37, 334.19],
        ["Self Arc Carp", 1.32, 2.35, 80.76, 214.82],
        ["Reflection Spiral Pike", 1.55, 3.29, 117.48, 381.46],
        ["Echo Flux Catfish", 1.75, 3.66, 118.32, 254.54],
        ["Solus Echo Grouper", 1.96, 4.36, 132.25, 437.46],
        ["Introspect Glare Salmon", 2.08, 5.02, 190.56, 564.2],
        ["Persona Bend Arowana", 2.24, 5.52, 195.86, 460.08],
        ["Mindglass Sweep Sturgeon", 2.37, 6.29, 215.72, 820.27],
        ["Narcissus Orbit Manta", 2.54, 6.6, 175.38, 440.33],
        ["Interior Volley Barracuda", 2.81, 7.33, 273.96, 978.72],
        ["Facet Shift Mackerel", 3.13, 7.15, 266.48, 999.66],
        ["Replica Weave Swordfish", 3.34, 8.17, 356.52, 1170.63],
        ["Lonewave Vault Tuna", 3.45, 8.79, 251.04, 449.71],
        ["Selfsame Ridge Coelacanth", 3.74, 8.82, 334.27, 738.18],
        ["Gaze Surge Leviathan", 3.94, 10.25, 328.83, 1168.07]
    ],

    rare: [
        ["Mirror Fringe Trout", 3.23, 5.59, 389.15, 704.26],
        ["Self Halo Pike", 4, 7.29, 501.36, 1083.6],
        ["Reflection Prism Catfish", 4.23, 9.3, 518.81, 1541.76],
        ["Echo Nova Grouper", 4.96, 11.26, 721.61, 2119.16],
        ["Solus Paradox Eel", 5.82, 13.17, 779.97, 2618.31],
        ["Introspect Vector Ray", 6.25, 14.25, 714.96, 2719.05],
        ["Persona Axiom Arowana", 6.72, 15.34, 735.5, 2512.4],
        ["Mindglass Quill Mackerel", 7.54, 18.82, 1024.83, 2898.32],
        ["Narcissus Ember Marlin", 8.31, 19.27, 1366.66, 3611.45],
        ["Interior Mirage Shark", 8.59, 21.89, 885.44, 1785.8],
        ["Facet Rift Tuna", 9.03, 23.25, 885.58, 2571.76],
        ["Replica Cipherline Sturgeon", 9.92, 25.67, 1258.22, 3545.63],
        ["Lonewave Vortex Manta", 10.65, 25.46, 1859.75, 4981.31],
        ["Selfsame Cipher Swordfish", 10.95, 30.49, 1042.99, 1954.77],
        ["Gaze Phantom Leviathan", 11.75, 32.73, 1164.39, 3285.57]
    ],

    epic: [
        ["Mirror Dominion Gar", 8.47, 15.63, 1511.3, 3558.18],
        ["Self Maelstrom Snapper", 10.03, 21.31, 2142.53, 4832.29],
        ["Reflection Supra Eel", 12.15, 24.36, 2546.02, 6301.88],
        ["Echo Arcane Ray", 14.58, 31.67, 3585.21, 11761.59],
        ["Solus Dynast Arowana", 15.46, 37.31, 3803.67, 8901.78],
        ["Introspect Monolith Mackerel", 16.89, 43.29, 4080.76, 9197.79],
        ["Persona Oblivion Marlin", 20.01, 46.54, 5331.93, 13291.13],
        ["Mindglass Catalyst Shark", 21.14, 50.14, 4970.52, 14737.09],
        ["Narcissus Overtide Tuna", 23.14, 51.49, 3466.1, 9717.03],
        ["Interior Hyperion Sturgeon", 24.49, 58.13, 4705.76, 13636.55],
        ["Facet Zenith Manta", 26.75, 68.74, 6569.87, 18264.22],
        ["Replica Cataclysm Barracuda", 27.56, 66.39, 4946.72, 13221.65],
        ["Lonewave Crown Swordfish", 28.36, 68.22, 7259.17, 15594.92],
        ["Selfsame Titan Coelacanth", 31.32, 87.45, 7227.34, 17736.71],
        ["Gaze Apex Leviathan", 32.42, 82.44, 5683.52, 12727.55]
    ],

    legendary: [
        ["Mirror Ancestral Snapper", 23.6, 39.21, 6790.04, 14259.09],
        ["Self Grand Arowana", 29.07, 59.47, 10534.73, 33567.45],
        ["Reflection Luminous Mackerel", 31.87, 63.98, 10181.3, 34218.66],
        ["Echo Imperial Marlin", 40.19, 83.92, 19001.83, 37433.49],
        ["Solus Epoch Shark", 44.14, 94.54, 17377.54, 36707.83],
        ["Introspect Absolute Tuna", 50.91, 118.3, 22910.46, 64560.93],
        ["Persona Myriad Sturgeon", 54.5, 125.18, 15754.4, 51645.91],
        ["Mindglass Paragon Manta", 58.64, 134.69, 25513.41, 74129.94],
        ["Narcissus Oracle Barracuda", 64.75, 170.09, 23106.15, 59464.71],
        ["Interior Ascendant Swordfish", 67.41, 174.99, 31604, 87727.13],
        ["Facet Inviolable Coelacanth", 71.72, 169.89, 32821.85, 62089.12],
        ["Replica Eternal Leviathan", 80.8, 213.83, 33679.34, 118462.82],
        ["Lonewave Sovereign Wyrm", 83.23, 223.14, 39431.08, 73260.52],
        ["Selfsame Prime Colossus", 86.74, 227.23, 38516.25, 104318.46],
        ["Gaze Celestial Behemoth", 92.31, 259.67, 35831.26, 117046.15]
    ],

    mythic: [
        ["Mirror Impossible Arowana", 52.13, 89.44, 35515.65, 76195.44],
        ["Self Infinite Marlin", 73.31, 146.73, 45372.18, 161567.84],
        ["Reflection Singularity Shark", 88.66, 194.94, 60455.41, 172288.22],
        ["Echo Unbound Tuna", 96.26, 221.64, 44803.27, 130433.38],
        ["Solus Origin Sturgeon", 112.3, 242.83, 65932.2, 246764.8],
        ["Introspect Apexvoid Manta", 125.53, 290.72, 99554.28, 205989.21],
        ["Persona Archetype Barracuda", 144.42, 332.82, 64618.08, 159987.09],
        ["Mindglass Meta Swordfish", 153.48, 401.8, 91894.04, 282818.22],
        ["Narcissus Eschaton Coelacanth", 163.37, 401, 121495.24, 246135.17],
        ["Interior Zeropoint Leviathan", 176.33, 449.56, 119645.18, 295331.04],
        ["Facet Cosmic Wyrm", 188.69, 509.95, 117640.47, 301937.36],
        ["Replica Transcendent Colossus", 203.44, 524.55, 152650.88, 337520.72],
        ["Lonewave Abyssal Behemoth", 218.55, 564.91, 134615.91, 241288.75],
        ["Selfsame Godfold Monarch", 232.54, 579.67, 177953.6, 396472.99],
        ["Gaze Mythborn Paragon", 246.55, 692.34, 142525.13, 448767.84]
    ]

};
