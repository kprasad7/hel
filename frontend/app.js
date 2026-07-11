// Vanilla JS, no build step, no SDK — talks to Cognito's public JSON API
// directly (stable, long-standing AWS API surface) and to our own API Gateway.
// Deliberately simple per the "simple UI initially" brief; a framework/build
// step can replace this later without touching the backend contract.
(() => {
  const cfg = window.APP_CONFIG;
  const cognitoEndpoint = `https://cognito-idp.${cfg.AWS_REGION}.amazonaws.com/`;

  const $ = (id) => document.getElementById(id);
  const show = (el) => el.classList.remove("hidden");
  const hide = (el) => el.classList.add("hidden");

  async function cognito(action, body) {
    const resp = await fetch(cognitoEndpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-amz-json-1.1",
        "X-Amz-Target": `AWSCognitoIdentityProviderService.${action}`,
      },
      body: JSON.stringify(body),
    });
    const data = await resp.json();
    if (!resp.ok) {
      throw new Error(data.message || data.__type || "Request failed");
    }
    return data;
  }

  function saveSession(authResult, email) {
    sessionStorage.setItem("id_token", authResult.IdToken);
    sessionStorage.setItem("user_email", email);
  }

  function getIdToken() {
    return sessionStorage.getItem("id_token");
  }

  function clearSession() {
    sessionStorage.removeItem("id_token");
    sessionStorage.removeItem("user_email");
  }

  // ---------- form switching ----------
  $("show-signup").addEventListener("click", (e) => {
    e.preventDefault();
    hide($("signin-form"));
    show($("signup-form"));
  });
  $("show-signin").addEventListener("click", (e) => {
    e.preventDefault();
    hide($("signup-form"));
    show($("signin-form"));
  });

  // ---------- sign up ----------
  $("signup-btn").addEventListener("click", async () => {
    const email = $("signup-email").value.trim();
    const password = $("signup-password").value;
    $("signup-error").textContent = "";
    try {
      await cognito("SignUp", {
        ClientId: cfg.COGNITO_APP_CLIENT_ID,
        Username: email,
        Password: password,
        UserAttributes: [{ Name: "email", Value: email }],
      });
      $("confirm-email").value = email;
      hide($("signup-form"));
      show($("confirm-form"));
    } catch (err) {
      $("signup-error").textContent = err.message;
    }
  });

  // ---------- confirm sign up ----------
  $("confirm-btn").addEventListener("click", async () => {
    const email = $("confirm-email").value.trim();
    const code = $("confirm-code").value.trim();
    $("confirm-error").textContent = "";
    try {
      await cognito("ConfirmSignUp", {
        ClientId: cfg.COGNITO_APP_CLIENT_ID,
        Username: email,
        ConfirmationCode: code,
      });
      hide($("confirm-form"));
      show($("signin-form"));
      $("signin-email").value = email;
    } catch (err) {
      $("confirm-error").textContent = err.message;
    }
  });

  // ---------- sign in ----------
  $("signin-btn").addEventListener("click", async () => {
    const email = $("signin-email").value.trim();
    const password = $("signin-password").value;
    $("signin-error").textContent = "";
    try {
      const data = await cognito("InitiateAuth", {
        AuthFlow: "USER_PASSWORD_AUTH",
        ClientId: cfg.COGNITO_APP_CLIENT_ID,
        AuthParameters: { USERNAME: email, PASSWORD: password },
      });
      saveSession(data.AuthenticationResult, email);
      enterApp(email);
    } catch (err) {
      $("signin-error").textContent = err.message;
    }
  });

  $("signout-btn").addEventListener("click", () => {
    clearSession();
    hide($("app-section"));
    show($("auth-section"));
  });

  // ---------- main app ----------
  function enterApp(email) {
    hide($("auth-section"));
    show($("app-section"));
    $("user-email").textContent = email;
  }

  let pollHandle = null;

  async function submitJob() {
    const prompt = $("prompt-input").value.trim();
    $("submit-error").textContent = "";
    if (!prompt) {
      $("submit-error").textContent = "Enter a prompt first.";
      return;
    }

    $("submit-btn").disabled = true;
    try {
      const resp = await fetch(`${cfg.API_INVOKE_URL}/generate`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${getIdToken()}`,
        },
        body: JSON.stringify({ prompt }),
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.error || "Failed to submit job");

      show($("job-card"));
      $("job-id").textContent = data.job_id;
      $("job-status").textContent = data.status;
      hide($("result-video"));
      $("job-stage-note").textContent =
        "This runs 4 GPU stages plus final assembly — first-run cold starts can take several minutes.";

      pollJob(data.job_id);
    } catch (err) {
      $("submit-error").textContent = err.message;
    } finally {
      $("submit-btn").disabled = false;
    }
  }

  function pollJob(jobId) {
    if (pollHandle) clearInterval(pollHandle);
    const start = Date.now();
    const maxMs = 20 * 60 * 1000; // give up after 20 minutes

    pollHandle = setInterval(async () => {
      if (Date.now() - start > maxMs) {
        clearInterval(pollHandle);
        $("job-stage-note").textContent = "Still not done after 20 minutes — check the AWS console.";
        return;
      }
      try {
        const resp = await fetch(`${cfg.API_INVOKE_URL}/jobs/${jobId}`, {
          headers: { Authorization: getIdToken() },
        });
        const data = await resp.json();
        if (!resp.ok) return; // transient — keep polling

        $("job-status").textContent = data.status;

        if (data.status === "COMPLETE") {
          clearInterval(pollHandle);
          $("job-stage-note").textContent = "";
          const video = $("result-video");
          video.src = data.output_url;
          show(video);
        } else if (data.status === "FAILED") {
          clearInterval(pollHandle);
          $("job-stage-note").textContent = `Failed: ${data.error || "unknown error"}`;
        }
      } catch (_err) {
        // transient network error — keep polling
      }
    }, 5000);
  }

  $("submit-btn").addEventListener("click", submitJob);

  // ---------- boot ----------
  if (getIdToken()) {
    enterApp(sessionStorage.getItem("user_email"));
  }
})();
