/**
 * FISH DATABASE ASSEMBLER
 * Combines all individual biome fish data into a unified FISH_DB constant.
 * Each biome file defines a FISH_<BIOME> constant that is referenced here.
 */

const FISH_DB = {
    mistvale: FISH_MISTVALE,
    stone_rapids: FISH_STONE_RAPIDS,
    volcanic: FISH_VOLCANIC,
    emerald: FISH_EMERALD,
    midnight: FISH_MIDNIGHT,
    crystalline_abyss: FISH_CRYSTALLINE_ABYSS,
    skyhollow_reaches: FISH_SKYHOLLOW_REACHES,
    resonant_depths: FISH_RESONANT_DEPTHS,
    mycelial_depths: FISH_MYCELIAL_DEPTHS,
    sunken_citadel: FISH_SUNKEN_CITADEL,
    glacial_spire: FISH_GLACIAL_SPIRE,
    chrono_river: FISH_CHRONO_RIVER,
    neon_bayou: FISH_NEON_BAYOU,
    gearwork_grotto: FISH_GEARWORK_GROTTO,
    aetherial_void: FISH_AETHERIAL_VOID,
    confection_coast: FISH_CONFECTION_COAST,
    origami_archipelago: FISH_ORIGAMI_ARCHIPELAGO,
    vaporwave_vista: FISH_VAPORWAVE_VISTA,
    prism_light_pools: FISH_PRISM_LIGHT_POOLS,
    silk_thread_stream: FISH_SILK_THREAD_STREAM,
    ferromagnetic_falls: FISH_FERROMAGNETIC_FALLS,
    amber_aquifer: FISH_AMBER_AQUIFER,
    tar_pit_tributary: FISH_TAR_PIT_TRIBUTARY,
    ossuary_ocean: FISH_OSSUARY_OCEAN,
    cellular_sea: FISH_CELLULAR_SEA,
    isotope_estuary: FISH_ISOTOPE_ESTUARY,
    transmutation_tide: FISH_TRANSMUTATION_TIDE,
    steeped_springs: FISH_STEEPED_SPRINGS,
    pigment_peninsula: FISH_PIGMENT_PENINSULA,
    porcelain_ponds: FISH_PORCELAIN_PONDS,
    celluloid_cenote: FISH_CELLULOID_CENOTE,
    stained_glass_sanctuary: FISH_STAINED_GLASS_SANCTUARY,
    cartographers_cove: FISH_CARTOGRAPHERS_COVE,
    aromatic_archipelago: FISH_AROMATIC_ARCHIPELAGO,
    carnivorous_canopy: FISH_CARNIVOROUS_CANOPY,
    pollen_ponds: FISH_POLLEN_PONDS,
    nectar_nexus: FISH_NECTAR_NEXUS,
    petrified_peat_bog: FISH_PETRIFIED_PEAT_BOG,
    thorn_thicket_trench: FISH_THORN_THICKET_TRENCH,
    quantum_superposition_sea: FISH_QUANTUM_SUPERPOSITION_SEA,
    bathtub_billows: FISH_BATHTUB_BILLOWS,
    somnambulist_shallows: FISH_SOMNAMBULIST_SHALLOWS,
    tabletop_trench: FISH_TABLETOP_TRENCH,
    silhouette_strait: FISH_SILHOUETTE_STRAIT,
    typography_trench: FISH_TYPOGRAPHY_TRENCH,
    broth_basin: FISH_BROTH_BASIN,
    ectoplasmic_eddy: FISH_ECTOPLASMIC_EDDY,
    mandelbrot_maelstrom: FISH_MANDELBROT_MAELSTROM,
    mobius_strip_stream: FISH_MOBIUS_STRIP_STREAM,
    fibonacci_floodplain: FISH_FIBONACCI_FLOODPLAIN,
    tesseract_trench: FISH_TESSERACT_TRENCH,
    attic_dust_sea: FISH_ATTIC_DUST_SEA,
    junk_drawer_delta: FISH_JUNK_DRAWER_DELTA,
    static_carpet_shallows: FISH_STATIC_CARPET_SHALLOWS,
    refrigerator_rill: FISH_REFRIGERATOR_RILL,
    sea_of_solipsism: FISH_SEA_OF_SOLIPSISM,
    utilitarian_utopia: FISH_UTILITARIAN_UTOPIA,
    nihilists_null: FISH_NIHILISTS_NULL,
    hedonists_haven: FISH_HEDONISTS_HAVEN,
    ship_of_theseus_shoals: FISH_SHIP_OF_THESEUS_SHOALS
};

// Freeze fish database to prevent console exploits
deepFreeze(FISH_DB);


