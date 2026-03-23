// ==================== GAME STATE ====================
let game = null;
let stats = null;
let cooldownActive = false;
let cooldownEndTime = 0;
let autoFarmInterval = null;
let autoFarmActive = false;
let autoFarmSessionHarvests = 0;
let localSaveTimestamp = 0;

function getDefaultGame() {
    return {
        balance: 0,
        xp: 0,
        prestigeLevel: 0,
        prestigeBonus: 0,
        currentHoeIndex: 0,
        selectedHoeIndex: 0,
        unlockedHoes: [0],
        selectedFertilizer: "none",
        fertilizers: {},
        upgrades: {},
        inventory: {},
        achievements: []
    };
}

function getDefaultStats() {
    return {
        totalFarms: 0,
        totalPlantsHarvested: 0,
        totalEarned: 0,
        totalSpent: 0,
        totalFertilizerUsed: 0,
        bestYield: 0,
        bestSale: 0,
        uniquePlantsHarvested: 0,
        legendaryHarvested: 0,
        sessionFarms: 0,
        plantsHarvestedTypes: {}
    };
}

function sanitizeNonNegativeNumber(value, fallback = 0) {
    const num = Number(value);
    return Number.isFinite(num) && num >= 0 ? num : fallback;
}

function sanitizeNonNegativeInt(value, fallback = 0, max = Number.MAX_SAFE_INTEGER) {
    const num = Math.floor(sanitizeNonNegativeNumber(value, fallback));
    return Math.min(num, max);
}

function sanitizeLoadedGame(rawGame) {
    const source = (rawGame && typeof rawGame === "object") ? rawGame : {};
    const clean = getDefaultGame();

    clean.balance = sanitizeNonNegativeNumber(source.balance, 0);
    clean.xp = sanitizeNonNegativeInt(source.xp, 0);
    clean.prestigeLevel = sanitizeNonNegativeInt(source.prestigeLevel, 0, 1000000);
    clean.prestigeBonus = sanitizeNonNegativeNumber(source.prestigeBonus, clean.prestigeLevel * 2);

    const unlockedSource = Array.isArray(source.unlockedHoes) ? source.unlockedHoes : [0];
    const unlockedSet = new Set();
    for (const index of unlockedSource) {
        const sanitizedIndex = sanitizeNonNegativeInt(index, -1, HOES.length - 1);
        if (sanitizedIndex >= 0 && sanitizedIndex < HOES.length) unlockedSet.add(sanitizedIndex);
    }
    unlockedSet.add(0);
    clean.unlockedHoes = Array.from(unlockedSet).sort((a, b) => a - b);

    const selectedHoe = sanitizeNonNegativeInt(source.selectedHoeIndex, 0, HOES.length - 1);
    clean.selectedHoeIndex = clean.unlockedHoes.includes(selectedHoe) ? selectedHoe : clean.unlockedHoes[0];
    const currentHoe = sanitizeNonNegativeInt(source.currentHoeIndex, clean.selectedHoeIndex, HOES.length - 1);
    clean.currentHoeIndex = clean.unlockedHoes.includes(currentHoe) ? currentHoe : clean.selectedHoeIndex;

    const fertilizersSource = (source.fertilizers && typeof source.fertilizers === "object") ? source.fertilizers : {};
    for (const fertilizer of FERTILIZERS) {
        clean.fertilizers[fertilizer.name] = sanitizeNonNegativeInt(fertilizersSource[fertilizer.name], 0);
    }

    const selectedFertilizer = typeof source.selectedFertilizer === "string" ? source.selectedFertilizer : "none";
    const validFertilizer =
        selectedFertilizer === "none" || FERTILIZERS.some(f => f.name === selectedFertilizer);
    clean.selectedFertilizer = validFertilizer ? selectedFertilizer : "none";
    if (clean.selectedFertilizer !== "none" && clean.fertilizers[clean.selectedFertilizer] <= 0) {
        clean.selectedFertilizer = "none";
    }

    const upgradesSource = (source.upgrades && typeof source.upgrades === "object") ? source.upgrades : {};
    for (const upgrade of UPGRADES) {
        clean.upgrades[upgrade.id] = sanitizeNonNegativeInt(upgradesSource[upgrade.id], 0, upgrade.maxLevel);
    }

    const inventorySource = (source.inventory && typeof source.inventory === "object") ? source.inventory : {};
    for (const plant of PLANTS) {
        clean.inventory[plant.name] = sanitizeNonNegativeInt(inventorySource[plant.name], 0);
    }

    const achievementIds = new Set(ACHIEVEMENTS.map(a => a.id));
    const achievementsSource = Array.isArray(source.achievements) ? source.achievements : [];
    clean.achievements = Array.from(new Set(
        achievementsSource.filter(id => typeof id === "string" && achievementIds.has(id))
    ));

    return clean;
}

