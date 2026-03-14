(function initPromoPage() {
    const GAME_ENTRY = "game.html";
    const AUTH_STATUS_MESSAGES = {
        checking: "Checking account access...",
        guest: "Not signed in. Create an account or log in to enter your farm.",
        unconfigured: "Cloud auth is not configured yet. Update Supabase settings to enable sign in.",
        error: "Could not verify session. You can still continue to sign in manually."
    };

    const statusEl = document.getElementById("promo-auth-status");
    const loginLink = document.getElementById("promo-login-link");
    const signupLink = document.getElementById("promo-signup-link");

    function setAuthState(state) {
        const safeState = AUTH_STATUS_MESSAGES[state] ? state : "error";
        document.body.dataset.authState = safeState;
        if (statusEl) {
            statusEl.textContent = AUTH_STATUS_MESSAGES[safeState];
        }
    }

    function withNext(path) {
        const separator = path.includes("?") ? "&" : "?";
        return `${path}${separator}next=${encodeURIComponent(GAME_ENTRY)}`;
    }

    function wireAuthLinks() {
        if (loginLink) loginLink.href = withNext("login.html");
        if (signupLink) signupLink.href = withNext("signup.html");

        document.querySelectorAll("a[href='login.html?next=game.html']").forEach((anchor) => {
            anchor.href = withNext("login.html");
        });
        document.querySelectorAll("a[href='signup.html?next=game.html']").forEach((anchor) => {
            anchor.href = withNext("signup.html");
        });
    }

    function setupScrollReveal() {
        const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
        if (revealItems.length === 0) return;

        const viewportHeight = window.innerHeight;
        const inViewThreshold = viewportHeight * 0.92;
        revealItems.forEach((item) => {
            const rect = item.getBoundingClientRect();
            if (rect.top <= inViewThreshold && rect.bottom >= 0) {
                item.classList.add("is-visible");
                item.dataset.revealFrom = rect.top < 0 ? "up" : "down";
            } else {
                item.dataset.revealFrom = rect.top < viewportHeight * 0.5 ? "up" : "down";
            }
        });

        document.body.classList.add("has-motion");

        const observer = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                const target = entry.target;
                const currentlyVisible = target.classList.contains("is-visible");

                if (entry.isIntersecting) {
                    if (currentlyVisible) return;
                    if (entry.intersectionRatio < 0.18) return;
                    target.dataset.revealFrom = entry.boundingClientRect.top < 0 ? "up" : "down";
                    entry.target.classList.add("is-visible");
                } else {
                    if (!currentlyVisible) return;
                    const fullyAbove = entry.boundingClientRect.bottom <= 0;
                    const fullyBelow = entry.boundingClientRect.top >= window.innerHeight;
                    if (!fullyAbove && !fullyBelow) return;

                    target.dataset.revealFrom = fullyAbove ? "up" : "down";
                    target.classList.remove("is-visible");
                }
            });
        }, {
            root: null,
            threshold: [0, 0.18, 0.4, 0.7, 1]
        });

        revealItems.forEach((item) => observer.observe(item));
    }

    function animateCounters() {
        const counters = Array.from(document.querySelectorAll("[data-counter]"));
        if (counters.length === 0) return;

        const formatCounterValue = (value) => {
            if (value >= 100) return String(Math.round(value));
            return String(Math.round(value));
        };

        const runCounter = (el) => {
            if (el.dataset.counterStarted === "true") return;
            el.dataset.counterStarted = "true";

            const target = Number(el.dataset.counter);
            if (!Number.isFinite(target) || target <= 0) {
                el.textContent = el.dataset.counter || "0";
                return;
            }

            const duration = 900;
            const startTime = performance.now();

            function tick(now) {
                const progress = Math.min((now - startTime) / duration, 1);
                const eased = 1 - Math.pow(1 - progress, 3);
                el.textContent = formatCounterValue(target * eased);
                if (progress < 1) {
                    requestAnimationFrame(tick);
                } else {
                    el.textContent = formatCounterValue(target);
                }
            }

            requestAnimationFrame(tick);
        };

        const counterObserver = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (entry.isIntersecting) {
                    runCounter(entry.target);
                }
            });
        }, {
            threshold: 0.5
        });

        counters.forEach((counter) => counterObserver.observe(counter));
    }

    async function redirectAuthenticatedUsers() {
        const supabaseApi = window.VirtualFarmerSupabase;

        if (!supabaseApi || typeof supabaseApi.init !== "function") {
            setAuthState("unconfigured");
            return;
        }

        try {
            const initResult = await supabaseApi.init();

            if (initResult?.configured && initResult?.user) {
                window.location.replace(GAME_ENTRY);
                return;
            }

            if (!initResult?.configured) {
                setAuthState("unconfigured");
                return;
            }

            setAuthState("guest");
        } catch (error) {
            console.error("Promo auth check failed:", error);
            setAuthState("error");
        }
    }

    wireAuthLinks();
    setupScrollReveal();
    animateCounters();
    setAuthState("checking");
    void redirectAuthenticatedUsers();
})();
