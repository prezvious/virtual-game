(function initAuthPages() {
    const PASSWORD_MIN_LENGTH = 8;
    const PASSWORD_RULES = [
        { key: "uppercase", label: "an uppercase letter", check: checkUppercase },
        { key: "lowercase", label: "a lowercase letter", check: checkLowercase },
        { key: "number", label: "a number", check: checkNumber },
        { key: "special", label: "a special character", check: checkSpecialCharacter },
        { key: "minLength", label: `${PASSWORD_MIN_LENGTH}+ characters`, check: checkMinLength }
    ];

    const nextTarget = sanitizeNextTarget(new URLSearchParams(window.location.search).get("next"));

    function sanitizeNextTarget(rawValue) {
        if (!rawValue) return "game.html";
        const trimmed = String(rawValue).trim();
        if (!trimmed) return "game.html";
        if (/^https?:\/\//i.test(trimmed) || trimmed.startsWith("//")) return "game.html";
        return trimmed;
    }

    function withNextParam(path) {
        const separator = path.includes("?") ? "&" : "?";
        return `${path}${separator}next=${encodeURIComponent(nextTarget)}`;
    }

    function getPasswordValue(inputEl) {
        return inputEl?.value || "";
    }

    function checkUppercase(password) {
        return /[A-Z]/.test(password);
    }

    function checkLowercase(password) {
        return /[a-z]/.test(password);
    }

    function checkNumber(password) {
        return /\d/.test(password);
    }

    function checkSpecialCharacter(password) {
        return /[^A-Za-z0-9\s]/.test(password);
    }

    function checkMinLength(password, min = PASSWORD_MIN_LENGTH) {
        return password.length >= min;
    }

    function validatePassword(password) {
        const value = String(password || "");
        const state = {};

        PASSWORD_RULES.forEach((rule) => {
            state[rule.key] = Boolean(rule.check(value));
        });

        const passedCount = PASSWORD_RULES.filter((rule) => state[rule.key]).length;
        return {
            ...state,
            passedCount,
            totalRules: PASSWORD_RULES.length,
            isValid: passedCount === PASSWORD_RULES.length
        };
    }

    function calculateStrength(validationResult) {
        const score = validationResult.passedCount;
        if (score <= 1) return { label: "Very weak", tone: "error" };
        if (score === 2) return { label: "Weak", tone: "error" };
        if (score === 3) return { label: "Medium", tone: "info" };
        if (score === 4) return { label: "Strong", tone: "success" };
        return { label: "Very strong", tone: "success" };
    }

    function updateChecklistUI(checklistEl, validationResult) {
        if (!checklistEl) return;
        checklistEl.querySelectorAll("[data-password-rule]").forEach((item) => {
            const ruleKey = item.getAttribute("data-password-rule");
            const isValid = Boolean(validationResult[ruleKey]);
            item.classList.toggle("is-valid", isValid);
            item.classList.toggle("is-pending", !isValid);
            item.setAttribute("aria-checked", isValid ? "true" : "false");
        });
    }

    function updateStrengthUI(strengthEl, validationResult) {
        if (!strengthEl) return;
        const strength = calculateStrength(validationResult);
        strengthEl.classList.remove("is-error", "is-success");
        if (strength.tone === "error") strengthEl.classList.add("is-error");
        if (strength.tone === "success") strengthEl.classList.add("is-success");
        strengthEl.textContent = `Strength: ${strength.label} (${validationResult.passedCount}/${validationResult.totalRules})`;
    }

    function getMissingPasswordRequirementLabels(validationResult) {
        return PASSWORD_RULES.filter((rule) => !validationResult[rule.key]).map((rule) => rule.label);
    }

    function formatList(items) {
        if (items.length === 0) return "";
        if (items.length === 1) return items[0];
        if (items.length === 2) return `${items[0]} and ${items[1]}`;
        return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
    }

    function setStatus(message, tone = "info") {
        const statusEl = document.getElementById("auth-status");
        if (!statusEl) return;
        statusEl.textContent = message || "";
        statusEl.classList.remove("error", "success");
        if (tone === "error") statusEl.classList.add("error");
        if (tone === "success") statusEl.classList.add("success");
    }

    function wireStatusReset(form) {
        form.querySelectorAll("input").forEach((inputEl) => {
            inputEl.addEventListener("input", () => {
                const statusEl = document.getElementById("auth-status");
                if (statusEl?.textContent) setStatus("");
            });
        });
    }

    function setupPasswordVisibilityToggles() {
        document.querySelectorAll("[data-password-toggle]").forEach((toggleBtn) => {
            const targetInputId = toggleBtn.getAttribute("data-password-toggle");
            const targetInput = document.getElementById(targetInputId);
            if (!targetInput) return;

            toggleBtn.addEventListener("click", () => {
                const revealPassword = targetInput.type === "password";
                targetInput.type = revealPassword ? "text" : "password";
                toggleBtn.textContent = revealPassword ? "Hide" : "Show";
                toggleBtn.setAttribute("aria-pressed", revealPassword ? "true" : "false");
                toggleBtn.setAttribute("aria-label", revealPassword ? "Hide password" : "Show password");
            });
        });
    }

    function setupPasswordField({ inputId, checklistId, strengthId }) {
        const inputEl = document.getElementById(inputId);
        if (!inputEl) return null;

        const checklistEl = document.getElementById(checklistId);
        const strengthEl = document.getElementById(strengthId);
        let latestValidation = validatePassword(getPasswordValue(inputEl));

        const syncValidationUI = () => {
            latestValidation = validatePassword(getPasswordValue(inputEl));
            updateChecklistUI(checklistEl, latestValidation);
            updateStrengthUI(strengthEl, latestValidation);
            return latestValidation;
        };

        inputEl.addEventListener("input", syncValidationUI);
        inputEl.addEventListener("blur", syncValidationUI);
        syncValidationUI();

        return {
            getValidation: () => latestValidation,
            syncValidationUI,
            getPassword: () => getPasswordValue(inputEl)
        };
    }

    function syncSubmitAvailability(submitBtn, fieldsFilled, passwordIsValid) {
        if (!submitBtn) return;
        submitBtn.disabled = !(fieldsFilled && passwordIsValid);
    }

    async function initialize() {
        const supabaseApi = window.VirtualFarmerSupabase;

        const loginLink = document.getElementById("link-login");
        const signupLink = document.getElementById("link-signup");
        if (loginLink) loginLink.href = withNextParam("login.html");
        if (signupLink) signupLink.href = withNextParam("signup.html");

        setupPasswordVisibilityToggles();
        setupLoginForm(supabaseApi);
        setupSignupForm(supabaseApi);

        if (!supabaseApi) {
            setStatus("Authentication client failed to load. Check script includes.", "error");
            return;
        }

        if (!supabaseApi.isConfigured()) {
            setStatus("Authentication config missing. Update your project auth config with project URL and anon key.", "error");
            return;
        }

        const redirected = await supabaseApi.redirectIfAuthenticated(nextTarget);
        if (redirected) return;
    }

    function setupLoginForm(supabaseApi) {
        const form = document.getElementById("login-form");
        if (!form) return;

        const submitBtn = form.querySelector("button[type='submit']");
        const emailInput = document.getElementById("login-email");
        const passwordInput = document.getElementById("login-password");
        const passwordField = setupPasswordField({
            inputId: "login-password",
            checklistId: "login-password-checklist",
            strengthId: "login-password-strength"
        });

        const syncLoginSubmitState = () => {
            const email = emailInput?.value.trim() || "";
            const password = passwordField?.getPassword() || "";
            syncSubmitAvailability(submitBtn, Boolean(email && password), true);
        };

        wireStatusReset(form);
        emailInput?.addEventListener("input", syncLoginSubmitState);
        passwordInput?.addEventListener("input", syncLoginSubmitState);
        syncLoginSubmitState();

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            const email = emailInput?.value.trim() || "";
            const password = passwordField?.getPassword() || "";
            passwordField?.syncValidationUI();

            if (!email || !password) {
                setStatus("Enter both email and password.", "error");
                syncLoginSubmitState();
                return;
            }
            if (!supabaseApi || !supabaseApi.isConfigured()) {
                setStatus("Authentication config missing. Update your project auth config with project URL and anon key.", "error");
                syncLoginSubmitState();
                return;
            }

            submitBtn.disabled = true;
            setStatus("Signing in...");

            try {
                await supabaseApi.signIn({ email, password });
                setStatus("Signed in. Redirecting...", "success");
                window.location.href = nextTarget;
            } catch (error) {
                setStatus(error?.message || "Login failed.", "error");
            } finally {
                syncLoginSubmitState();
            }
        });
    }

    function setupSignupForm(supabaseApi) {
        const form = document.getElementById("signup-form");
        if (!form) return;

        const submitBtn = form.querySelector("button[type='submit']");
        const emailInput = document.getElementById("signup-email");
        const confirmPasswordInput = document.getElementById("signup-confirm-password");
        const passwordInput = document.getElementById("signup-password");
        const passwordField = setupPasswordField({
            inputId: "signup-password",
            checklistId: "signup-password-checklist",
            strengthId: "signup-password-strength"
        });

        const syncSignupSubmitState = () => {
            const email = emailInput?.value.trim() || "";
            const confirmPassword = confirmPasswordInput?.value || "";
            const password = passwordField?.getPassword() || "";
            const validation = passwordField?.getValidation() || validatePassword("");
            const allFieldsFilled = Boolean(email && password && confirmPassword);
            const passwordsMatch = password === confirmPassword;
            syncSubmitAvailability(submitBtn, allFieldsFilled && passwordsMatch, validation.isValid);
        };

        wireStatusReset(form);
        emailInput?.addEventListener("input", syncSignupSubmitState);
        confirmPasswordInput?.addEventListener("input", syncSignupSubmitState);
        passwordInput?.addEventListener("input", syncSignupSubmitState);
        syncSignupSubmitState();

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            const email = emailInput?.value.trim() || "";
            const password = passwordField?.getPassword() || "";
            const confirmPassword = confirmPasswordInput?.value || "";
            const validation = passwordField?.syncValidationUI() || validatePassword(password);

            if (!email || !password || !confirmPassword) {
                setStatus("Fill out all required fields.", "error");
                syncSignupSubmitState();
                return;
            }
            if (!validation.isValid) {
                const missingRules = formatList(getMissingPasswordRequirementLabels(validation));
                setStatus(`Password must include ${missingRules}.`, "error");
                syncSignupSubmitState();
                return;
            }
            if (password !== confirmPassword) {
                setStatus("Passwords do not match.", "error");
                syncSignupSubmitState();
                return;
            }
            if (!supabaseApi || !supabaseApi.isConfigured()) {
                setStatus("Authentication config missing. Update your project auth config with project URL and anon key.", "error");
                syncSignupSubmitState();
                return;
            }

            submitBtn.disabled = true;
            setStatus("Creating account...");

            try {
                const result = await supabaseApi.signUp({ email, password });
                if (result.session) {
                    setStatus("Account created. Redirecting...", "success");
                    window.location.href = nextTarget;
                    return;
                }

                setStatus(
                    "Account created. Check your email for confirmation, then sign in.",
                    "success"
                );
            } catch (error) {
                setStatus(error?.message || "Sign-up failed.", "error");
            } finally {
                syncSignupSubmitState();
            }
        });
    }

    void initialize();
})();
