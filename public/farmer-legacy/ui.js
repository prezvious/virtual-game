// ==================== NOTIFICATIONS ====================
function showNotification(message, rarity = "common") {
    const container = document.getElementById('notifications');

    // Limit visible notifications
    while (container.children.length >= MAX_NOTIFICATIONS) {
        container.removeChild(container.firstChild);
    }

    const notif = document.createElement('div');
    notif.className = `notification ${rarity}`;
    notif.textContent = message;
    container.appendChild(notif);
    setTimeout(() => notif.remove(), 2500);
}

let modalReturnFocusEl = null;
const SHOP_DEFAULT_SORT = 'recommended';
const shopUIState = {
    activeCategory: 'all',
    sortBy: SHOP_DEFAULT_SORT,
    hideOwned: false
};
const leaderboardState = {
    mostPlants: [],
    highestBalance: [],
    highestXP: [],
    snapshotRefreshedAt: "",
    loadedAt: 0,
    loading: false
};

function openModal(modalEl, focusSelector) {
    if (!modalEl) return;
    modalReturnFocusEl = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    modalEl.classList.add('active');
    modalEl.setAttribute('aria-hidden', 'false');

    const focusTarget = focusSelector
        ? modalEl.querySelector(focusSelector)
        : modalEl.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    if (focusTarget instanceof HTMLElement) {
        requestAnimationFrame(() => focusTarget.focus());
    }
}

function closeModal(modalEl) {
    if (!modalEl) return;
    modalEl.classList.remove('active');
    modalEl.setAttribute('aria-hidden', 'true');

    if (modalReturnFocusEl && document.contains(modalReturnFocusEl)) {
        modalReturnFocusEl.focus();
    }
}

function closeActiveModal() {
    const activeModal = document.querySelector('.modal.active');
    if (!activeModal) return false;
    closeModal(activeModal);
    return true;
}

function isEditableTarget(target) {
    if (!(target instanceof HTMLElement)) return false;
    if (target.isContentEditable) return true;
    return ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName);
}

// ==================== COOLDOWN BAR ====================
function updateCooldownBar(duration) {
    const bar = document.getElementById('cooldown-bar');
    const btn = document.getElementById('farm-btn');

    function update() {
        const now = Date.now();
        if (now >= cooldownEndTime) {
            cooldownActive = false;
            bar.style.width = '0%';
            btn.disabled = false;
            return;
        }

        const remaining = cooldownEndTime - now;
        const percent = (remaining / duration) * 100;
        bar.style.width = percent + '%';
        btn.disabled = true;
        requestAnimationFrame(update);
    }
    update();
}

// ==================== UI UPDATES ====================
function updateAllUI() {
    updateStatsBar();
    updateHoeSelect();
    updateFertilizerSelect();
    updatePrestigeCard();
    updateShopPage();
    updateUpgradesPage();
    updateInventoryPage();
    updateStatsPage();
    updateAchievementsPage();
    updateLeaderboardPage();
    updateAutoFarmUI();
    updateAutoFarmStats();
}

function updateStatsBar() {
    const selectedHoe = HOES[game.selectedHoeIndex] || HOES[0];
    document.getElementById('balance-display').textContent = formatMoney(game.balance);
    document.getElementById('xp-display').textContent = formatNumber(game.xp);
    document.getElementById('plants-display').textContent = formatNumber(getTotalPlants());
    document.getElementById('hoe-display').textContent = selectedHoe.name;
    document.getElementById('prestige-display').textContent = `Lv. ${game.prestigeLevel} (+${game.prestigeBonus}%)`;
}

function updateHoeSelect() {
    const select = document.getElementById('hoe-select');
    select.innerHTML = '';

    for (const index of game.unlockedHoes.sort((a, b) => a - b)) {
        const hoe = HOES[index];
        const option = document.createElement('option');
        option.value = index;
        option.textContent = `${hoe.name} (${hoe.multiplier}x)`;
        option.selected = index === game.selectedHoeIndex;
        select.appendChild(option);
    }
}

function updateFertilizerSelect() {
    const select = document.getElementById('fertilizer-select');
    select.innerHTML = '<option value="none">No Fertilizer</option>';

    for (const fert of FERTILIZERS) {
        const qty = game.fertilizers[fert.name] || 0;
        if (qty > 0) {
            const option = document.createElement('option');
            option.value = fert.name;
            option.textContent = `${fert.name} (+${fert.bonus}) [${qty}]`;
            option.selected = fert.name === game.selectedFertilizer;
            select.appendChild(option);
        }
    }
}

