/**
 * SHOP SYSTEM
 * Handles modal UI and purchase/equip logic for weather, amulets, rods, and baits.
 */

class Shop {
    constructor(game) {
        this.game = game;
        this.activeTab = 'weather';
    }

    _formatCoinButton(cost) {
        return `${Number(cost).toLocaleString('en-US')} coins`;
    }

    /* ---------- MODAL CONTROL ---------- */
    open() {
        const overlay = document.getElementById('shop-modal-overlay');
        const modal = document.getElementById('shop-modal');
        if (!overlay || !modal) return;

        overlay.classList.add('active');
        modal.classList.add('active');
        this.switchTab(this.activeTab);
    }

    close() {
        const overlay = document.getElementById('shop-modal-overlay');
        const modal = document.getElementById('shop-modal');
        if (!overlay || !modal) return;

        overlay.classList.remove('active');
        modal.classList.remove('active');
    }

    switchTab(tabId) {
        const validTabs = new Set(['weather', 'amulets', 'rods', 'baits']);
        this.activeTab = validTabs.has(tabId) ? tabId : 'weather';

        document.querySelectorAll('.shop-tab-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === this.activeTab);
        });

        this.render();
    }

    /* ---------- MAIN RENDER ---------- */
    render() {
        const container = document.getElementById('shop-tab-content');
        if (!container) return;

        switch (this.activeTab) {
            case 'weather':
                this.renderWeather(container);
                break;
            case 'amulets':
                this.renderAmulets(container);
                break;
            case 'rods':
                this.renderRods(container);
                break;
            case 'baits':
                this.renderBaits(container);
                break;
            default:
                this.renderWeather(container);
                break;
        }
    }

    /* ---------- WEATHER TAB ---------- */
    renderWeather(container) {
        if (typeof this.game._removeExpiredPurchasedWeathers === 'function') {
            this.game._removeExpiredPurchasedWeathers({ logExpired: false, persist: false });
        }

        const active = this.game.state.activeWeathers || [];
        const slotsLeft = WEATHER_BUY_LIMIT - active.length;
        const totalLuck = this.game.getWeatherMultiplier();
        const luckPct = Math.round((totalLuck - 1) * 100);

        container.innerHTML = `<h3 class="shop-tab-title">Weather Control</h3>
            <p class="shop-tab-desc">Activate multiple weather effects at once. Active slots: <strong>${active.length}</strong> / ${WEATHER_BUY_LIMIT}. Combined luck: <strong>${luckPct >= 0 ? '+' : ''}${luckPct}%</strong>. Purchased weather lasts <strong>15 minutes</strong>; natural random weather lasts <strong>20 minutes</strong>.</p>`;

        const grid = document.createElement('div');
        grid.className = 'shop-grid';

        WEATHER_SHOP.forEach(item => {
            const weather = WEATHER_DATA[item.weatherKey];
            if (!weather) return;

            const isActive = active.includes(item.weatherKey);
            const full = slotsLeft <= 0;
            const canBuy = !full && this.game.state.coins >= item.cost;

            const div = document.createElement('div');
            div.className = `shop-item ${isActive ? 'shop-item-highlight' : ''}`;
            div.innerHTML = `
                <div class="item-info">
                    <h3>${weather.icon} ${weather.name}${isActive ? ' <span style="font-size:0.75rem;color:var(--theme-success-text);">Active</span>' : ''}</h3>
                    <p class="shop-item-desc">${weather.desc}</p>
                    <p class="shop-item-meta">Luck: x${weather.luck} | Difficulty: x${weather.difficulty_mod}</p>
                </div>
                <div class="item-actions">
                    ${isActive
                    ? `<button class="btn-secondary btn-sm" onclick="GameAPI.shopRemoveWeather('${item.weatherKey}')">Remove</button>`
                    : `<button class="btn-primary btn-sm"
                            ${canBuy ? '' : 'disabled'}
                            onclick="GameAPI.shopBuyWeather('${item.weatherKey}')">
                            ${full ? 'Slots Full' : this._formatCoinButton(item.cost)}
                        </button>`
                }
                </div>
            `;
            grid.appendChild(div);
        });

        container.appendChild(grid);
    }

    buyWeather(key) {
        if (typeof this.game._removeExpiredPurchasedWeathers === 'function') {
            this.game._removeExpiredPurchasedWeathers({ logExpired: false, persist: false });
        }

        const item = WEATHER_SHOP.find(w => w.weatherKey === key);
        if (!item) return;

        const active = this.game.state.activeWeathers || [];
        if (active.length >= WEATHER_BUY_LIMIT) {
            this.game.log('All weather slots are full.');
            return;
        }
        if (active.includes(key)) {
            this.game.log('This weather is already active.');
            return;
        }
        if (this.game.state.coins < item.cost) {
            this.game.log('Not enough coins.');
            return;
        }

        this.game.spendCoins(item.cost);
        this.game.addPurchasedWeather(key);

        const remaining = WEATHER_BUY_LIMIT - this.game.state.activeWeathers.length;
        this.game.log(`Activated ${WEATHER_DATA[key].name} for 15 minutes. ${remaining} weather slots remaining.`);
        this.game.achievementManager.onWeatherPurchase();
        this.game.ui.renderStats();
        this.game.saveSystem.save();
        this.render();
    }

    removeWeather(key) {
        this.game.removePurchasedWeather(key);
        this.game.log(`Removed ${WEATHER_DATA[key].name} from active weather effects.`);
        this.game.saveSystem.save();
        this.render();
    }

    /* ---------- AMULETS TAB ---------- */
    renderAmulets(container) {
        const currentBiome = this.game.state.location;
        const activeAmulet = this.game.state.activeAmulet;

        container.innerHTML = `<h3 class="shop-tab-title">Biome Amulets</h3>
            <p class="shop-tab-desc">Amulets boost luck in their matching biome. Wearing one consumes one stock each catch.</p>
            ${activeAmulet
                ? `<div class="amulet-active-badge">Active amulet: ${AMULETS[activeAmulet].icon} ${AMULETS[activeAmulet].name} (+${AMULETS[activeAmulet].luckBonus} Luck in ${LOCATIONS[activeAmulet].name})</div>`
                : '<div class="amulet-active-badge inactive">No amulet is currently worn.</div>'}`;

        const grid = document.createElement('div');
        grid.className = 'shop-grid';

        Object.entries(AMULETS).forEach(([biomeKey, amulet]) => {
            const stock = this.game.state.amuletStock[biomeKey] || 0;
            const isCurrentBiome = biomeKey === currentBiome;
            const isWorn = activeAmulet === biomeKey;

            const div = document.createElement('div');
            div.className = `shop-item ${isCurrentBiome ? 'shop-item-highlight' : ''}`;
            div.innerHTML = `
                <div class="item-info">
                    <h3>${amulet.icon} ${amulet.name}</h3>
                    <p class="shop-item-desc">${amulet.desc}</p>
                    <p class="shop-item-meta">
                        Biome: <strong>${LOCATIONS[biomeKey].name}</strong> |
                        Luck: <strong>+${amulet.luckBonus}</strong> |
                        Stock: <strong>${stock}</strong>
                    </p>
                </div>
                <div class="item-actions">
                    <button class="btn-primary btn-sm"
                        ${this.game.state.coins < amulet.cost ? 'disabled' : ''}
                        onclick="GameAPI.shopBuyAmulet('${biomeKey}')">
                        ${this._formatCoinButton(amulet.cost)}
                    </button>
                    <button class="btn-secondary btn-sm"
                        ${stock <= 0 || isWorn || !isCurrentBiome ? 'disabled' : ''}
                        onclick="GameAPI.shopWearAmulet('${biomeKey}')">
                        ${isWorn ? 'Worn' : !isCurrentBiome ? 'Wrong Biome' : 'Wear'}
                    </button>
                </div>
            `;
            grid.appendChild(div);
        });

        container.appendChild(grid);
    }

    buyAmulet(biomeKey) {
        const amulet = AMULETS[biomeKey];
        if (!amulet) return;

        if (this.game.state.coins < amulet.cost) {
            this.game.log('Not enough coins.');
            return;
        }

        this.game.spendCoins(amulet.cost);
        this.game.state.amuletStock[biomeKey] = (this.game.state.amuletStock[biomeKey] || 0) + 1;

        this.game.log(`Purchased ${amulet.name}. Stock: ${this.game.state.amuletStock[biomeKey]}.`);
        this.game.ui.renderStats();
        this.game.saveSystem.save();
        this.render();
    }

    wearAmulet(biomeKey) {
        const amulet = AMULETS[biomeKey];
        if (!amulet) return;

        const stock = this.game.state.amuletStock[biomeKey] || 0;
        if (stock <= 0) {
            this.game.log('No amulets in stock.');
            return;
        }
        if (biomeKey !== this.game.state.location) {
            this.game.log('This amulet does not match your current biome.');
            return;
        }

        this.game.state.activeAmulet = biomeKey;
        this.game.log(`Wearing ${amulet.name}. +${amulet.luckBonus} Luck in ${LOCATIONS[biomeKey].name}.`);
        this.game.ui.renderStats();
        this.game.saveSystem.save();
        this.render();
    }

    /* ---------- RODS TAB ---------- */
    renderRods(container) {
        container.innerHTML = '<h3 class="shop-tab-title">Rod Shop</h3><p class="shop-tab-desc">Upgrade your rod for higher capacity, better luck, and faster reels.</p>';

        const grid = document.createElement('div');
        grid.className = 'shop-grid';

        RODS.forEach(rod => {
            const owned = this.game.state.rodsOwned.includes(rod.id);
            const equipped = this.game.state.rod === rod.id;
            const btnText = equipped ? 'Equipped' : owned ? 'Equip' : this._formatCoinButton(rod.cost);
            const passiveHtml = rod.passive?.summary
                ? `<p class="shop-item-desc">${rod.passive.summary}</p>`
                : '';

            const div = document.createElement('div');
            div.className = 'shop-item';
            div.innerHTML = `
                <div class="item-info">
                    <h3>${rod.name}</h3>
                    <p class="shop-item-meta">Capacity: ${rod.capacity}kg | Luck: +${rod.luck} | Speed: ${rod.speed}</p>
                    ${passiveHtml}
                </div>
                <div class="item-actions">
                    <button class="${equipped ? 'btn-secondary' : 'btn-primary'} btn-sm"
                        ${equipped || (!owned && this.game.state.coins < rod.cost) ? 'disabled' : ''}
                        onclick="GameAPI.shopBuyRod('${rod.id}')">
                        ${btnText}
                    </button>
                </div>
            `;
            grid.appendChild(div);
        });

        container.appendChild(grid);
    }

    buyRod(id) {
        const item = RODS.find(r => r.id === id);
        if (!item) return;

        if (this.game.state.rodsOwned.includes(id)) {
            this.game.state.rod = id;
            if (typeof this.game.onRodEquipped === 'function') this.game.onRodEquipped(item);
            this.game.log(`Equipped ${item.name}.`);
        } else if (this.game.state.coins >= item.cost) {
            this.game.spendCoins(item.cost);
            this.game.state.rodsOwned.push(id);
            this.game.state.rod = id;
            if (typeof this.game.onRodEquipped === 'function') this.game.onRodEquipped(item);
            this.game.log(`Purchased ${item.name}.`);
            this.game.achievementManager.onPurchase('rod', id);
        } else {
            this.game.log('Not enough coins.');
            return;
        }

        this.game.ui.renderAll();
        this.game.saveSystem.save();
        this.render();
    }

    /* ---------- BAITS TAB ---------- */
    renderBaits(container) {
        const equippedRod = RODS.find((rod) => rod.id === this.game.state.rod) || RODS[0];
        container.innerHTML = '<h3 class="shop-tab-title">Bait Shop</h3><p class="shop-tab-desc">Passive baits bias rolls only. They never guarantee rarity or catches.</p>';

        const grid = document.createElement('div');
        grid.className = 'shop-grid';

        BAITS.forEach(bait => {
            const owned = this.game.state.baitsOwned.includes(bait.id);
            const equipped = this.game.state.bait === bait.id;
            const btnText = equipped ? 'Active' : owned ? 'Equip' : this._formatCoinButton(bait.cost);
            const bestRod = bait.passive?.bestWithRod
                ? RODS.find((rod) => rod.id === bait.passive.bestWithRod)
                : null;
            const passiveEnabled = bait.passive?.midTierOnly !== true || equippedRod?.tier === 'mid';
            const passiveMode = bait.passive?.midTierOnly === true
                ? (passiveEnabled
                    ? (bestRod && bestRod.id !== equippedRod.id ? `Passive tuned for ${bestRod.name}.` : 'Passive active.')
                    : 'Passive inactive: equip a mid-tier rod.')
                : '';
            const passiveSummary = bait.passive?.summary
                ? `<p class="shop-item-desc">${bait.passive.summary}</p><p class="shop-item-meta">${passiveMode}</p>`
                : '';

            const div = document.createElement('div');
            div.className = 'shop-item';
            div.innerHTML = `
                <div class="item-info">
                    <h3>${bait.name}</h3>
                    <p class="shop-item-meta">Luck Bonus: +${bait.luck}</p>
                    ${passiveSummary}
                </div>
                <div class="item-actions">
                    <button class="${equipped ? 'btn-secondary' : 'btn-primary'} btn-sm"
                        ${equipped || (!owned && this.game.state.coins < bait.cost) ? 'disabled' : ''}
                        onclick="GameAPI.shopBuyBait('${bait.id}')">
                        ${btnText}
                    </button>
                </div>
            `;
            grid.appendChild(div);
        });

        container.appendChild(grid);
        this.renderBaitBench(container);
    }

    buyBait(id) {
        const item = BAITS.find(b => b.id === id);
        if (!item) return;

        if (this.game.state.baitsOwned.includes(id)) {
            this.game.state.bait = id;
            this.game.log(`Using ${item.name}.`);
        } else if (this.game.state.coins >= item.cost) {
            this.game.spendCoins(item.cost);
            this.game.state.baitsOwned.push(id);
            this.game.state.bait = id;
            this.game.log(`Purchased ${item.name}.`);
            this.game.achievementManager.onPurchase('bait', id);
        } else {
            this.game.log('Not enough coins.');
            return;
        }

        this.game.ui.renderAll();
        this.game.saveSystem.save();
        this.render();
    }

    _canCraftBaitBenchFamily(family, benchState) {
        if (!family?.id || !benchState?.unlockedRecipes?.[family.id]) return false;
        const costs = family.craft?.costs || {};
        return Object.entries(costs).every(([resourceId, amount]) => {
            const needed = Math.max(0, Math.floor(Number(amount) || 0));
            return (benchState.resources?.[resourceId] || 0) >= needed;
        });
    }

    _formatBaitBenchCosts(costs = {}) {
        const parts = Object.entries(costs)
            .map(([resourceId, amount]) => {
                const qty = Math.max(0, Math.floor(Number(amount) || 0));
                const resource = BAIT_BENCH_RESOURCES.find((entry) => entry.id === resourceId);
                return `${qty} ${resource?.name || resourceId}`;
            })
            .filter(Boolean);
        return parts.length > 0 ? parts.join(' + ') : 'No cost';
    }

    renderBaitBench(container) {
        const benchState = this.game.getBaitBenchState();
        const activeFamily = this.game.getActiveBaitBenchFamily();

        const section = document.createElement('section');
        section.className = 'bait-bench-panel';

        const resourceBadges = BAIT_BENCH_RESOURCES.map((resource) => {
            const count = benchState.resources?.[resource.id] || 0;
            return `<span class="bait-bench-chip"><strong>${resource.name}:</strong> ${count.toLocaleString('en-US')}</span>`;
        }).join('');

        section.innerHTML = `
            <div class="bait-bench-head">
                <div>
                    <h3 class="shop-tab-title">Bait Bench</h3>
                    <p class="shop-tab-desc">First catch unlocks recipes. Break down duplicate fish into charges and craft roll-bias baits.</p>
                </div>
                <button class="btn-primary btn-sm" onclick="GameAPI.shopBreakDownBaitDuplicates()">Break Down Duplicates</button>
            </div>
            <div class="bait-bench-chips">${resourceBadges}</div>
        `;

        const familiesGrid = document.createElement('div');
        familiesGrid.className = 'shop-grid bait-bench-grid';

        BAIT_BENCH_FAMILIES.forEach((family) => {
            const unlocked = benchState.unlockedRecipes?.[family.id] === true;
            const charges = benchState.charges?.[family.id] || 0;
            const active = activeFamily?.id === family.id;
            const canCraft = this._canCraftBaitBenchFamily(family, benchState);
            const fishCount = Array.isArray(family.fishNames) ? family.fishNames.length : 0;
            const recipeCost = this._formatBaitBenchCosts(family.craft?.costs || {});

            const card = document.createElement('div');
            card.className = `shop-item bait-bench-item ${active ? 'shop-item-highlight' : ''}`;
            card.innerHTML = `
                <div class="item-info">
                    <h3>${family.name}${active ? ' <span class="bait-bench-active">Active</span>' : ''}</h3>
                    <p class="shop-item-desc">${family.effectSummary}</p>
                    <p class="shop-item-meta">${unlocked ? 'Recipe unlocked' : 'Locked until first matching catch'} | Species list: ${fishCount}</p>
                    <p class="shop-item-meta">Recipe: ${recipeCost} -> ${family.craft?.makesCharges || 1} charges | Stored: ${charges}</p>
                </div>
                <div class="item-actions">
                    <button class="btn-primary btn-sm" ${canCraft ? '' : 'disabled'} onclick="GameAPI.shopCraftBaitBench('${family.id}')">Craft</button>
                    <button class="btn-secondary btn-sm" ${active || charges > 0 ? '' : 'disabled'} onclick="GameAPI.shopActivateBaitBench('${family.id}')">${active ? 'Deactivate' : 'Activate'}</button>
                </div>
            `;
            familiesGrid.appendChild(card);
        });

        section.appendChild(familiesGrid);
        container.appendChild(section);
    }

    breakDownBaitDuplicates() {
        const outcome = this.game.breakDownDuplicateBaitFish();
        if (!outcome || outcome.converted <= 0) {
            this.game.log('No eligible duplicate fish found for Bait Bench breakdown.');
            this.render();
            return;
        }

        const gains = Object.entries(outcome.gained || {})
            .filter(([, amount]) => amount > 0)
            .map(([resourceId, amount]) => {
                const resource = BAIT_BENCH_RESOURCES.find((entry) => entry.id === resourceId);
                return `${amount} ${resource?.name || resourceId}`;
            });

        this.game.log(`Bait Bench processed ${outcome.converted.toLocaleString('en-US')} duplicate fish into ${gains.join(', ')}.`);
        if (outcome.skippedMythic > 0) {
            this.game.log(`Mythic catches skipped: ${outcome.skippedMythic.toLocaleString('en-US')} (trophy-only).`);
        }

        this.game.inventory.render();
        this.game.saveSystem.save();
        this.render();
    }

    craftBaitBenchFamily(familyId) {
        const outcome = this.game.craftBaitBenchFamily(familyId);
        if (!outcome?.ok) {
            if (outcome?.reason === 'locked') {
                this.game.log('Recipe is locked. Catch one listed species first.');
            } else if (outcome?.reason === 'insufficient_resources') {
                this.game.log('Not enough bait materials to craft this family.');
            } else {
                this.game.log('Unable to craft this bait family.');
            }
            this.render();
            return;
        }

        this.game.log(`Crafted ${outcome.family.name}. +${outcome.addedCharges} charges (total ${outcome.totalCharges}).`);
        this.game.saveSystem.save();
        this.render();
    }

    activateBaitBenchFamily(familyId) {
        const benchState = this.game.getBaitBenchState();
        if (benchState.activeFamily === familyId) {
            this.game.setActiveBaitBenchFamily(null);
            this.game.log('Deactivated crafted bait family.');
            this.game.saveSystem.save();
            this.render();
            return;
        }

        const outcome = this.game.setActiveBaitBenchFamily(familyId);
        if (!outcome?.ok) {
            if (outcome?.reason === 'locked') {
                this.game.log('This crafted bait family is still locked.');
            } else if (outcome?.reason === 'no_charges') {
                this.game.log('No charges available. Craft this family first.');
            } else {
                this.game.log('Unable to activate crafted bait family.');
            }
            this.render();
            return;
        }

        this.game.log(`Activated crafted bait: ${outcome.family.name}.`);
        this.game.saveSystem.save();
        this.render();
    }
}