function sanitizeLoadedStats(rawStats) {
    const source = (rawStats && typeof rawStats === "object") ? rawStats : {};
    const clean = getDefaultStats();

    clean.totalFarms = sanitizeNonNegativeInt(source.totalFarms, 0);
    clean.totalPlantsHarvested = sanitizeNonNegativeInt(source.totalPlantsHarvested, 0);
    clean.totalEarned = sanitizeNonNegativeNumber(source.totalEarned, 0);
    clean.totalSpent = sanitizeNonNegativeNumber(source.totalSpent, 0);
    clean.totalFertilizerUsed = sanitizeNonNegativeInt(source.totalFertilizerUsed, 0);
    clean.bestYield = sanitizeNonNegativeInt(source.bestYield, 0);
    clean.bestSale = sanitizeNonNegativeNumber(source.bestSale, 0);
    clean.legendaryHarvested = sanitizeNonNegativeInt(source.legendaryHarvested, 0);
    clean.sessionFarms = 0; // Session-only metric; never restored from save

    const harvestedTypes = (source.plantsHarvestedTypes && typeof source.plantsHarvestedTypes === "object")
        ? source.plantsHarvestedTypes
        : {};
    for (const plant of PLANTS) {
        clean.plantsHarvestedTypes[plant.name] = sanitizeNonNegativeInt(harvestedTypes[plant.name], 0);
    }

    clean.uniquePlantsHarvested = PLANTS.reduce((count, plant) => {
        return count + (clean.plantsHarvestedTypes[plant.name] > 0 ? 1 : 0);
    }, 0);

    const trackedPlantTotal = Object.values(clean.plantsHarvestedTypes).reduce((sum, qty) => sum + qty, 0);
    clean.totalPlantsHarvested = Math.max(clean.totalPlantsHarvested, trackedPlantTotal);

    return clean;
}

function getSerializableStats() {
    return { ...stats, sessionFarms: 0 };
}

function initGame() {
    FERTILIZERS.forEach(f => {
        if (game.fertilizers[f.name] === undefined) game.fertilizers[f.name] = 0;
    });
    UPGRADES.forEach(u => {
        if (game.upgrades[u.id] === undefined) game.upgrades[u.id] = 0;
    });
    PLANTS.forEach(p => {
        if (game.inventory[p.name] === undefined) game.inventory[p.name] = 0;
        if (stats.plantsHarvestedTypes[p.name] === undefined) stats.plantsHarvestedTypes[p.name] = 0;
    });
}

