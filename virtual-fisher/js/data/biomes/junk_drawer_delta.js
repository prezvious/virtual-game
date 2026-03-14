/**
 * JUNK DRAWER DELTA - Fish Data
 * Format: [name, minWeight, maxWeight, minPrice, maxPrice]
 */

const FISH_JUNK_DRAWER_DELTA = {
    common: [
        ["Battery Drift Minnow", 0.21, 0.38, 11.65, 34.72],
        ["Copper Ripple Smelt", 0.27, 0.5, 14.7, 50.58],
        ["Keyring Wake Darter", 0.27, 0.62, 11.18, 35.42],
        ["Paperclip Current Chub", 0.35, 0.81, 13.6, 49.03],
        ["Staple Foam Loach", 0.36, 0.87, 21.26, 57.74],
        ["Screw Mist Bream", 0.41, 1.04, 25.38, 49.46],
        ["Washer Glimmer Trout", 0.45, 1.02, 25.51, 79.76],
        ["Coil Sway Guppy", 0.51, 1.14, 27.63, 69.84],
        ["Wire Trace Perch", 0.53, 1.43, 28.94, 95],
        ["Circuit Whorl Shiner", 0.6, 1.6, 29.86, 65.6],
        ["Drawer Flow Carp", 0.65, 1.63, 24.72, 74.56],
        ["Magnet Pulse Eel", 0.67, 1.83, 34.17, 85.89],
        ["Nickel Glint Gar", 0.7, 1.99, 29.18, 56.04],
        ["Loosepart Lilt Ray", 0.78, 1.93, 46.98, 85.01],
        ["Sparkplug Bloom Snapper", 0.82, 1.96, 51.85, 102.64]
    ],

    uncommon: [
        ["Battery Glide Perch", 1.12, 1.99, 106.7, 403.15],
        ["Copper Arc Carp", 1.38, 2.65, 143.41, 364.75],
        ["Keyring Spiral Pike", 1.57, 3, 137.25, 254.77],
        ["Paperclip Flux Catfish", 1.64, 3.57, 168.13, 511.88],
        ["Staple Echo Grouper", 1.93, 4.34, 126.22, 321.91],
        ["Screw Glare Salmon", 1.97, 4.73, 114.04, 288.54],
        ["Washer Bend Arowana", 2.27, 5.76, 236.18, 586.65],
        ["Coil Sweep Sturgeon", 2.48, 6.3, 223.58, 701.09],
        ["Wire Orbit Manta", 2.69, 6.12, 217.02, 744.94],
        ["Circuit Volley Barracuda", 2.92, 6.63, 187.78, 406.89],
        ["Drawer Shift Mackerel", 2.98, 8.03, 287.76, 663.98],
        ["Magnet Weave Swordfish", 3.14, 8.33, 198.92, 441.21],
        ["Nickel Vault Tuna", 3.51, 9.67, 211.57, 567],
        ["Loosepart Ridge Coelacanth", 3.69, 10.11, 387.3, 1299.33],
        ["Sparkplug Surge Leviathan", 3.77, 9.58, 221.73, 500.67]
    ],

    rare: [
        ["Battery Fringe Trout", 2.89, 5.37, 455.42, 1208.07],
        ["Copper Halo Pike", 3.76, 7.5, 647.65, 2126.06],
        ["Keyring Prism Catfish", 4.27, 9.14, 539.61, 1401.98],
        ["Paperclip Nova Grouper", 4.64, 10.04, 628.01, 1846.58],
        ["Staple Paradox Eel", 5.42, 13.15, 508.85, 1151.49],
        ["Screw Vector Ray", 6.04, 14.44, 785.65, 2615.46],
        ["Washer Axiom Arowana", 7.09, 17.65, 917.78, 2907.16],
        ["Coil Quill Mackerel", 7.42, 19.01, 1144.58, 2146.14],
        ["Wire Ember Marlin", 7.96, 19.48, 893.08, 1860],
        ["Circuit Mirage Shark", 8.6, 20.24, 875.16, 1735.12],
        ["Drawer Rift Tuna", 9.27, 23.41, 1300.2, 3547.47],
        ["Magnet Cipherline Sturgeon", 10.01, 23.5, 1549.33, 5644.29],
        ["Nickel Vortex Manta", 10.45, 29.12, 1672.26, 5446.58],
        ["Loosepart Cipher Swordfish", 11.32, 31.29, 1148.22, 3272.2],
        ["Sparkplug Phantom Leviathan", 11.72, 30.4, 1480.98, 4702.55]
    ],

    epic: [
        ["Battery Dominion Gar", 9.81, 16.17, 2644.2, 7688.55],
        ["Copper Maelstrom Snapper", 10.89, 21.03, 2281.68, 7351.15],
        ["Keyring Supra Eel", 13.28, 27.63, 2547.75, 6940.5],
        ["Paperclip Arcane Ray", 13.87, 30.27, 3201.53, 9004.04],
        ["Staple Dynast Arowana", 15.88, 35.82, 2461.71, 6259.45],
        ["Screw Monolith Mackerel", 17.87, 44.27, 4221.37, 13616.03],
        ["Washer Oblivion Marlin", 18.78, 47.79, 5002.61, 11591.04],
        ["Coil Catalyst Shark", 20.42, 46.81, 3821.68, 11453.83],
        ["Wire Overtide Tuna", 22.36, 57.84, 5025.24, 11726.53],
        ["Circuit Hyperion Sturgeon", 23.11, 56.43, 4077.2, 15154.2],
        ["Drawer Zenith Manta", 25.35, 68.77, 6411.08, 24665.61],
        ["Magnet Cataclysm Barracuda", 27.72, 67.47, 4728.59, 10795.4],
        ["Nickel Crown Swordfish", 29.25, 76.68, 5725.67, 20637.66],
        ["Loosepart Titan Coelacanth", 30.8, 83.85, 7056.87, 21706.65],
        ["Sparkplug Apex Leviathan", 32.93, 80.9, 7394.47, 15264.19]
    ],

    legendary: [
        ["Battery Ancestral Snapper", 26.53, 44.12, 10895.7, 31791.09],
        ["Copper Grand Arowana", 29.89, 59.16, 10277.74, 18505.8],
        ["Keyring Luminous Mackerel", 33.28, 75.19, 11750.65, 25911.67],
        ["Paperclip Imperial Marlin", 37.15, 89.35, 10286.48, 39125.89],
        ["Staple Epoch Shark", 46.67, 105.56, 16878.62, 46046.16],
        ["Screw Absolute Tuna", 50.3, 114.5, 14363.47, 27555.45],
        ["Washer Myriad Sturgeon", 54.41, 124.33, 23391.56, 79540.32],
        ["Coil Paragon Manta", 57.13, 153.1, 25777.17, 98826.15],
        ["Wire Oracle Barracuda", 61.47, 146.01, 21779.84, 48620.74],
        ["Circuit Ascendant Swordfish", 68.46, 166.83, 21217.44, 39451.17],
        ["Drawer Inviolable Coelacanth", 73.97, 198.87, 32982.99, 70139.83],
        ["Magnet Eternal Leviathan", 78.21, 202.94, 33576.25, 99736.48],
        ["Nickel Sovereign Wyrm", 81.76, 201.32, 39126.43, 143413.76],
        ["Loosepart Prime Colossus", 88.09, 220.43, 30046.53, 68369.54],
        ["Sparkplug Celestial Behemoth", 94.47, 248.48, 25916.65, 80867.38]
    ],

    mythic: [
        ["Battery Impossible Arowana", 58.49, 95.53, 46074.81, 93178.14],
        ["Copper Infinite Marlin", 74.33, 135.19, 32179.88, 90862.39],
        ["Keyring Singularity Shark", 84.23, 188.44, 44736.45, 88864.71],
        ["Paperclip Unbound Tuna", 95.96, 212.39, 43985.48, 159679],
        ["Staple Origin Sturgeon", 113.26, 256.12, 85892.79, 186870.97],
        ["Screw Apexvoid Manta", 125.66, 315.36, 71591.77, 245759.92],
        ["Washer Archetype Barracuda", 132.33, 340.1, 76168.57, 239984.43],
        ["Coil Meta Swordfish", 154.05, 371.5, 104493.62, 257630.09],
        ["Wire Eschaton Coelacanth", 161, 377.79, 79449.37, 228745.49],
        ["Circuit Zeropoint Leviathan", 181.72, 454.01, 131496.58, 401177.3],
        ["Drawer Cosmic Wyrm", 196.32, 460.1, 119175.49, 379334.83],
        ["Magnet Transcendent Colossus", 202.15, 542.81, 131319.44, 337421.66],
        ["Nickel Abyssal Behemoth", 215.93, 575.2, 154828.69, 441748.1],
        ["Loosepart Godfold Monarch", 228.89, 622.76, 141644.91, 278974.2],
        ["Sparkplug Mythborn Paragon", 248.33, 614.31, 159047.39, 450986.1]
    ]

};
