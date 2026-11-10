(function () {
  "use strict";

  const project = "https://jclycoagtotikxskgkju.supabase.co";
  const key = "sb_publishable_zHB_lJ-kSGkVnU4F-9JcJA_OHPNCwlB";
  const redirect = "https://devrah0.github.io/Web/job-office/";
  const store = "job-office-manager-session-v1";
  let session = read();
  let refreshing;

  function read() {
    try {
      const value = JSON.parse(localStorage.getItem(store));
      return value?.access_token ? value : null;
    } catch {
      return null;
    }
  }

  function save(value) {
    session = value && {
      ...value,
      expires_at: Number(value.expires_at) || Math.floor(Date.now() / 1000) + Number(value.expires_in || 0),
    };
    try {
      if (session) localStorage.setItem(store, JSON.stringify(session));
      else localStorage.removeItem(store);
    } catch {
      // The current page can still use the session if Safari denies storage.
    }
  }

  window.addEventListener("storage", event => {
    if (event.key === store || event.key === null) session = read();
  });

  async function request(url, options = {}) {
    let response;
    try {
      response = await fetch(url, options);
    } catch {
      throw new Error("تعذر الوصول إلى الخادم. تحقق من الاتصال ثم أعد المحاولة.");
    }
    const body = await response.json().catch(() => ({}));
    if (response.ok) return body;
    const message = {
      invalid_credentials: "البريد الإلكتروني أو كلمة المرور غير صحيحة.",
      email_not_confirmed: "فعّل البريد من رسالة Supabase ثم حاول تسجيل الدخول.",
      otp_expired: "انتهت صلاحية رابط التفعيل أو سبق استخدامه. جرّب تسجيل الدخول.",
    }[body.error_code || body.code];
    const error = new Error(message || body.msg || body.error_description || body.message || body.error || "تعذر إكمال الطلب (" + response.status + ")");
    error.status = response.status;
    throw error;
  }

  function authRequest(path, body) {
    return request(project + "/auth/v1/" + path, {
      method: "POST",
      headers: { apikey: key, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  function headers(token = session?.access_token) {
    return { apikey: key, Authorization: "Bearer " + token, Accept: "application/json" };
  }

  const fresh = () => Number(session?.expires_at) > Date.now() / 1000 + 60;

  async function refresh() {
    session = read() || session;
    if (fresh()) return true;
    const previous = session;
    if (!previous?.refresh_token) {
      save(null);
      return false;
    }
    try {
      const value = await authRequest("token?grant_type=refresh_token", { refresh_token: previous.refresh_token });
      if (session !== previous) return fresh();
      save(value);
      return true;
    } catch (error) {
      if (session !== previous) return fresh();
      const newer = read();
      if (newer && newer.refresh_token !== previous.refresh_token) {
        session = newer;
        return fresh();
      }
      if (![400, 401, 403].includes(error.status)) throw error;
      save(null);
      return false;
    }
  }

  async function valid() {
    if (!session) return false;
    if (fresh()) return true;
    if (!refreshing) {
      refreshing = (navigator.locks
        ? navigator.locks.request(store, refresh)
        : refresh()).finally(() => { refreshing = undefined; });
    }
    return refreshing;
  }

  async function signIn(email, password) {
    save(await authRequest("token?grant_type=password", { email, password }));
  }

  async function signUp(email, password) {
    const value = await authRequest("signup?redirect_to=" + encodeURIComponent(redirect), { email, password });
    if (!value.access_token) return false;
    save(value);
    return true;
  }

  function signOut() {
    const token = session?.access_token;
    save(null);
    if (token) request(project + "/auth/v1/logout?scope=local", { method: "POST", headers: headers(token) }).catch(() => {});
  }

  async function readConfirmation() {
    const url = new URL(location.href);
    const fragment = new URLSearchParams(url.hash.slice(1));
    const params = fragment.has("access_token") || fragment.has("error") ? fragment : url.searchParams;
    if (!params.has("access_token") && !params.has("error")) return false;
    const token = params.get("access_token");
    const refreshToken = params.get("refresh_token");
    const type = params.get("type");
    const expiresAt = params.get("expires_at");
    const expiresIn = params.get("expires_in");
    if (params === fragment) url.hash = "";
    else for (const field of ["access_token", "refresh_token", "expires_at", "expires_in", "token_type", "type", "error", "error_code", "error_description"]) params.delete(field);
    history.replaceState(null, "", url);
    if (!token || !refreshToken || type !== "signup") {
      throw new Error("تعذر استخدام رابط التفعيل. إذا فعّلت البريد من قبل، سجّل الدخول بكلمة المرور.");
    }
    const user = await request(project + "/auth/v1/user", { headers: headers(token) });
    if (!user.email_confirmed_at) throw new Error("البريد يحتاج تأكيدًا قبل الدخول.");
    save({ access_token: token, refresh_token: refreshToken, expires_at: expiresAt, expires_in: expiresIn });
    return true;
  }

  window.JobOfficeAuth = { project, request, headers, valid, signIn, signUp, readConfirmation, signOut, get session() { return session; } };
})();