// ==================== NUMBER FORMATTING ====================
function formatNumber(num) {
    if (num < 1000) return Math.floor(num).toLocaleString();
    if (num < 1000000) return (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
    if (num < 1e9) return (num / 1e6).toFixed(2).replace(/\.00$/, '').replace(/(\..\d)0$/, '$1') + ' million';
    if (num < 1e12) return (num / 1e9).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' billion';
    if (num < 1e15) return (num / 1e12).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' trillion';
    if (num < 1e18) return (num / 1e15).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' quadrillion';
    if (num < 1e21) return (num / 1e18).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' quintillion';
    if (num < 1e24) return (num / 1e21).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' sextillion';
    return (num / 1e24).toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1') + ' septillion';
}

function formatMoney(num) {
    return '$' + formatNumber(num);
}

// ==================== SAVE/LOAD ====================
function buildSaveDataPayload() {
    return {
        game,
        stats: getSerializableStats(),
        autoFarmState: loadAutoFarmState() || { enabled: autoFarmActive, lastTick: Date.now() },
        version: 2,
        timestamp: Date.now()
    };
}

function getProgressSnapshotForCloud() {
    const payload = buildSaveDataPayload();
    return {
        ...payload,
        totalPlants: getTotalPlants()
    };
}

function queueCloudProgressSave(immediate = false) {
    const supabaseApi = window.VirtualFarmerSupabase;
    if (!supabaseApi || !supabaseApi.isAuthenticated()) return;
    supabaseApi.queueSave(getProgressSnapshotForCloud(), { immediate });
}

function applyCloudProgressRow(progressRow) {
    if (!progressRow || typeof progressRow !== "object") return false;

    game = sanitizeLoadedGame(progressRow.game_state);
    stats = sanitizeLoadedStats(progressRow.stats_state);

    if (progressRow.auto_farm_state && typeof progressRow.auto_farm_state === "object") {
        const enabled = Boolean(progressRow.auto_farm_state.enabled);
        const lastTick = Number(progressRow.auto_farm_state.lastTick);
        localStorage.setItem('autoFarmState', JSON.stringify({
            enabled,
            lastTick: Number.isFinite(lastTick) && lastTick > 0 ? Math.floor(lastTick) : Date.now()
        }));
    }

    const cloudTimestamp = Date.parse(progressRow.last_saved_at || progressRow.updated_at || "");
    localSaveTimestamp = Number.isFinite(cloudTimestamp) ? cloudTimestamp : Date.now();
    initGame();
    return true;
}

async function syncProgressWithCloud() {
    const supabaseApi = window.VirtualFarmerSupabase;
    if (!supabaseApi || !supabaseApi.isAuthenticated()) return;

    try {
        const cloudRow = await supabaseApi.loadProgress();
        if (!cloudRow) {
            await supabaseApi.saveProgress(getProgressSnapshotForCloud());
            return;
        }

        const cloudTimestamp = Date.parse(cloudRow.last_saved_at || cloudRow.updated_at || "");
        const normalizedCloudTimestamp = Number.isFinite(cloudTimestamp) ? cloudTimestamp : 0;

        if (normalizedCloudTimestamp > localSaveTimestamp) {
            if (applyCloudProgressRow(cloudRow)) {
                saveGame({ skipCloud: true });
                showNotification("Cloud save loaded.", "achievement");
            }
            return;
        }

        if (localSaveTimestamp >= normalizedCloudTimestamp) {
            await supabaseApi.saveProgress(getProgressSnapshotForCloud());
        }
    } catch (error) {
        console.error("Cloud sync failed:", error);
        showNotification("Cloud sync failed. Using local save.", "common");
    }
}

function saveGame(options = {}) {
    const saveOptions = (options && typeof options === "object") ? options : {};
    const skipCloud = Boolean(saveOptions.skipCloud);
    const immediateCloud = Boolean(saveOptions.immediateCloud);

    try {
        const saveData = buildSaveDataPayload();
        localStorage.setItem('virtualFarmerSave', JSON.stringify(saveData));
        localSaveTimestamp = saveData.timestamp;

        if (!skipCloud) {
            queueCloudProgressSave(immediateCloud);
        }
    } catch (e) {
        console.error("Save failed:", e);
    }
}

function loadGame() {
    try {
        const savedData = localStorage.getItem('virtualFarmerSave');
        if (savedData) {
            const parsed = JSON.parse(savedData);
            if (parsed.game && typeof parsed.game === "object") {
                game = sanitizeLoadedGame(parsed.game);
                stats = sanitizeLoadedStats(parsed.stats);
                localSaveTimestamp = sanitizeNonNegativeInt(parsed.timestamp, 0);
            } else {
                throw new Error("Invalid save structure");
            }
        } else {
            game = getDefaultGame();
            stats = getDefaultStats();
            localSaveTimestamp = 0;
        }
    } catch (e) {
        console.error("Load failed:", e);
        game = getDefaultGame();
        stats = getDefaultStats();
        localSaveTimestamp = 0;
    }
    initGame();
}

// ==================== CALCULATIONS ====================
function getUpgradeCost(upgrade, level) {
    return Math.floor(upgrade.baseCost * Math.pow(5.15, level));
}

function calculateYield({ suppressNotifications = false } = {}) {
    // Auto-farm must remain notification-free to avoid spam.
    const notificationsSuppressed = suppressNotifications || autoFarmActive;
    const hoe = HOES[game.selectedHoeIndex];

    // Cosmic Ray: permanently adds +0.1 to hoe multiplier per level
    let hoeMultiplier = hoe.multiplier + ((game.upgrades.cosmicRay || 0) * 0.1);

    let baseYield = 10 + game.selectedHoeIndex * 5 + Math.floor(Math.random() * 10);

    // Dark Matter Soil: +50 base yield per level
    baseYield += (game.upgrades.darkMatterSoil || 0) * 50;

    // Root Expansion: +1 yield per 100 XP
    if (game.upgrades.rootExpansion) {
        baseYield += Math.floor(game.xp / 100) * game.upgrades.rootExpansion;
    }

    // Apply hoe multiplier
    baseYield *= hoeMultiplier;

    // Prestige bonus (with Reality Anchor)
    let prestigeEffectiveness = 1 + ((game.upgrades.realityAnchor || 0) * 0.05);
    baseYield *= (1 + (game.prestigeBonus * prestigeEffectiveness) / 100);

    // Existing upgrades
    baseYield += game.upgrades.sharperTools || 0;
    baseYield += (game.upgrades.automatedSprinkler || 0) * 2;
    baseYield *= Math.pow(1.2, game.upgrades.irrigationSystem || 0);
    baseYield *= (1 + (game.upgrades.seedMultiplier || 0) * 0.05);
    baseYield *= (1 + (game.upgrades.advancedAnalytics || 0) * 0.03);

    // Fertilizer
    if (game.selectedFertilizer !== "none" && game.fertilizers[game.selectedFertilizer] > 0) {
        const fert = FERTILIZERS.find(f => f.name === game.selectedFertilizer);
        if (fert) {
            let fertBonus = fert.bonus;
            fertBonus *= (1 + (game.upgrades.fertilizerEfficiency || 0) * 0.1);
            baseYield += fertBonus;
        }
    }

    // Duplicator
    const dupChance = (game.upgrades.duplicator || 0) * 0.05;
    if (Math.random() < dupChance) baseYield *= 2;

    // Genetic Mutation: 0.5% chance per level for 10x yield
    const mutationChance = (game.upgrades.geneticMutation || 0) * 0.005;
    if (Math.random() < mutationChance) {
        baseYield *= 10;
        if (!notificationsSuppressed) {
            showNotification("GENETIC MUTATION! 10x YIELD!", "mythic");
        }
    }

    // Singularity Engine: final multiplier of 1.1x per level
    const singularityMult = Math.pow(1.1, game.upgrades.singularityEngine || 0);
    baseYield *= singularityMult;

    return Math.floor(baseYield);
}

function calculateXP() {
    let baseXP = 10 + game.selectedHoeIndex * 5 + Math.floor(Math.random() * 5);
    baseXP *= (1 + (game.upgrades.experienced || 0) * 0.2);
    baseXP *= (1 + game.prestigeBonus / 100);
    return Math.floor(baseXP);
}

function calculateSellPrice() {
    let totalValue = 0;
    let totalItems = 0;

    for (const [plantName, quantity] of Object.entries(game.inventory)) {
        if (quantity > 0) {
            totalItems += quantity;
            const plant = PLANTS.find(p => p.name === plantName);
            if (plant) totalValue += plant.price * quantity;
        }
    }

    let multiplier = 1;
    multiplier *= (1 + (game.upgrades.expertFarmer || 0) * 0.1);
    multiplier *= (1 + (game.upgrades.businessman || 0) * 0.05);
    multiplier *= (1 + (game.upgrades.marketSpecialist || 0) * 0.05);
    multiplier *= (1 + (game.upgrades.advancedAnalytics || 0) * 0.03);

    // Auto Negotiator: +2% sell price per achievement unlocked
    const achievementsUnlocked = game.achievements.length;
    multiplier *= (1 + (achievementsUnlocked * (game.upgrades.autoNegotiator || 0) * 0.02));

    // Inflation Mastery: sell price increases with total held items (max 50% at 10k items)
    if (game.upgrades.inflationMastery) {
        const inflationBonus = Math.min(totalItems / 10000, 0.5) * (game.upgrades.inflationMastery * 0.1);
        multiplier += inflationBonus;
    }

    // Tax Evasion: +10% money per level
    multiplier *= (1 + (game.upgrades.taxEvasion || 0) * 0.1);

    // Prestige effect (with Reality Anchor)
    let prestigeEffectiveness = 1 + ((game.upgrades.realityAnchor || 0) * 0.05);
    multiplier *= (1 + (game.prestigeBonus * prestigeEffectiveness) / 100);

    return Math.floor(totalValue * multiplier);
}

function getTotalPlants() {
    return Object.values(game.inventory).reduce((a, b) => a + b, 0);
}

function canPrestige() {
    return game.balance >= 5000000 || UPGRADES.every(u => game.upgrades[u.id] >= u.maxLevel);
}

// ==================== GAME ACTIONS ====================
function farm() {
    if (cooldownActive) return;

    // Time Dilator: reduce cooldown by 50ms per level (min 200ms)
    let currentCooldown = COOLDOWN_DURATION - ((game.upgrades.timeDilator || 0) * 50);
    currentCooldown = Math.max(200, currentCooldown);

    cooldownActive = true;
    cooldownEndTime = Date.now() + currentCooldown;
    updateCooldownBar(currentCooldown);

    const eligiblePlants = PLANTS.filter(p => p.minHoe <= game.selectedHoeIndex);
    const selectedPlant = eligiblePlants[Math.floor(Math.random() * eligiblePlants.length)];

    const yieldAmount = calculateYield();

    // Tax Evasion: -5% XP per level
    let xpMult = 1 - ((game.upgrades.taxEvasion || 0) * 0.05);
    const xpGained = Math.floor(calculateXP() * xpMult);

    // Fertilizer consumption
    if (game.selectedFertilizer !== "none" && game.fertilizers[game.selectedFertilizer] > 0) {
        // Dark Matter Soil: double fertilizer consumption
        let consumptionMult = (game.upgrades.darkMatterSoil > 0) ? 2 : 1;

        const consumption = (RARITY_CONSUMPTION[selectedPlant.rarity] || 1) * consumptionMult;
        const available = game.fertilizers[game.selectedFertilizer];
        let consumed = Math.min(consumption, available);

        // Recycling Protocol: chance to save fertilizer
        const recycleChance = (game.upgrades.recyclingProtocol || 0) * 0.05;
        if (Math.random() < recycleChance) {
            consumed = 0;
            showNotification("Fertilizer Recycled!", "common");
        }

        game.fertilizers[game.selectedFertilizer] -= consumed;
        stats.totalFertilizerUsed += consumed;

        if (game.fertilizers[game.selectedFertilizer] <= 0) {
            game.selectedFertilizer = "none";
        }
    }

    game.inventory[selectedPlant.name] = (game.inventory[selectedPlant.name] || 0) + yieldAmount;

    // Quantum Entanglement: chance to give 1 random owned crop
    if (game.upgrades.quantumEntanglement > 0) {
        const ownedPlants = Object.keys(game.inventory).filter(k => game.inventory[k] > 0);
        if (ownedPlants.length > 0 && Math.random() < (game.upgrades.quantumEntanglement * 0.2)) {
            const randomPlant = ownedPlants[Math.floor(Math.random() * ownedPlants.length)];
            game.inventory[randomPlant] += 1;
        }
    }

    // Treasure Hunter: chance to find direct cash
    if (game.upgrades.treasureHunter > 0) {
        if (Math.random() < (game.upgrades.treasureHunter * 0.01)) {
            const treasure = 100 * (game.selectedHoeIndex + 1) * (game.prestigeLevel + 1);
            game.balance += treasure;
            showNotification(`Found Treasure: ${formatMoney(treasure)}!`, "rare");
        }
    }

    game.xp += xpGained;

    // Update stats
    stats.totalFarms++;
    stats.sessionFarms++;
    stats.totalPlantsHarvested += yieldAmount;
    if (yieldAmount > stats.bestYield) stats.bestYield = yieldAmount;
    if (stats.plantsHarvestedTypes[selectedPlant.name] === 0) {
        stats.uniquePlantsHarvested++;
    }
    stats.plantsHarvestedTypes[selectedPlant.name] += yieldAmount;
    if (selectedPlant.rarity === "legendary") {
        stats.legendaryHarvested += yieldAmount;
    }

    showNotification(`Harvested ${formatNumber(yieldAmount)} ${selectedPlant.name}!`, selectedPlant.rarity);

    checkAchievements();
    saveGame();
    updateAllUI();
}

function sellAll() {
    const totalPlants = getTotalPlants();
    if (totalPlants === 0) {
        showNotification("No plants to sell!", "common");
        return;
    }

    const saleValue = calculateSellPrice();
    game.balance += saleValue;
    stats.totalEarned += saleValue;
    if (saleValue > stats.bestSale) stats.bestSale = saleValue;

    // Clear inventory
    for (const plant of PLANTS) {
        game.inventory[plant.name] = 0;
    }

    showNotification(`Sold for ${formatMoney(saleValue)}!`, "achievement");

    checkAchievements();
    saveGame();
    updateAllUI();
}

function buyHoe(index) {
    const hoe = HOES[index];
    if (game.unlockedHoes.includes(index)) return;

    // Lobbying: reduce hoe prices by 2% per level
    let discount = 1 - ((game.upgrades.lobbying || 0) * 0.02);
    let finalCost = Math.floor(hoe.cost * discount);

    if (game.balance < finalCost) return;

    game.balance -= finalCost;
    stats.totalSpent += finalCost;
    game.unlockedHoes.push(index);
    game.currentHoeIndex = Math.max(game.currentHoeIndex, index);

    showNotification(`Unlocked ${hoe.name}!`, "achievement");

    checkAchievements();
    saveGame();
    updateAllUI();
}

function equipHoe(index) {
    if (!game.unlockedHoes.includes(index)) return;
    game.selectedHoeIndex = index;
    saveGame();
    updateAllUI();
}

function buyFertilizer(name, amount = 1) {
    const fert = FERTILIZERS.find(f => f.name === name);
    if (!fert) return;

    const totalCost = fert.cost * amount;
    if (game.balance < totalCost) return;

    game.balance -= totalCost;
    stats.totalSpent += totalCost;
    game.fertilizers[name] = (game.fertilizers[name] || 0) + amount;

    showNotification(`Bought ${amount}x ${name}!`, "common");

    saveGame();
    updateAllUI();
}

function buyUpgrade(id) {
    const upgrade = UPGRADES.find(u => u.id === id);
    if (!upgrade) return;

    const currentLevel = game.upgrades[id] || 0;
    if (currentLevel >= upgrade.maxLevel) return;

    const cost = getUpgradeCost(upgrade, currentLevel);
    if (game.balance < cost) return;

    game.balance -= cost;
    stats.totalSpent += cost;
    game.upgrades[id] = currentLevel + 1;

    showNotification(`${upgrade.name} upgraded to Lv.${currentLevel + 1}!`, "rare");

    checkAchievements();
    saveGame();
    updateAllUI();
}

function prestige() {
    if (!canPrestige()) return;

    // Offshore Account: keep a % of balance after prestige
    let keptBalance = 0;
    if (game.upgrades.offshoreAccount) {
        keptBalance = Math.floor(game.balance * (game.upgrades.offshoreAccount * 0.01));
    }

    game.prestigeLevel++;
    game.prestigeBonus = game.prestigeLevel * 2;

    // Reset progress
    game.balance = keptBalance;
    game.xp = 0;
    game.currentHoeIndex = 0;
    game.selectedHoeIndex = 0;
    game.unlockedHoes = [0];
    game.selectedFertilizer = "none";

    for (const fert of FERTILIZERS) {
        game.fertilizers[fert.name] = 0;
    }
    for (const upgrade of UPGRADES) {
        game.upgrades[upgrade.id] = 0;
    }
    for (const plant of PLANTS) {
        game.inventory[plant.name] = 0;
    }

    let msg = `Prestige Level ${game.prestigeLevel}!`;
    if (keptBalance > 0) msg += ` (Kept ${formatMoney(keptBalance)})`;

    showNotification(msg, "legendary");

    const prestigeModal = document.getElementById('prestige-modal');
    if (typeof closeModal === "function") {
        closeModal(prestigeModal);
    } else {
        prestigeModal.classList.remove('active');
        prestigeModal.setAttribute('aria-hidden', 'true');
    }

    checkAchievements();
    saveGame();
    updateAllUI();
}

// ==================== ACHIEVEMENTS ====================
function checkAchievements() {
    for (const achievement of ACHIEVEMENTS) {
        if (!game.achievements.includes(achievement.id)) {
            if (achievement.check(game, stats)) {
                game.achievements.push(achievement.id);
                showNotification(`Achievement: ${achievement.name}!`, "achievement");
            }
        }
    }
}

// ==================== AUTO FARM ====================
const AUTO_FARM_INTERVAL = 166; // ~6 harvests per second
const AUTO_FARM_YIELD_MULT = 0.3; // 30% of manual yield
const AUTO_FARM_SILENT_RARITIES = new Set(["common", "uncommon", "rare", "epic"]); // these are silenced
const AFK_MAX_SECONDS = 24 * 60 * 60; // 24 hours max AFK
let autoFarmTickCounter = 0;
let autoFarmSessionPlants = 0;
let autoFarmSessionXP = 0;

function autoFarmTick() {
    const eligiblePlants = PLANTS.filter(p => p.minHoe <= game.selectedHoeIndex);
    const selectedPlant = eligiblePlants[Math.floor(Math.random() * eligiblePlants.length)];

    // Calculate yield at 30% of manual, suppressing mutation popups
    const fullYield = calculateYield({ suppressNotifications: true });
    const yieldAmount = Math.max(1, Math.floor(fullYield * AUTO_FARM_YIELD_MULT));

    // XP (also reduced, with Tax Evasion applied)
    let xpMult = 1 - ((game.upgrades.taxEvasion || 0) * 0.05);
    const xpGained = Math.max(1, Math.floor(calculateXP() * xpMult * AUTO_FARM_YIELD_MULT));

    // Fertilizer consumption (same as manual farming)
    if (game.selectedFertilizer !== "none" && game.fertilizers[game.selectedFertilizer] > 0) {
        let consumptionMult = (game.upgrades.darkMatterSoil > 0) ? 2 : 1;
        const consumption = (RARITY_CONSUMPTION[selectedPlant.rarity] || 1) * consumptionMult;
        const available = game.fertilizers[game.selectedFertilizer];
        let consumed = Math.min(consumption, available);

        // Recycling Protocol: chance to save fertilizer
        const recycleChance = (game.upgrades.recyclingProtocol || 0) * 0.05;
        if (Math.random() < recycleChance) {
            consumed = 0;
        }

        game.fertilizers[game.selectedFertilizer] -= consumed;
        stats.totalFertilizerUsed += consumed;

        if (game.fertilizers[game.selectedFertilizer] <= 0) {
            game.selectedFertilizer = "none";
        }
    }

    // Add to inventory
    game.inventory[selectedPlant.name] = (game.inventory[selectedPlant.name] || 0) + yieldAmount;
    game.xp += xpGained;

    // Update stats
    stats.totalFarms++;
    stats.totalPlantsHarvested += yieldAmount;
    if (yieldAmount > stats.bestYield) stats.bestYield = yieldAmount;
    if (stats.plantsHarvestedTypes[selectedPlant.name] === 0) {
        stats.uniquePlantsHarvested++;
    }
    stats.plantsHarvestedTypes[selectedPlant.name] += yieldAmount;
    if (selectedPlant.rarity === "legendary") {
        stats.legendaryHarvested += yieldAmount;
    }

    autoFarmSessionHarvests++;
    autoFarmSessionPlants += yieldAmount;
    autoFarmSessionXP += xpGained;
    autoFarmTickCounter++;

    // Keep auto-farm fully silent.

    // Check achievements periodically (every 6 ticks = ~1 second)
    if (autoFarmTickCounter % 6 === 0) {
        checkAchievements();
    }

    // Save periodically (every 30 ticks = ~5 seconds) + update last tick timestamp
    if (autoFarmTickCounter % 30 === 0) {
        saveAutoFarmState();
        saveGame();
    }

    // Update UI every 3 ticks (~0.5 seconds) for performance
    if (autoFarmTickCounter % 3 === 0) {
        updateAutoFarmStats();
        updateStatsBar();
        updateInventoryPage();
    }
}

function startAutoFarm() {
    if (autoFarmActive) return;
    autoFarmActive = true;
    autoFarmSessionHarvests = 0;
    autoFarmSessionPlants = 0;
    autoFarmSessionXP = 0;
    autoFarmTickCounter = 0;
    autoFarmInterval = setInterval(autoFarmTick, AUTO_FARM_INTERVAL);
    saveAutoFarmState();
    queueCloudProgressSave(true);
    updateAutoFarmUI();
}

function stopAutoFarm() {
    if (!autoFarmActive) return;
    autoFarmActive = false;
    clearInterval(autoFarmInterval);
    autoFarmInterval = null;
    saveAutoFarmState();
    saveGame();
    updateAllUI();
}

function toggleAutoFarm() {
    if (autoFarmActive) {
        stopAutoFarm();
    } else {
        startAutoFarm();
    }
}

// ==================== AUTO FARM PERSISTENCE ====================
function saveAutoFarmState() {
    const state = {
        enabled: autoFarmActive,
        lastTick: Date.now()
    };
    localStorage.setItem('autoFarmState', JSON.stringify(state));
}

function loadAutoFarmState() {
    try {
        const raw = localStorage.getItem('autoFarmState');
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (e) {
        return null;
    }
}

function processOfflineAutoFarm() {
    const state = loadAutoFarmState();
    if (!state || !state.enabled) return;

    const now = Date.now();
    const elapsedMs = now - state.lastTick;
    const elapsedSeconds = Math.floor(elapsedMs / 1000);

    if (elapsedSeconds <= 0) return;

    // Cap AFK at 24 hours
    const cappedSeconds = Math.min(elapsedSeconds, AFK_MAX_SECONDS);
    const tickCount = cappedSeconds * 6; // 6 ticks per second

    if (tickCount <= 0) return;

    // Simulate offline harvests (simplified — average yield × tick count)
    const eligiblePlants = PLANTS.filter(p => p.minHoe <= game.selectedHoeIndex);
    let totalOfflinePlants = 0;
    let totalOfflineXP = 0;

    // Use average yield for performance (don't run full calculation per tick)
    const avgYield = Math.max(1, Math.floor(calculateYield({ suppressNotifications: true }) * AUTO_FARM_YIELD_MULT));
    let xpMult = 1 - ((game.upgrades.taxEvasion || 0) * 0.05);
    const avgXP = Math.max(1, Math.floor(calculateXP() * xpMult * AUTO_FARM_YIELD_MULT));

    // Distribute harvests across random plants
    for (let i = 0; i < Math.min(tickCount, 10000); i++) {
        const plant = eligiblePlants[Math.floor(Math.random() * eligiblePlants.length)];
        game.inventory[plant.name] = (game.inventory[plant.name] || 0) + avgYield;
        totalOfflinePlants += avgYield;
        if (stats.plantsHarvestedTypes[plant.name] === 0) {
            stats.uniquePlantsHarvested++;
        }
        stats.plantsHarvestedTypes[plant.name] += avgYield;
        if (plant.rarity === "legendary") {
            stats.legendaryHarvested += avgYield;
        }
    }

    // For very long AFK (>10000 ticks), batch the rest
    if (tickCount > 10000) {
        const remainingTicks = tickCount - 10000;
        const batchYield = avgYield * remainingTicks;
        const batchXP = avgXP * remainingTicks;

        // Distribute batch evenly across eligible plants
        const perPlant = Math.floor(batchYield / eligiblePlants.length);
        const leftover = batchYield % eligiblePlants.length;

        for (let i = 0; i < eligiblePlants.length; i++) {
            const plant = eligiblePlants[i];
            const amount = perPlant + (i < leftover ? 1 : 0);
            game.inventory[plant.name] = (game.inventory[plant.name] || 0) + amount;
            stats.plantsHarvestedTypes[plant.name] += amount;
            if (plant.rarity === "legendary") {
                stats.legendaryHarvested += amount;
            }
        }

        totalOfflinePlants += batchYield;
        totalOfflineXP += batchXP;
    }

    totalOfflineXP += avgXP * Math.min(tickCount, 10000);
    game.xp += totalOfflineXP;
    stats.totalFarms += tickCount;
    stats.totalPlantsHarvested += totalOfflinePlants;

    // Format time string
    let timeStr;
    if (cappedSeconds < 60) {
        timeStr = `${cappedSeconds}s`;
    } else if (cappedSeconds < 3600) {
        timeStr = `${Math.floor(cappedSeconds / 60)}m`;
    } else {
        timeStr = `${Math.floor(cappedSeconds / 3600)}h ${Math.floor((cappedSeconds % 3600) / 60)}m`;
    }

    const wasAFK = elapsedSeconds > AFK_MAX_SECONDS;
    const afkNote = wasAFK ? ' (AFK capped at 24h)' : '';

    showNotification(`Welcome back! Auto-farmed ${formatNumber(totalOfflinePlants)} plants in ${timeStr}${afkNote}`, "achievement");

    saveGame();

    // Resume auto-farm
    startAutoFarm();
}

