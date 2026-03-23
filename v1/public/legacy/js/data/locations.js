/**
 * LOCATION DEFINITIONS
 * All fishing locations/biomes with their name, description, and theme colors.
 */

const LOCATIONS = {
    mistvale: {
        name: "Mistvale Lake",
        desc: "A serene lake shrouded in perpetual morning mist.",
        colors: ["#e0f7fa", "#b2ebf2"]
    },
    stone_rapids: {
        name: "Stone Rapids",
        desc: "Fast-flowing waters carving through ancient granite.",
        colors: ["#eceff1", "#cfd8dc"]
    },
    volcanic: {
        name: "Volcanic Bay",
        desc: "Boiling waters rich with minerals and danger.",
        colors: ["#ffe0b2", "#ffcc80"]
    },
    emerald: {
        name: "Emerald Basin",
        desc: "Lush, overgrown waters hiding massive beasts.",
        colors: ["#c8e6c9", "#a5d6a7"]
    },
    midnight: {
        name: "Midnight Ocean",
        desc: "Deep, dark waters where bioluminescence rules.",
        colors: ["#d1c4e9", "#b39ddb"]
    },
    crystalline_abyss: {
        name: "Crystalline Abyss",
        desc: "Geometric caverns where light refracts through living crystal formations, creating impossible colors and temporal distortions.",
        colors: ["#f8bbd0", "#f48fb1"]
    },
    skyhollow_reaches: {
        name: "Skyhollow Reaches",
        desc: "Floating islands suspended above an endless sky, where water defies gravity and clouds form living ecosystems beneath crystalline equilibrium.",
        colors: ["#bbdefb", "#90caf9"]
    },
    resonant_depths: {
        name: "Resonant Depths",
        desc: "Subterranean underwater caverns where sound materializes into visible harmonics, and every movement creates symphonic ripples through sentient waters.",
        colors: ["#b2dfdb", "#80cbc4"]
    },
    mycelial_depths: {
        name: "Mycelial Depths",
        desc: "An underground civilization of bioluminescent fungal forests where spore clouds drift like clouds. Waters shimmer with ethereal light from countless living organisms.",
        colors: ["#e1bee7", "#ce93d8"]
    },
    sunken_citadel: {
        name: "Sunken Citadel",
        desc: "The ruins of an advanced civilization lie submerged beneath crystalline waters. Ancient architecture blends seamlessly with coral growth.",
        colors: ["#cfd8dc", "#b0bec5"]
    },
    glacial_spire: {
        name: "Glacial Spire",
        desc: "Towering frozen peaks where the water is supercooled and the aurora borealis touches the surface.",
        colors: ["#e3f2fd", "#ffffff"]
    },
    chrono_river: {
        name: "Chrono-River",
        desc: "A river flowing backwards through time, surrounded by golden dunes and floating hourglasses.",
        colors: ["#fff9c4", "#fbc02d"]
    },
    neon_bayou: {
        name: "Neon Bayou",
        desc: "A synthetic wetland lit by holographic advertisements and leaking coolant streams.",
        colors: ["#ea80fc", "#8c9eff"]
    },
    gearwork_grotto: {
        name: "Gearwork Grotto",
        desc: "An industrial cavern filled with grinding gears, steam vents, and oil-slicked waters.",
        colors: ["#d7ccc8", "#a1887f"]
    },
    aetherial_void: {
        name: "Aetherial Void",
        desc: "The edge of the universe where stars are born. You aren't fishing in water, but in pure stardust.",
        colors: ["#311b92", "#000000"]
    },
    confection_coast: {
        name: "Confection Coast",
        desc: "A sugary paradise where the waves are made of warm syrup and the sand is pure powdered sugar.",
        colors: ["#ffb7b2", "#b5ead7"]
    },
    origami_archipelago: {
        name: "Origami Archipelago",
        desc: "A delicate world of folded parchment and ink, where paper cranes nest in cardboard cliffs.",
        colors: ["#fdfbf7", "#9a8c98"]
    },
    vaporwave_vista: {
        name: "Vaporwave Vista",
        desc: "An eternal 80s sunset over a wireframe ocean, humming with low-fidelity synth nostalgia.",
        colors: ["#e0bbe4", "#ffdfd3"]
    },
    prism_light_pools: {
        name: "Prism-Light Pools",
        desc: "Blindingly clear shallows where light shatters into rainbows across mirror-smooth surfaces.",
        colors: ["#ffffff", "#e6e6fa"]
    },
    silk_thread_stream: {
        name: "Silk-Thread Stream",
        desc: "A river composed of millions of flowing golden threads, woven by the hands of unseen giants.",
        colors: ["#fff9c4", "#d1c4e9"]
    },
    ferromagnetic_falls: {
        name: "Ferromagnetic Falls",
        desc: "Pitch-black ferrofluid currents bend and surge under unstable magnetic fields.",
        colors: ["#1a1a1a", "#b3b3b3"]
    },
    amber_aquifer: {
        name: "Amber Aquifer",
        desc: "Ancient golden sap traps life in viscous time-locked channels.",
        colors: ["#ff8f00", "#ffe082"]
    },
    tar_pit_tributary: {
        name: "Tar-Pit Tributary",
        desc: "Boiling asphalt and suction-heavy currents hide prehistoric predators.",
        colors: ["#212121", "#424242"]
    },
    ossuary_ocean: {
        name: "Ossuary Ocean",
        desc: "Milky calcium tides roll over vast reefs of bones and leviathan remains.",
        colors: ["#e0e0e0", "#8d6e63"]
    },
    cellular_sea: {
        name: "Cellular Sea",
        desc: "A giant petri-dish ocean where life multiplies and mutates in real time.",
        colors: ["#76ff03", "#69f0ae"]
    },
    isotope_estuary: {
        name: "Isotope Estuary",
        desc: "Cherenkov-green waters glow with radioactive drift and unstable mutations.",
        colors: ["#ccff00", "#111111"]
    },
    transmutation_tide: {
        name: "Transmutation Tide",
        desc: "A boiling alchemical sea where metal life evolves during the reel.",
        colors: ["#ffd700", "#9c27b0"]
    },
    steeped_springs: {
        name: "Steeped Springs",
        desc: "Fragrant matcha steam rises over hyperactive herbal pools.",
        colors: ["#33691e", "#aed581"]
    },
    pigment_peninsula: {
        name: "Pigment Peninsula",
        desc: "Tides look like living brushstrokes that never dry.",
        colors: ["#ff007f", "#00e5ff"]
    },
    porcelain_ponds: {
        name: "Porcelain Ponds",
        desc: "Smooth white basins split by glowing gold fracture lines.",
        colors: ["#fafafa", "#ffb300"]
    },
    celluloid_cenote: {
        name: "Celluloid Cenote",
        desc: "A sepia sinkhole where motion jitters like old projector footage.",
        colors: ["#705a45", "#d6c4a8"]
    },
    stained_glass_sanctuary: {
        name: "Stained-Glass Sanctuary",
        desc: "Refracted ruby and cobalt light dances through glass reefs.",
        colors: ["#b71c1c", "#01579b"]
    },
    cartographers_cove: {
        name: "Cartographer's Cove",
        desc: "Topographic grids ripple across parchment-toned waters.",
        colors: ["#ffecb3", "#bcaaa4"]
    },
    aromatic_archipelago: {
        name: "Aromatic Archipelago",
        desc: "Lavender and rose vapor rises from translucent oil seas.",
        colors: ["#f8bbd0", "#e1bee7"]
    },
    carnivorous_canopy: {
        name: "Carnivorous Canopy",
        desc: "Acidic pools form inside massive carnivorous flora.",
        colors: ["#b71c1c", "#33691e"]
    },
    pollen_ponds: {
        name: "Pollen Ponds",
        desc: "A fluid sea of pollen erupts into golden clouds each cast.",
        colors: ["#fbc02d", "#fff9c4"]
    },
    nectar_nexus: {
        name: "Nectar Nexus",
        desc: "Sticky neon nectar glows beneath giant flower petals.",
        colors: ["#ff4081", "#ea80fc"]
    },
    petrified_peat_bog: {
        name: "Petrified Peat-Bog",
        desc: "A root-heavy marsh bubbles with trapped ancient gases.",
        colors: ["#3e2723", "#1b5e20"]
    },
    thorn_thicket_trench: {
        name: "Thorn-Thicket Trench",
        desc: "A dense thorn maze where every path threatens your line.",
        colors: ["#212121", "#880e4f"]
    },
    quantum_superposition_sea: {
        name: "Quantum Superposition Sea",
        desc: "Everything flickers until your catch event defines reality.",
        colors: ["#000000", "#ffffff"]
    },
    bathtub_billows: {
        name: "Bathtub Billows",
        desc: "Foam swells crash between glossy tile canyons.",
        colors: ["#e0f7fa", "#ffffff"]
    },
    somnambulist_shallows: {
        name: "Somnambulist Shallows",
        desc: "Melting clocks and impossible doors drift through dreamwater.",
        colors: ["#4a148c", "#b388ff"]
    },
    tabletop_trench: {
        name: "Tabletop Trench",
        desc: "Catch rates surge and crash with invisible table rolls.",
        colors: ["#1b5e20", "#f44336"]
    },
    silhouette_strait: {
        name: "Silhouette Strait",
        desc: "A flat realm of black forms crossing a blinding white field.",
        colors: ["#000000", "#ffffff"]
    },
    typography_trench: {
        name: "Typography Trench",
        desc: "Sentences and symbols jump from an ocean of language.",
        colors: ["#263238", "#cfd8dc"]
    },
    broth_basin: {
        name: "Broth Basin",
        desc: "A savory sea where spice islands float in simmering stock.",
        colors: ["#d84315", "#ffcc80"]
    },
    ectoplasmic_eddy: {
        name: "Ectoplasmic Eddy",
        desc: "No water remains, only spectral vapor and glitching echoes.",
        colors: ["#84ffff", "#1de9b6"]
    },
    mandelbrot_maelstrom: {
        name: "Mandelbrot Maelstrom",
        desc: "Each wave contains a smaller copy of the same whirlpool.",
        colors: ["#6200ea", "#00bfff"]
    },
    mobius_strip_stream: {
        name: "Mobius Strip Stream",
        desc: "Cast too far and your hook returns from behind you.",
        colors: ["#ff5722", "#607d8b"]
    },
    fibonacci_floodplain: {
        name: "Fibonacci Floodplain",
        desc: "Ripples and migration patterns obey sequence mathematics.",
        colors: ["#ffd54f", "#5d4037"]
    },
    tesseract_trench: {
        name: "Tesseract Trench",
        desc: "Bobbers appear in impossible axes beyond normal space.",
        colors: ["#00e676", "#1a237e"]
    },
    attic_dust_sea: {
        name: "Attic Dust-Sea",
        desc: "Sunbeams cut through a dry ocean of drifting dust.",
        colors: ["#9e9e9e", "#795548"]
    },
    junk_drawer_delta: {
        name: "Junk Drawer Delta",
        desc: "Metallic swamps surge with erratic magnetic currents.",
        colors: ["#757575", "#ff9800"]
    },
    static_carpet_shallows: {
        name: "Static-Carpet Shallows",
        desc: "Towering carpet fibers spark with high-voltage static.",
        colors: ["#d32f2f", "#ffeb3b"]
    },
    refrigerator_rill: {
        name: "Refrigerator Rill",
        desc: "A sterile tundra forms among frozen leftovers and freon mist.",
        colors: ["#b2ebf2", "#c5e1a5"]
    },
    sea_of_solipsism: {
        name: "Sea of Solipsism",
        desc: "A flawless mirror-ocean reflects only the player.",
        colors: ["#eceff1", "#b0bec5"]
    },
    utilitarian_utopia: {
        name: "Utilitarian Utopia",
        desc: "A sterile world where every movement is utility-calculated.",
        colors: ["#fafafa", "#90caf9"]
    },
    nihilists_null: {
        name: "Nihilist's Null",
        desc: "A featureless void with no music, weather, or resistance.",
        colors: ["#424242", "#212121"]
    },
    hedonists_haven: {
        name: "Hedonist's Haven",
        desc: "Violent color shifts amplify risk and reward in every moment.",
        colors: ["#d50000", "#aa00ff"]
    },
    ship_of_theseus_shoals: {
        name: "Ship of Theseus Shoals",
        desc: "A vortex of planks and nails questions what remains the same.",
        colors: ["#8d6e63", "#546e7a"]
    }
};

// Freeze locations to prevent console exploits
deepFreeze(LOCATIONS);