function updatePrestigeCard() {
    const card = document.getElementById('prestige-card');
    const desc = document.getElementById('prestige-description');

    if (canPrestige()) {
        card.style.display = 'block';
        const newBonus = (game.prestigeLevel + 1) * 2;
        let text = `Reset your progress to gain Prestige Level ${game.prestigeLevel + 1} with a permanent +${newBonus}% bonus to all yields and earnings!`;

        // Show Offshore Account info if owned
        if (game.upgrades.offshoreAccount > 0) {
            const keepPercent = game.upgrades.offshoreAccount;
            const keptAmount = Math.floor(game.balance * (keepPercent * 0.01));
            text += ` You will keep ${formatMoney(keptAmount)} (${keepPercent}% via Offshore Account).`;
        }

        desc.textContent = text;
    } else {
        card.style.display = 'none';
    }
}

function getHoeDisplayCost(hoe) {
    const discount = 1 - ((game.upgrades.lobbying || 0) * 0.02);
    return Math.floor(hoe.cost * discount);
}

function formatFixedTrimmed(value, digits = 2) {
    return value.toFixed(digits).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1');
}

function formatRoiLabel(roi) {
    if (!Number.isFinite(roi) || roi <= 0) return 'ROI: n/a';
    if (roi >= 1) return `ROI: +${formatFixedTrimmed(roi)}x per $1`;
    if (roi >= 1e-3) return `ROI: +${formatFixedTrimmed(roi * 1000)}x per $1K`;
    if (roi >= 1e-6) return `ROI: +${formatFixedTrimmed(roi * 1e6)}x per $1M`;
    if (roi >= 1e-9) return `ROI: +${formatFixedTrimmed(roi * 1e9)}x per $1B`;
    return `ROI: +${formatFixedTrimmed(roi * 1e12)}x per $1T`;
}

function formatEfficiencyLabel(efficiency) {
    if (!Number.isFinite(efficiency) || efficiency <= 0) return '0 / $1';
    if (efficiency >= 1) return `${formatFixedTrimmed(efficiency)} / $1`;
    return `${formatFixedTrimmed(efficiency * 1000)} / $1K`;
}

function updateShopPage() {
    const hoeGrid = document.getElementById('hoe-grid');
    const fertGrid = document.getElementById('fertilizer-grid');
    if (!hoeGrid || !fertGrid) return;

    const sortSelect = document.getElementById('shop-sort-select');
    const hideOwnedToggle = document.getElementById('shop-hide-owned');
    if (sortSelect && sortSelect.value !== shopUIState.sortBy) {
        sortSelect.value = shopUIState.sortBy;
    }
    if (hideOwnedToggle) {
        hideOwnedToggle.checked = shopUIState.hideOwned;
    }

    document.querySelectorAll('[data-shop-category]').forEach(btn => {
        const isActive = btn.dataset.shopCategory === shopUIState.activeCategory;
        btn.classList.toggle('active', isActive);
        btn.setAttribute('aria-pressed', String(isActive));
    });

    const hoeSection = document.getElementById('shop-hoe-section');
    const fertilizerSection = document.getElementById('shop-fertilizer-section');
    const showHoes = shopUIState.activeCategory === 'all' || shopUIState.activeCategory === 'hoes';
    const showFertilizers = shopUIState.activeCategory === 'all' || shopUIState.activeCategory === 'fertilizers';
    if (hoeSection) {
        hoeSection.hidden = !showHoes;
        if (shopUIState.activeCategory === 'hoes') hoeSection.open = true;
    }
    if (fertilizerSection) {
        fertilizerSection.hidden = !showFertilizers;
        if (shopUIState.activeCategory === 'fertilizers') fertilizerSection.open = true;
    }

    const selectedHoe = HOES[game.selectedHoeIndex] || HOES[0];
    const hoeEntries = HOES.map((hoe, index) => {
        const displayCost = getHoeDisplayCost(hoe);
        const owned = game.unlockedHoes.includes(index);
        const deltaMultiplier = Math.max(hoe.multiplier - selectedHoe.multiplier, 0);
        const roi = !owned && displayCost > 0 ? deltaMultiplier / displayCost : 0;
        return {
            hoe,
            index,
            owned,
            equipped: game.selectedHoeIndex === index,
            canBuy: !owned && game.balance >= displayCost,
            displayCost,
            deltaMultiplier,
            roi,
            isCheapestNext: false,
            isBestRoi: false
        };
    });

    const unownedHoes = hoeEntries.filter(entry => !entry.owned);
    const cheapestNextHoe = unownedHoes.reduce((best, current) => {
        if (!best) return current;
        if (current.displayCost < best.displayCost) return current;
        if (current.displayCost === best.displayCost && current.index < best.index) return current;
        return best;
    }, null);
    const bestRoiHoe = unownedHoes.reduce((best, current) => {
        if (!best) return current;
        if (current.roi > best.roi) return current;
        if (current.roi === best.roi && current.displayCost < best.displayCost) return current;
        return best;
    }, null);

    if (cheapestNextHoe) {
        const item = hoeEntries[cheapestNextHoe.index];
        if (item) item.isCheapestNext = true;
    }
    if (bestRoiHoe) {
        const item = hoeEntries[bestRoiHoe.index];
        if (item) item.isBestRoi = true;
    }

    let visibleHoes = hoeEntries.filter(entry => !(shopUIState.hideOwned && entry.owned));
    visibleHoes.sort((a, b) => {
        switch (shopUIState.sortBy) {
            case 'price-desc':
                if (a.displayCost !== b.displayCost) return b.displayCost - a.displayCost;
                break;
            case 'power-desc':
                if (a.hoe.multiplier !== b.hoe.multiplier) return b.hoe.multiplier - a.hoe.multiplier;
                break;
            case 'efficiency-desc':
                if (a.roi !== b.roi) return b.roi - a.roi;
                break;
            case 'name':
                return a.hoe.name.localeCompare(b.hoe.name);
            case 'recommended': {
                const rankFor = (entry) => {
                    if (entry.isBestRoi && !entry.owned) return 0;
                    if (entry.isCheapestNext && !entry.owned) return 1;
                    if (!entry.owned && entry.canBuy) return 2;
                    if (!entry.owned) return 3;
                    if (entry.equipped) return 4;
                    return 5;
                };
                const rankDiff = rankFor(a) - rankFor(b);
                if (rankDiff !== 0) return rankDiff;
                if (a.displayCost !== b.displayCost) return a.displayCost - b.displayCost;
                break;
            }
            case 'price-asc':
            default:
                if (a.displayCost !== b.displayCost) return a.displayCost - b.displayCost;
                break;
        }
        return a.index - b.index;
    });

    const fertilizerEntries = FERTILIZERS.map((fert, index) => {
        const qty = game.fertilizers[fert.name] || 0;
        return {
            fert,
            index,
            qty,
            canBuy: game.balance >= fert.cost,
            efficiency: fert.bonus / Math.max(fert.cost, 1),
            isMostEfficient: false
        };
    });

    const mostEfficientFertilizer = fertilizerEntries.reduce((best, current) => {
        if (!best) return current;
        if (current.efficiency > best.efficiency) return current;
        if (current.efficiency === best.efficiency && current.fert.cost < best.fert.cost) return current;
        return best;
    }, null);
    if (mostEfficientFertilizer) {
        const item = fertilizerEntries[mostEfficientFertilizer.index];
        if (item) item.isMostEfficient = true;
    }

    let visibleFertilizers = fertilizerEntries.filter(entry => !(shopUIState.hideOwned && entry.qty > 0));
    visibleFertilizers.sort((a, b) => {
        switch (shopUIState.sortBy) {
            case 'price-desc':
                if (a.fert.cost !== b.fert.cost) return b.fert.cost - a.fert.cost;
                break;
            case 'power-desc':
                if (a.fert.bonus !== b.fert.bonus) return b.fert.bonus - a.fert.bonus;
                break;
            case 'efficiency-desc':
                if (a.efficiency !== b.efficiency) return b.efficiency - a.efficiency;
                break;
            case 'name':
                return a.fert.name.localeCompare(b.fert.name);
            case 'recommended': {
                const rankFor = (entry) => {
                    if (entry.isMostEfficient) return 0;
                    if (entry.canBuy && entry.qty === 0) return 1;
                    if (entry.canBuy) return 2;
                    return 3;
                };
                const rankDiff = rankFor(a) - rankFor(b);
                if (rankDiff !== 0) return rankDiff;
                if (a.fert.cost !== b.fert.cost) return a.fert.cost - b.fert.cost;
                break;
            }
            case 'price-asc':
            default:
                if (a.fert.cost !== b.fert.cost) return a.fert.cost - b.fert.cost;
                break;
        }
        return a.index - b.index;
    });

    const hoeMeta = document.getElementById('shop-hoe-meta');
    const fertilizerMeta = document.getElementById('shop-fertilizer-meta');
    const ownedHoeCount = game.unlockedHoes.length;
    const stockedFertilizerCount = FERTILIZERS.reduce((count, fert) => count + ((game.fertilizers[fert.name] || 0) > 0 ? 1 : 0), 0);
    if (hoeMeta) {
        hoeMeta.textContent = `${ownedHoeCount}/${HOES.length} owned${shopUIState.hideOwned ? ` | ${visibleHoes.length} shown` : ''}`;
    }
    if (fertilizerMeta) {
        fertilizerMeta.textContent = `${stockedFertilizerCount}/${FERTILIZERS.length} stocked${shopUIState.hideOwned ? ` | ${visibleFertilizers.length} shown` : ''}`;
    }

    const insights = document.getElementById('shop-insights');
    if (insights) {
        const bestRoiText = bestRoiHoe
            ? `<strong>${bestRoiHoe.hoe.name}</strong><span>${formatRoiLabel(bestRoiHoe.roi)}</span>`
            : '<strong>All hoes owned</strong><span>No ROI targets left.</span>';
        const cheapestNextText = cheapestNextHoe
            ? `<strong>${cheapestNextHoe.hoe.name}</strong><span>${formatMoney(cheapestNextHoe.displayCost)}</span>`
            : '<strong>No next upgrade</strong><span>You own every hoe.</span>';
        const bestFertText = mostEfficientFertilizer
            ? `<strong>${mostEfficientFertilizer.fert.name}</strong><span>Efficiency: +${formatEfficiencyLabel(mostEfficientFertilizer.efficiency)} yield</span>`
            : '<strong>No fertilizer data</strong><span>Unavailable</span>';

        insights.innerHTML = `
            <article class="shop-insight-card">
                <p>Best ROI Hoe</p>
                ${bestRoiText}
            </article>
            <article class="shop-insight-card">
                <p>Cheapest Next Upgrade</p>
                ${cheapestNextText}
            </article>
            <article class="shop-insight-card">
                <p>Most Efficient Fertilizer</p>
                ${bestFertText}
            </article>
        `;
    }

    hoeGrid.innerHTML = '';
    if (visibleHoes.length === 0) {
        hoeGrid.innerHTML = '<p class="shop-empty">No hoes match the current filter.</p>';
    } else {
        for (const entry of visibleHoes) {
            const { hoe, index, owned, equipped, canBuy, displayCost, deltaMultiplier } = entry;
            const card = document.createElement('div');
            card.className = `item-card${owned ? ' owned' : ''}${equipped ? ' equipped' : ''}`;

            let priceHtml;
            if (hoe.cost === 0) {
                priceHtml = 'Free';
            } else if (displayCost < hoe.cost) {
                priceHtml = `<s style="opacity:0.5;font-size:0.75rem">${formatMoney(hoe.cost)}</s> ${formatMoney(displayCost)}`;
            } else {
                priceHtml = formatMoney(hoe.cost);
            }

            const badges = [];
            if (entry.isBestRoi && !owned) badges.push('<span class="item-badge item-badge-roi">Best ROI</span>');
            if (entry.isCheapestNext && !owned) badges.push('<span class="item-badge item-badge-cheap">Cheapest Next</span>');
            if (equipped) badges.push('<span class="item-badge item-badge-equipped">Equipped</span>');
            if (owned && !equipped) badges.push('<span class="item-badge item-badge-owned">Owned</span>');

            card.innerHTML = `
                <div class="item-header">
                    <span class="item-name">${hoe.name}</span>
                    <span class="item-price">${priceHtml}</span>
                </div>
                ${badges.length ? `<div class="item-badges">${badges.join('')}</div>` : ''}
                <div class="item-stats">Multiplier: ${formatNumber(hoe.multiplier)}x</div>
                <div class="item-stats">${owned ? 'Ready to equip.' : `Gain vs equipped: +${formatNumber(deltaMultiplier)}x`}</div>
                ${owned
                    ? (equipped
                        ? '<button class="btn" disabled>Equipped</button>'
                        : '<button class="btn btn-secondary">Equip</button>')
                    : `<button class="btn" ${canBuy ? '' : 'disabled'}>Buy</button>`
                }
            `;

            const actionBtn = card.querySelector('button');
            if (actionBtn) {
                actionBtn.addEventListener('click', () => {
                    if (owned) {
                        if (!equipped) equipHoe(index);
                    } else {
                        buyHoe(index);
                    }
                });
            }
            hoeGrid.appendChild(card);
        }
    }

    fertGrid.innerHTML = '';
    if (visibleFertilizers.length === 0) {
        fertGrid.innerHTML = '<p class="shop-empty">No fertilizers match the current filter.</p>';
    } else {
        for (const entry of visibleFertilizers) {
            const { fert, qty, canBuy, efficiency } = entry;

            const card = document.createElement('div');
            card.className = `item-card${qty > 0 ? ' owned' : ''}`;

            const badges = [];
            if (entry.isMostEfficient) badges.push('<span class="item-badge item-badge-eff">Most Efficient</span>');
            if (qty > 0) badges.push('<span class="item-badge item-badge-owned">Stocked</span>');

            card.innerHTML = `
                <div class="item-header">
                    <span class="item-name">${fert.name}</span>
                    <span class="item-price">${formatMoney(fert.cost)}</span>
                </div>
                ${badges.length ? `<div class="item-badges">${badges.join('')}</div>` : ''}
                <div class="item-stats">Bonus: +${formatNumber(fert.bonus)} yield | Owned: ${formatNumber(qty)}</div>
                <div class="item-stats">Efficiency: +${formatEfficiencyLabel(efficiency)} yield</div>
            `;

            const actions = document.createElement('div');
            actions.className = 'fert-actions';
            const purchaseAmounts = [1, 10, 100];
            for (const amount of purchaseAmounts) {
                const btn = document.createElement('button');
                btn.className = amount === 100 ? 'btn btn-secondary' : 'btn';
                btn.textContent = `+${amount}`;
                btn.disabled = !canBuy || game.balance < (fert.cost * amount);
                btn.addEventListener('click', () => buyFertilizer(fert.name, amount));
                actions.appendChild(btn);
            }

            card.appendChild(actions);
            fertGrid.appendChild(card);
        }
    }
}

function updateUpgradesPage() {
    const grid = document.getElementById('upgrade-grid');
    grid.innerHTML = '';

    // Render upgrades grouped by category
    for (const catKey of Object.keys(UPGRADE_CATEGORIES)) {
        const category = UPGRADE_CATEGORIES[catKey];

        // Category header
        const header = document.createElement('div');
        header.className = 'upgrade-category';
        header.textContent = category.label;
        grid.appendChild(header);

        // Upgrades in this category
        for (const upgradeId of category.ids) {
            const upgrade = UPGRADES.find(u => u.id === upgradeId);
            if (!upgrade) continue;

            const level = game.upgrades[upgrade.id] || 0;
            const maxed = level >= upgrade.maxLevel;
            const cost = maxed ? 0 : getUpgradeCost(upgrade, level);
            const canBuy = !maxed && game.balance >= cost;

            const card = document.createElement('div');
            card.className = `item-card${maxed ? ' owned' : ''}`;
            card.innerHTML = `
                <div class="item-header">
                    <span class="item-name">${upgrade.name}</span>
                    <span class="upgrade-level">Lv. ${level}/${upgrade.maxLevel}</span>
                </div>
                <div class="item-stats">${upgrade.desc}</div>
                <div class="progress-container">
                    <div class="progress-bar" style="width: ${(level / upgrade.maxLevel) * 100}%"></div>
                </div>
                ${maxed
                    ? '<button class="btn" disabled>Maxed</button>'
                    : `<button class="btn" ${canBuy ? '' : 'disabled'} onclick="buyUpgrade('${upgrade.id}')">${formatMoney(cost)}</button>`
                }
            `;
            grid.appendChild(card);
        }
    }
}

function updateInventoryPage() {
    const grid = document.getElementById('inventory-grid');
    const sortBy = document.getElementById('sort-select').value;
    const filterBy = document.getElementById('filter-select').value;

    let items = PLANTS.map(p => ({
        ...p,
        quantity: game.inventory[p.name] || 0
    })).filter(p => p.quantity > 0);

    // Filter
    if (filterBy !== 'all') {
        items = items.filter(p => p.rarity === filterBy);
    }

    // Sort
    switch (sortBy) {
        case 'quantity':
            items.sort((a, b) => b.quantity - a.quantity);
            break;
        case 'value':
            items.sort((a, b) => b.price - a.price);
            break;
        case 'rarity':
            items.sort((a, b) => RARITY_ORDER[b.rarity] - RARITY_ORDER[a.rarity]);
            break;
        default:
            items.sort((a, b) => a.name.localeCompare(b.name));
    }

    grid.innerHTML = '';

    if (items.length === 0) {
        grid.innerHTML = '<p style="grid-column: 1/-1; text-align: center; opacity: 0.6;">No plants in inventory</p>';
    } else {
        for (const item of items) {
            const div = document.createElement('div');
            div.className = `inventory-item ${item.rarity}`;
            div.innerHTML = `
                <span>${item.name}</span>
                <span>${formatNumber(item.quantity)}</span>
            `;
            grid.appendChild(div);
        }
    }

    const totalValue = calculateSellPrice();
    document.getElementById('inventory-total').textContent =
        `Total Value: ${formatMoney(totalValue)} (${formatNumber(getTotalPlants())} plants)`;
}

function updateStatsPage() {
    const grid = document.getElementById('stats-grid');

    const statItems = [
        { label: "Total Farms", value: formatNumber(stats.totalFarms) },
        { label: "Total Plants Harvested", value: formatNumber(stats.totalPlantsHarvested) },
        { label: "Total Money Earned", value: formatMoney(stats.totalEarned) },
        { label: "Total Money Spent", value: formatMoney(stats.totalSpent) },
        { label: "Best Single Yield", value: formatNumber(stats.bestYield) },
        { label: "Best Single Sale", value: formatMoney(stats.bestSale) },
        { label: "Unique Plants Discovered", value: `${stats.uniquePlantsHarvested}/${PLANTS.length}` },
        { label: "Legendary Plants Harvested", value: formatNumber(stats.legendaryHarvested) },
        { label: "Fertilizer Used", value: formatNumber(stats.totalFertilizerUsed) },
        { label: "Session Farms", value: formatNumber(stats.sessionFarms) },
        { label: "Current Prestige Level", value: `Lv. ${game.prestigeLevel}` },
        { label: "Prestige Bonus", value: `+${game.prestigeBonus}%` }
    ];

    grid.innerHTML = statItems.map(s => `
        <div class="stats-card">
            <div class="value">${s.value}</div>
            <div class="label">${s.label}</div>
        </div>
    `).join('');
}

function updateAchievementsPage() {
    const grid = document.getElementById('achievement-grid');
    const unlocked = game.achievements.length;

    document.getElementById('achievement-progress').textContent =
        `Unlocked: ${unlocked}/${ACHIEVEMENTS.length}`;

    grid.innerHTML = ACHIEVEMENTS.map(a => {
        const isUnlocked = game.achievements.includes(a.id);
        return `
            <div class="achievement-card${isUnlocked ? ' unlocked' : ''}">
                <div class="achievement-icon">${a.icon}</div>
                <div class="achievement-info">
                    <h3>${a.name}</h3>
                    <p>${a.desc}</p>
                </div>
            </div>
        `;
    }).join('');
}

function formatLeaderboardValue(metric, value) {
    const numericValue = Number(value) || 0;
    if (metric === "balance") return formatMoney(numericValue);
    return formatNumber(numericValue);
}

function escapeHtml(value) {
    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/\"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

function renderLeaderboardTable(bodyId, rows, metric) {
    const body = document.getElementById(bodyId);
    if (!body) return;

    if (!Array.isArray(rows) || rows.length === 0) {
        body.innerHTML = '<tr><td colspan="3" class="leaderboard-empty">No leaderboard data yet</td></tr>';
        return;
    }

    const currentUserId = window.VirtualFarmerSupabase?.getCurrentUser()?.id || null;
    body.innerHTML = rows.map((row, index) => {
        const username = row?.username || row?.display_name || "Unknown";
        const safeDisplayName = escapeHtml(username.startsWith("@") ? username : `@${username}`);
        const value =
            metric === "total_plants" ? row.total_plants :
            metric === "balance" ? row.balance :
            row.xp;
        const safeValue = escapeHtml(formatLeaderboardValue(metric, value));
        const isCurrentUser = currentUserId && row?.user_id === currentUserId;

        return `
            <tr class="${isCurrentUser ? "leaderboard-self" : ""}">
                <td class="leaderboard-rank">${index + 1}</td>
                <td>${safeDisplayName}</td>
                <td>${safeValue}</td>
            </tr>
        `;
    }).join('');
}

function updateLeaderboardPage() {
    renderLeaderboardTable("leaderboard-plants-body", leaderboardState.mostPlants, "total_plants");
    renderLeaderboardTable("leaderboard-balance-body", leaderboardState.highestBalance, "balance");
    renderLeaderboardTable("leaderboard-xp-body", leaderboardState.highestXP, "xp");

    const stampEl = document.getElementById("leaderboard-last-updated");
    if (!stampEl) return;

    const snapshotUpdatedMs = Date.parse(String(leaderboardState.snapshotRefreshedAt || ""));
    if (Number.isFinite(snapshotUpdatedMs)) {
        stampEl.textContent = `Last updated: ${new Date(snapshotUpdatedMs).toLocaleString()}`;
        return;
    }

    if (!leaderboardState.loadedAt) {
        stampEl.textContent = "Last updated: not loaded yet";
        return;
    }
    const loadedDate = new Date(leaderboardState.loadedAt);
    stampEl.textContent = `Last updated: ${loadedDate.toLocaleString()}`;
}

async function refreshLeaderboard({ force = false } = {}) {
    const supabaseApi = window.VirtualFarmerSupabase;
    if (!supabaseApi || !supabaseApi.isAuthenticated()) {
        return;
    }

    if (leaderboardState.loading) return;
    if (!force && leaderboardState.loadedAt && (Date.now() - leaderboardState.loadedAt < 15000)) {
        return;
    }

    const refreshButton = document.getElementById("refresh-leaderboard-btn");
    if (refreshButton) refreshButton.disabled = true;
    leaderboardState.loading = true;

    try {
        if (force && typeof supabaseApi.flushQueuedSave === "function") {
            await supabaseApi.flushQueuedSave();
        }

        const bundle = await supabaseApi.fetchLeaderboardBundle(10, { forceRefresh: force === true });
        leaderboardState.mostPlants = Array.isArray(bundle.mostPlants) ? bundle.mostPlants : [];
        leaderboardState.highestBalance = Array.isArray(bundle.highestBalance) ? bundle.highestBalance : [];
        leaderboardState.highestXP = Array.isArray(bundle.highestXP) ? bundle.highestXP : [];
        leaderboardState.snapshotRefreshedAt = String(bundle?.refreshedAt || "").trim();
        leaderboardState.loadedAt = Date.now();
        updateLeaderboardPage();
    } catch (error) {
        console.error("Failed to refresh leaderboard:", error);
        showNotification("Failed to load leaderboard.", "common");
    } finally {
        leaderboardState.loading = false;
        if (refreshButton) refreshButton.disabled = false;
    }
}

// ==================== AUTO FARM UI ====================
function updateAutoFarmUI() {
    const toggleBtn = document.getElementById('auto-farm-toggle');
    const statusEl = document.getElementById('auto-farm-status');

    if (autoFarmActive) {
        toggleBtn.textContent = 'Disable Auto Farm';
        toggleBtn.classList.add('active');
        statusEl.textContent = 'Active';
        statusEl.classList.add('active');
    } else {
        toggleBtn.textContent = 'Enable Auto Farm';
        toggleBtn.classList.remove('active');
        statusEl.textContent = 'Inactive';
        statusEl.classList.remove('active');
    }
}

function updateAutoFarmStats() {
    const grid = document.getElementById('auto-farm-stats');
    if (autoFarmActive) {
        grid.innerHTML = `
            <div class="auto-farm-stat">
                <div class="af-value">${formatNumber(autoFarmSessionHarvests)}</div>
                <div class="af-label">Harvests</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">${formatNumber(autoFarmSessionPlants)}</div>
                <div class="af-label">Plants Earned</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">${formatNumber(autoFarmSessionXP)}</div>
                <div class="af-label">XP Earned</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">30%</div>
                <div class="af-label">Yield Rate</div>
            </div>
        `;
    } else {
        grid.innerHTML = `
            <div class="auto-farm-stat">
                <div class="af-value">--</div>
                <div class="af-label">Harvests</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">--</div>
                <div class="af-label">Plants Earned</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">--</div>
                <div class="af-label">XP Earned</div>
            </div>
            <div class="auto-farm-stat">
                <div class="af-value">30%</div>
                <div class="af-label">Yield Rate</div>
            </div>
        `;
    }
}

function setupShopControls() {
    const sortSelect = document.getElementById('shop-sort-select');
    if (sortSelect) {
        sortSelect.value = shopUIState.sortBy;
        sortSelect.addEventListener('change', (event) => {
            shopUIState.sortBy = event.target.value || SHOP_DEFAULT_SORT;
            updateShopPage();
        });
    }

    const hideOwnedToggle = document.getElementById('shop-hide-owned');
    if (hideOwnedToggle) {
        hideOwnedToggle.checked = shopUIState.hideOwned;
        hideOwnedToggle.addEventListener('change', (event) => {
            shopUIState.hideOwned = event.target.checked;
            updateShopPage();
        });
    }

    document.querySelectorAll('[data-shop-category]').forEach(btn => {
        btn.addEventListener('click', () => {
            shopUIState.activeCategory = btn.dataset.shopCategory || 'all';
            updateShopPage();
        });
    });
}

function updateSignedInUserPanel() {
    const playerNameEl = document.getElementById('player-display-name');
    const loginBtn = document.getElementById('login-btn');
    const signupBtn = document.getElementById('signup-btn');
    if (!playerNameEl || !loginBtn || !signupBtn) return;

    const next = encodeURIComponent('game.html');
    loginBtn.href = `login.html?next=${next}`;
    signupBtn.href = `signup.html?next=${next}`;

    const supabaseApi = window.VirtualFarmerSupabase;
    if (!supabaseApi || !supabaseApi.isConfigured()) {
        playerNameEl.textContent = 'Local Mode';
        loginBtn.hidden = false;
        signupBtn.hidden = false;
        return;
    }

    if (!supabaseApi.isAuthenticated()) {
        playerNameEl.textContent = 'Not Signed In';
        loginBtn.hidden = false;
        signupBtn.hidden = false;
        return;
    }

    const currentUser = supabaseApi.getCurrentUser();
    const username = typeof supabaseApi.getUsername === "function" ? supabaseApi.getUsername() : "";
    playerNameEl.textContent = username ? `@${username}` : (currentUser?.email || "Signed In");
    loginBtn.hidden = true;
    signupBtn.hidden = true;
}

// ==================== EVENT LISTENERS ====================
function setupEventListeners() {
    // Navigation
    document.querySelectorAll('.nav-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
            document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));

            btn.classList.add('active');
            document.getElementById(`page-${btn.dataset.page}`).classList.add('active');

            if (btn.dataset.page === 'leaderboard') {
                await refreshLeaderboard({ force: false });
            }
        });
    });

    // Farm button
    document.getElementById('farm-btn').addEventListener('click', farm);

    // Sell button
    document.getElementById('sell-btn').addEventListener('click', sellAll);

    // Hoe select
    document.getElementById('hoe-select').addEventListener('change', (e) => {
        equipHoe(parseInt(e.target.value));
    });

    // Fertilizer select
    document.getElementById('fertilizer-select').addEventListener('change', (e) => {
        game.selectedFertilizer = e.target.value;
        saveGame();
    });

    // Inventory sort/filter
    document.getElementById('sort-select').addEventListener('change', updateInventoryPage);
    document.getElementById('filter-select').addEventListener('change', updateInventoryPage);
    setupShopControls();

    const refreshLeaderboardBtn = document.getElementById('refresh-leaderboard-btn');
    if (refreshLeaderboardBtn) {
        refreshLeaderboardBtn.addEventListener('click', async () => {
            await refreshLeaderboard({ force: true });
        });
    }

    // Prestige
    document.getElementById('prestige-btn').addEventListener('click', () => {
        const newBonus = (game.prestigeLevel + 1) * 2;
        let previewText = `You will gain: Prestige Level ${game.prestigeLevel + 1} with +${newBonus}% permanent bonus!`;

        if (game.upgrades.offshoreAccount > 0) {
            const keepPercent = game.upgrades.offshoreAccount;
            const keptAmount = Math.floor(game.balance * (keepPercent * 0.01));
            previewText += ` (Keeping ${formatMoney(keptAmount)})`;
        }

        document.getElementById('prestige-bonus-preview').textContent = previewText;
        openModal(document.getElementById('prestige-modal'), '#prestige-cancel');
    });

    document.getElementById('prestige-cancel').addEventListener('click', () => {
        closeModal(document.getElementById('prestige-modal'));
    });

    document.getElementById('prestige-confirm').addEventListener('click', prestige);

    // Close modals when clicking backdrop
    document.querySelectorAll('.modal').forEach(modal => {
        modal.addEventListener('click', (event) => {
            if (event.target === modal) {
                closeModal(modal);
            }
        });
    });

    // Auto Farm toggle
    document.getElementById('auto-farm-toggle').addEventListener('click', toggleAutoFarm);

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        if (e.code === 'Escape' && closeActiveModal()) {
            e.preventDefault();
            return;
        }
        if (document.querySelector('.modal.active')) return;
        if (isEditableTarget(e.target)) return;

        switch (e.code) {
            case 'Space':
                e.preventDefault();
                farm();
                break;
            case 'KeyS':
                sellAll();
                break;
            case 'KeyA':
                if (e.repeat) break;
                toggleAutoFarm();
                break;
            case 'KeyF':
                const fertSelect = document.getElementById('fertilizer-select');
                const options = fertSelect.options;
                const currentIndex = fertSelect.selectedIndex;
                const nextIndex = (currentIndex + 1) % options.length;
                fertSelect.selectedIndex = nextIndex;
                game.selectedFertilizer = fertSelect.value;
                saveGame();
                break;
            case 'Digit1':
            case 'Digit2':
            case 'Digit3':
            case 'Digit4':
            case 'Digit5':
            case 'Digit6':
            case 'Digit7':
            case 'Digit8':
            case 'Digit9':
                const hoeIndex = parseInt(e.code.slice(-1)) - 1;
                if (game.unlockedHoes.includes(hoeIndex)) {
                    equipHoe(hoeIndex);
                }
                break;
        }
    });
}

// ==================== INITIALIZATION ====================
async function init() {
    const supabaseApi = window.VirtualFarmerSupabase;
    const redirectTarget = `login.html?next=${encodeURIComponent('game.html')}`;
    let shouldRevealApp = true;

    try {
        if (supabaseApi) {
            const initResult = await supabaseApi.init({ requireAuth: true, redirectTo: redirectTarget });
            if (initResult.configured && !initResult.user && !initResult.error) {
                shouldRevealApp = false;
                return;
            }
            if (initResult.error) {
                console.error("Supabase init error:", initResult.error);
            }

            if (supabaseApi.isConfigured()) {
                supabaseApi.onAuthStateChange(() => {
                    updateSignedInUserPanel();
                });
            }
        }

        loadGame();
        await syncProgressWithCloud();

        // Process offline auto-farm earnings
        processOfflineAutoFarm();

        setupEventListeners();
        updateSignedInUserPanel();
        updateAllUI();
        updateAutoFarmStats();

        if (supabaseApi && supabaseApi.isAuthenticated()) {
            await refreshLeaderboard({ force: true });
        }

        // Start weather polling
        if (typeof startWeatherPolling === 'function') {
            startWeatherPolling();
        }

        // Auto-save every 30 seconds
        setInterval(saveGame, 30000);
    } catch (error) {
        console.error("Initialization failed:", error);
    } finally {
        if (shouldRevealApp) {
            document.body.dataset.appReady = 'true';
        }
    }
}

void init();
