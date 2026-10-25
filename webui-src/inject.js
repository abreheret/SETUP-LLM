// Ajoute une entree "Documentation" sous "Settings" dans le menu de l'interface web de llama-server,
// et affiche la doc clients en plein ecran par-dessus le chat.
// Injecte dans webui/index.html par tools/build-webui.py, precede de window.__SETUP_LLM_DOCS
// ({ css, pages: [{ id, title, html }] }). La doc est dans index.html parce que llama-server ne sert
// sans mot de passe que les fichiers de son interface integree : un fichier docs/*.html demanderait la cle.
// Le bouton Settings est clone (sans ses gestionnaires d'evenements) ; un MutationObserver le remet en
// place quand l'interface redessine le menu. Lien direct : http://<ip>:8080/?docs ou /?docs=opencode.
// Entree "Fichiers" : liste les fichiers crees par le modele avec les outils serveur (dossier /work du
// conteneur setup-llm-tools, ~/LLM-fichiers sur le Mac) et les telecharge via POST /tools (read_file en
// base64), avec la cle deja enregistree par l'interface. Lien direct : /?docs=files.
// Dans les reponses du chat, chaque chemin /work/... ecrit en code recoit un bouton "Telecharger".
// Voix : bouton micro a cote du bouton d'envoi (dictee transcrite par whisper-server via
// https://<ip>:8443/whisper/, voir voice/) et bouton "Lire a voix haute" sous chaque reponse (voix du
// systeme, francais ou anglais selon le texte). Le micro n'est autorise par les navigateurs qu'en HTTPS.
(function () {
  const DATA = window.__SETUP_LLM_DOCS;
  const ROOT_ID = "setup-llm-docs";
  const FILES_PAGE = "files";
  const FILES_DIR = "/work";
  const ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-4 w-4">' +
    '<path d="M2 4h6a4 4 0 0 1 4 4v12a3 3 0 0 0-3-3H2z"/><path d="M22 4h-6a4 4 0 0 0-4 4v12a3 3 0 0 1 3-3h7z"/></svg>';
  const FILES_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-4 w-4">' +
    '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>' +
    '<path d="M12 10v6"/><path d="m9 13 3 3 3-3"/></svg>';

  // --- Fichiers generes ---------------------------------------------------------------------------

  // Cle API saisie dans l'interface (Settings), enregistree par elle dans localStorage.
  function apiKey() {
    try {
      return JSON.parse(localStorage.getItem("LlamaUi.config") || "{}").apiKey?.toString().trim() || "";
    } catch {
      return "";
    }
  }

  async function runTool(tool, params, respType) {
    const headers = { "Content-Type": "application/json" };
    const key = apiKey();
    if (key) headers.Authorization = "Bearer " + key;
    if (respType) headers["x-resp-type"] = respType;
    const r = await fetch("./tools", { method: "POST", headers, body: JSON.stringify({ tool, params }) });
    if (r.status === 401) throw new Error("clé API absente ou invalide : saisissez-la dans Settings");
    if (r.status === 404) throw new Error("outils désactivés sur le serveur (conteneur setup-llm-tools arrêté ?)");
    const data = await r.json();
    if (data.error) throw new Error(data.error);
    return data;
  }

  const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  function formatSize(n) {
    if (n < 1024) return n + " o";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " Ko";
    return (n / 1024 / 1024).toFixed(1) + " Mo";
  }

  async function listFiles() {
    // find -printf : chemin relatif, taille, date ; les plus recents en premier.
    const cmd =
      `find ${FILES_DIR} -type f -not -path '*/.*' -printf '%T@\\t%P\\t%s\\n' | sort -rn | head -500`;
    const out = (await runTool("exec_shell_command", { command: cmd })).plain_text_response || "";
    return out
      .split("\n")
      .map((l) => l.split("\t"))
      .filter((f) => f.length === 3)
      .map(([time, path, size]) => ({
        path,
        size: Number(size),
        // Le conteneur est en UTC : date formatee dans le fuseau du navigateur.
        date: new Date(Number(time) * 1000).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }),
      }));
  }

  async function download(path, btn) {
    btn.disabled = true;
    btn.textContent = "…";
    try {
      const data = await runTool("read_file", { path: FILES_DIR + "/" + path }, "base64");
      const bytes = Uint8Array.from(atob(data.base64 || ""), (c) => c.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([bytes], { type: "application/octet-stream" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = path.split("/").pop();
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
      btn.textContent = "Télécharger";
    } catch (e) {
      btn.textContent = "Erreur";
      btn.title = e.message;
    } finally {
      btn.disabled = false;
    }
  }

  // Bouton de telechargement a cote de chaque chemin /work/<fichier> en code dans le chat. Le chemin est
  // relu au clic : pendant le streaming, le texte du code peut encore etre incomplet.
  const PATH_RE = new RegExp("^" + FILES_DIR + "/[^\\s]+\\.[A-Za-z0-9]{1,8}$");
  function addDownloadButtons() {
    for (const code of document.querySelectorAll("code:not([data-setup-llm-dl])")) {
      if (code.closest("pre, #" + ROOT_ID + ", textarea, [contenteditable]")) continue;
      if (!PATH_RE.test(code.textContent.trim())) continue;
      code.dataset.setupLlmDl = "1";
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "setup-llm-dl";
      btn.textContent = "Télécharger";
      btn.title = "Télécharger ce fichier depuis le serveur";
      btn.style.cssText =
        "margin-left:.4rem;padding:.05rem .5rem;border-radius:.4rem;border:1px solid rgba(127,127,127,.4);" +
        "background:transparent;color:inherit;font-size:.8em;cursor:pointer;vertical-align:baseline";
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        download(code.textContent.trim().slice(FILES_DIR.length + 1), btn);
      });
      code.insertAdjacentElement("afterend", btn);
    }
  }

  async function renderFiles(main) {
    main.innerHTML =
      "<h1>Fichiers</h1>" +
      "<p>Fichiers créés par le modèle avec les outils de l'interface (Shell, Write file), dans son dossier " +
      `<code>${FILES_DIR}</code>. Demandez-lui d'y enregistrer ses fichiers, puis téléchargez-les ici.</p>` +
      '<p><button type="button" class="files-refresh">Actualiser</button></p><div class="files-list">Chargement…</div>';
    main.querySelector(".files-refresh").addEventListener("click", () => renderFiles(main));
    const list = main.querySelector(".files-list");
    try {
      const files = await listFiles();
      if (!files.length) {
        list.innerHTML = "<p>Aucun fichier pour le moment.</p>";
        return;
      }
      list.innerHTML =
        "<table><thead><tr><th>Nom</th><th>Taille</th><th>Modifié</th><th></th></tr></thead><tbody>" +
        files
          .map(
            (f) =>
              `<tr><td><code>${esc(f.path)}</code></td><td>${formatSize(f.size)}</td><td>${esc(f.date)}</td>` +
              `<td><button type="button" class="files-dl" data-path="${esc(f.path)}">Télécharger</button></td></tr>`
          )
          .join("") +
        "</tbody></table>";
      for (const btn of list.querySelectorAll(".files-dl")) {
        btn.addEventListener("click", () => download(btn.dataset.path, btn));
      }
    } catch (e) {
      list.innerHTML = `<p>Impossible de lister les fichiers : ${esc(e.message)}</p>`;
    }
  }

  // --- Vue documentation -------------------------------------------------------------------------

  function addCopyButtons(container) {
    for (const pre of container.querySelectorAll("pre")) {
      const btn = document.createElement("button");
      btn.className = "copy";
      btn.type = "button";
      btn.textContent = "Copier";
      btn.addEventListener("click", async () => {
        const text = pre.querySelector("code")?.innerText ?? pre.innerText;
        try {
          await navigator.clipboard.writeText(text);
        } catch {
          // Page en HTTP simple sur le reseau : l'API presse-papiers est refusee, repli sur execCommand.
          const area = document.createElement("textarea");
          area.value = text;
          document.body.appendChild(area);
          area.select();
          document.execCommand("copy");
          area.remove();
        }
        btn.textContent = "Copié";
        setTimeout(() => (btn.textContent = "Copier"), 1500);
      });
      pre.appendChild(btn);
    }
  }

  function showPage(root, id, anchor) {
    const main = root.querySelector("main");
    if (id === FILES_PAGE) {
      for (const a of root.querySelectorAll("nav a[data-page]")) {
        a.classList.toggle("active", a.dataset.page === FILES_PAGE);
      }
      main.scrollTop = 0;
      renderFiles(main);
      return;
    }
    const page = DATA.pages.find((p) => p.id === id) || DATA.pages[0];
    main.innerHTML = page.html;
    addCopyButtons(main);
    for (const a of root.querySelectorAll("nav a[data-page]")) {
      a.classList.toggle("active", a.dataset.page === page.id);
    }
    const target = anchor && main.querySelector("#" + CSS.escape(anchor));
    if (target) target.scrollIntoView();
    else main.scrollTop = 0;
  }

  function openDocs(id) {
    let root = document.getElementById(ROOT_ID);
    if (!root) {
      root = document.createElement("div");
      root.id = ROOT_ID;
      const nav = DATA.pages
        .map((p) => `<a href="#" data-page="${p.id}">${p.title}</a>`)
        .join("");
      root.innerHTML =
        `<style>${DATA.css}</style>` +
        `<nav><a href="#" class="back">← Retour au chat</a><div class="label">Documentation</div>${nav}` +
        `<div class="label">Outils</div><a href="#" data-page="${FILES_PAGE}">Fichiers</a></nav>` +
        `<main></main>`;
      root.addEventListener("click", (e) => {
        const a = e.target.closest("a");
        if (!a) return;
        const href = a.getAttribute("href") || "";
        if (a.classList.contains("back")) {
          e.preventDefault();
          closeDocs();
        } else if (a.dataset.page) {
          e.preventDefault();
          showPage(root, a.dataset.page);
        } else if (href.startsWith("doc:")) {
          // Lien vers une autre page de doc : doc:<id> ou doc:<id>#<ancre>.
          e.preventDefault();
          const [page, anchor] = href.slice(4).split("#");
          showPage(root, page, anchor);
        } else if (href.startsWith("#")) {
          e.preventDefault();
          root.querySelector("main #" + CSS.escape(decodeURIComponent(href.slice(1))))?.scrollIntoView();
        } else {
          a.target = "_blank";
          a.rel = "noopener";
        }
      });
      document.body.appendChild(root);
    }
    root.hidden = false;
    showPage(root, id);
  }

  function closeDocs() {
    const root = document.getElementById(ROOT_ID);
    if (root) root.hidden = true;
  }

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeDocs();
  });

  // --- Voix : dictee et lecture a voix haute -----------------------------------------------------

  const MIC_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:18px;height:18px">' +
    '<path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/>' +
    '<line x1="12" x2="12" y1="19" y2="22"/></svg>';
  const SPEAK_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-3 w-3">' +
    '<path d="M11 5 6 9H2v6h4l5 4V5Z"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>';
  const STOP_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" ' +
    'stroke="none" class="h-3 w-3"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>';
  const HTTPS_PORT = "8443";

  function showNotice(anchor, html) {
    document.getElementById("setup-llm-notice")?.remove();
    const box = document.createElement("div");
    box.id = "setup-llm-notice";
    box.innerHTML = html + '<div style="text-align:right;margin-top:.5rem"><button type="button">OK</button></div>';
    box.style.cssText =
      "position:fixed;z-index:2147482500;max-width:24rem;padding:.8rem 1rem;border-radius:.6rem;font-size:.85rem;" +
      "line-height:1.45;background:#1f1f22;color:#ececee;border:1px solid #3a3a40;box-shadow:0 8px 24px rgba(0,0,0,.35)";
    box.querySelector("a")?.setAttribute("style", "color:#7aa7ff;text-decoration:underline");
    box.querySelector("button").style.cssText =
      "padding:.2rem .8rem;border-radius:.4rem;border:1px solid #3a3a40;background:#2a2a2e;color:inherit;cursor:pointer";
    box.querySelector("button").addEventListener("click", () => box.remove());
    document.body.appendChild(box);
    const r = anchor.getBoundingClientRect();
    box.style.left = Math.max(8, Math.min(r.right - box.offsetWidth, innerWidth - box.offsetWidth - 8)) + "px";
    box.style.top = Math.max(8, r.top - box.offsetHeight - 10) + "px";
  }

  // Valeur du champ de saisie : passe par le setter natif puis un evenement input, pour que
  // l'interface (Svelte) prenne le texte en compte.
  function insertPrompt(text) {
    const ta = document.querySelector("form textarea");
    if (!ta || !text) return;
    const current = ta.value;
    const value = current && !/\s$/.test(current) ? current + " " + text : current + text;
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(ta, value);
    ta.dispatchEvent(new Event("input", { bubbles: true }));
    ta.focus();
  }

  // Audio enregistre (webm/opus, mp4...) converti en WAV 16 kHz mono : le format lu par whisper-server
  // sans ffmpeg.
  async function toWav16k(blob) {
    const ctx = new AudioContext();
    const decoded = await ctx.decodeAudioData(await blob.arrayBuffer());
    ctx.close();
    const off = new OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
    const src = off.createBufferSource();
    src.buffer = decoded;
    src.connect(off.destination);
    src.start();
    const pcm = (await off.startRendering()).getChannelData(0);
    const buf = new DataView(new ArrayBuffer(44 + pcm.length * 2));
    const str = (o, t) => [...t].forEach((c, i) => buf.setUint8(o + i, c.charCodeAt(0)));
    str(0, "RIFF");
    buf.setUint32(4, 36 + pcm.length * 2, true);
    str(8, "WAVEfmt ");
    buf.setUint32(16, 16, true);
    buf.setUint16(20, 1, true);
    buf.setUint16(22, 1, true);
    buf.setUint32(24, 16000, true);
    buf.setUint32(28, 32000, true);
    buf.setUint16(32, 2, true);
    buf.setUint16(34, 16, true);
    str(36, "data");
    buf.setUint32(40, pcm.length * 2, true);
    for (let i = 0; i < pcm.length; i++) {
      buf.setInt16(44 + i * 2, Math.max(-1, Math.min(1, pcm[i])) * 0x7fff, true);
    }
    return new Blob([buf], { type: "audio/wav" });
  }

  async function transcribe(blob) {
    const form = new FormData();
    form.append("file", await toWav16k(blob), "audio.wav");
    form.append("response_format", "json");
    form.append("temperature", "0");
    const headers = {};
    const key = apiKey();
    if (key) headers.Authorization = "Bearer " + key;
    const r = await fetch("./whisper/inference", { method: "POST", headers, body: form });
    if (r.status === 401) throw new Error("clé API absente ou invalide : saisissez-la dans Settings");
    if (!r.ok) {
      // Seul le port HTTPS (Caddy) sert /whisper/ : ailleurs (http://localhost:8080 sur le Mac...), 404.
      throw new Error(
        `transcription indisponible (HTTP ${r.status}) : utilisez https://${location.hostname}:${HTTPS_PORT}/`
      );
    }
    return ((await r.json()).text || "").trim();
  }

  let recording = null;
  async function toggleMic(btn) {
    if (!window.isSecureContext || !navigator.mediaDevices) {
      const url = `https://${location.hostname}:${HTTPS_PORT}/`;
      showNotice(
        btn,
        "<b>Le micro demande une connexion HTTPS.</b><br>Ouvrez " +
          `<a href="${url}">${url}</a>. Au premier accès, le navigateur affiche une alerte de sécurité ` +
          "(certificat du Mac) : <i>Paramètres avancés</i>, puis <i>Continuer</i>. Saisissez ensuite le mot de passe " +
          "une fois : les conversations de l'adresse en HTTP n'y sont pas reprises."
      );
      return;
    }
    if (recording) {
      recording.recorder.stop();
      return;
    }
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      });
    } catch (e) {
      showNotice(btn, "Micro inaccessible : " + esc(e.message) + "<br>Autorisez le micro pour ce site dans le navigateur.");
      return;
    }
    const recorder = new MediaRecorder(stream);
    const chunks = [];
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    recorder.onstop = async () => {
      clearTimeout(recording?.timer);
      recording = null;
      stream.getTracks().forEach((t) => t.stop());
      setMicState(btn, "busy");
      try {
        insertPrompt(await transcribe(new Blob(chunks, { type: recorder.mimeType })));
      } catch (e) {
        showNotice(btn, "Transcription impossible : " + esc(e.message));
      } finally {
        setMicState(btn, "idle");
      }
    };
    recorder.start();
    // Dictee limitee a 5 minutes.
    recording = { recorder, timer: setTimeout(() => recorder.state === "recording" && recorder.stop(), 300000) };
    setMicState(btn, "rec");
  }

  function setMicState(btn, state) {
    btn.dataset.state = state;
    btn.style.color = state === "rec" ? "#ef4444" : "";
    btn.style.animation = state === "rec" ? "setup-llm-pulse 1.2s ease-in-out infinite" : "";
    btn.style.opacity = state === "busy" ? ".5" : "";
    btn.disabled = state === "busy";
    btn.title = state === "rec" ? "Arrêter et transcrire" : state === "busy" ? "Transcription…" : "Dicter (micro)";
    btn.setAttribute("aria-label", btn.title);
  }

  function addMicButton() {
    const form = document.querySelector("form textarea")?.closest("form");
    if (!form || form.querySelector(".setup-llm-mic")) return;
    const submit = form.querySelector('button[type="submit"]');
    if (!submit) return;
    if (!document.getElementById("setup-llm-voice-style")) {
      const st = document.createElement("style");
      st.id = "setup-llm-voice-style";
      st.textContent =
        "@keyframes setup-llm-pulse{0%,100%{opacity:1}50%{opacity:.4}}" +
        ".setup-llm-mic{display:inline-flex;align-items:center;justify-content:center;width:2rem;height:2rem;" +
        "border-radius:9999px;border:0;background:transparent;color:inherit;cursor:pointer;opacity:.75}" +
        ".setup-llm-mic:hover{opacity:1;background:rgba(127,127,127,.15)}";
      document.head.appendChild(st);
    }
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "setup-llm-mic";
    btn.innerHTML = MIC_ICON;
    setMicState(btn, recording ? "rec" : "idle");
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      toggleMic(btn);
    });
    submit.insertAdjacentElement("beforebegin", btn);
  }

  // Texte lisible d'une reponse : sans la reflexion, les blocs de code ni les adresses web.
  function speakableText(group) {
    const parts = [];
    for (const md of group.querySelectorAll(".agentic-text .markdown-content")) {
      const c = md.cloneNode(true);
      c.querySelectorAll("pre, .code-block-wrapper, button, svg").forEach((el) => el.replaceWith(" "));
      for (const el of c.querySelectorAll("p, li, h1, h2, h3, h4, tr, br, div")) el.append(". ");
      parts.push(c.textContent);
    }
    return parts
      .join(". ")
      .replace(/https?:\/\/\S+/g, " ")
      .replace(/[*_#`>|]+/g, " ")
      .replace(/(\s*\.\s*){2,}/g, ". ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function detectLang(text) {
    const t = " " + text.toLowerCase() + " ";
    const count = (words) => words.reduce((n, w) => n + t.split(" " + w + " ").length - 1, 0);
    const fr = count(["le", "la", "les", "des", "est", "et", "une", "pour", "dans", "que", "vous", "pas"]) + (t.match(/[éèêàçù]/g) || []).length / 3;
    const en = count(["the", "and", "is", "of", "to", "in", "that", "for", "you", "with", "are", "this"]);
    return fr >= en ? "fr" : "en";
  }

  // Meilleure voix du systeme pour la langue : voix "naturelles" ou "premium" d'abord (Edge, macOS).
  function pickVoice(lang) {
    const voices = speechSynthesis.getVoices().filter((v) => v.lang.toLowerCase().startsWith(lang));
    const score = (v) =>
      (/natural|neural|premium|enhanced|online/i.test(v.name) ? 4 : 0) +
      (/google/i.test(v.name) ? 2 : 0) +
      (v.lang.toLowerCase() === (lang === "fr" ? "fr-fr" : "en-us") ? 1 : 0) +
      (v.localService ? 0 : 1);
    return voices.sort((a, b) => score(b) - score(a))[0] || null;
  }

  let speakingBtn = null;
  function stopSpeaking() {
    speechSynthesis.cancel();
    if (speakingBtn) setSpeakState(speakingBtn, false);
    speakingBtn = null;
  }

  function setSpeakState(btn, on) {
    const svg = btn.querySelector("svg");
    const cls = svg?.getAttribute("class");
    if (svg) svg.outerHTML = on ? STOP_ICON : SPEAK_ICON;
    if (cls) btn.querySelector("svg").setAttribute("class", cls);
    btn.title = on ? "Arrêter la lecture" : "Lire à voix haute";
    btn.setAttribute("aria-label", btn.title);
  }

  function speak(group, btn) {
    const wasMine = speakingBtn === btn;
    stopSpeaking();
    if (wasMine) return;
    const text = speakableText(group);
    if (!text) return;
    const lang = detectLang(text);
    const voice = pickVoice(lang);
    // Phrases lues une a une : Chrome coupe les longues lectures d'un seul bloc.
    const sentences = text.split(/(?<=[.!?;:])\s+/);
    const chunks = [];
    for (const s of sentences) {
      if (chunks.length && (chunks[chunks.length - 1] + s).length < 220) chunks[chunks.length - 1] += " " + s;
      else chunks.push(s);
    }
    speakingBtn = btn;
    setSpeakState(btn, true);
    chunks.forEach((chunk, i) => {
      const u = new SpeechSynthesisUtterance(chunk.trim());
      u.lang = voice?.lang || (lang === "fr" ? "fr-FR" : "en-US");
      if (voice) u.voice = voice;
      if (i === chunks.length - 1) u.onend = () => speakingBtn === btn && stopSpeaking();
      speechSynthesis.speak(u);
    });
  }

  function addSpeakButtons() {
    if (!("speechSynthesis" in window)) return;
    for (const group of document.querySelectorAll('[aria-label="Assistant message with actions"]')) {
      const copy = group.querySelector('button[aria-label="Copy"]');
      if (!copy || copy.parentElement.querySelector(".setup-llm-speak")) continue;
      const btn = copy.cloneNode(true);
      btn.classList.add("setup-llm-speak");
      btn.removeAttribute("data-slot");
      btn.removeAttribute("data-state");
      setSpeakState(btn, false);
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        speak(group, btn);
      });
      copy.insertAdjacentElement("afterend", btn);
    }
  }

  // Chrome charge la liste des voix apres coup.
  if ("speechSynthesis" in window) speechSynthesis.getVoices();

  // --- Entree de menu ----------------------------------------------------------------------------

  // Menu deplie : bouton avec le texte "Settings". Menu replie : icone seule, aria-label="Settings".
  function findSettings() {
    for (const el of document.querySelectorAll("a, button")) {
      if (el.id.startsWith("setup-llm-") || !el.querySelector("svg")) continue;
      const text = el.textContent.trim();
      if (text === "Settings" || (text === "" && el.getAttribute("aria-label") === "Settings")) return el;
    }
    return null;
  }

  function relabel(node, label) {
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      if (walker.currentNode.nodeValue.trim() === "Settings") {
        walker.currentNode.nodeValue = walker.currentNode.nodeValue.replace("Settings", label);
      }
    }
    for (const el of [node, ...node.querySelectorAll("[title], [aria-label]")]) {
      if (el.getAttribute("title") === "Settings") el.setAttribute("title", label);
      if (el.getAttribute("aria-label") === "Settings") el.setAttribute("aria-label", label);
    }
  }

  // Entrees ajoutees sous Settings, dans cet ordre.
  const ENTRIES = [
    { id: "setup-llm-docs-link", label: "Documentation", icon: ICON, open: () => openDocs() },
    { id: "setup-llm-files-link", label: "Fichiers", icon: FILES_ICON, open: () => openDocs(FILES_PAGE) },
  ];

  // Ecran "Access denied / Enter API Key" (pas encore de mot de passe) : pas de menu, donc un bouton
  // flottant, pour que la doc reste accessible avant la premiere connexion.
  function syncFloatingButton(hasMenu) {
    const ID = "setup-llm-docs-float";
    let btn = document.getElementById(ID);
    const show = !hasMenu && /Enter API Key|Server Connection Error/.test(document.body?.innerText || "");
    if (show && !btn) {
      btn = document.createElement("button");
      btn.id = ID;
      btn.type = "button";
      btn.innerHTML = ICON + "<span>Documentation</span>";
      btn.style.cssText =
        "position:fixed;right:1rem;bottom:1rem;z-index:2147482000;display:flex;gap:.5rem;align-items:center;" +
        "padding:.55rem .9rem;border-radius:.6rem;border:1px solid rgba(127,127,127,.35);cursor:pointer;" +
        "background:inherit;color:inherit;font:inherit;font-size:.9rem";
      btn.addEventListener("click", () => openDocs());
      document.body.appendChild(btn);
    } else if (!show && btn) {
      btn.remove();
    }
  }

  function addLink() {
    const settings = findSettings();
    syncFloatingButton(!!settings);
    // Le bouton est parfois seul dans une enveloppe (infobulle) : c'est elle qui porte l'espacement du
    // menu, on la clone avec lui.
    let anchor = settings;
    const parent = settings?.parentElement;
    if (parent && [...parent.children].filter((c) => !c.id.startsWith("setup-llm-")).length === 1) {
      anchor = parent;
    }
    let prev = anchor;
    for (const entry of ENTRIES) {
      const existing = document.getElementById(entry.id + "-wrap") || document.getElementById(entry.id);
      // Menu replie ou deplie : l'interface remplace le bouton Settings, les clones doivent suivre.
      if (existing && prev && existing.previousElementSibling === prev) {
        prev = existing;
        continue;
      }
      existing?.remove();
      if (!settings) continue;
      const clone = anchor.cloneNode(true);
      const link = anchor === settings ? clone : clone.querySelector("a, button");
      if (clone !== link) clone.id = entry.id + "-wrap";
      link.id = entry.id;
      for (const attr of ["data-active", "aria-current", "href"]) link.removeAttribute(attr);
      const svg = link.querySelector("svg");
      if (svg) {
        const cls = svg.getAttribute("class");
        svg.outerHTML = entry.icon;
        if (cls) link.querySelector("svg").setAttribute("class", cls);
      }
      relabel(link, entry.label);
      link.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        entry.open();
      });
      prev.insertAdjacentElement("afterend", clone);
      prev = clone;
    }
  }

  if (!DATA) return;
  new MutationObserver(() => {
    addLink();
    addDownloadButtons();
    addMicButton();
    addSpeakButtons();
  }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  addLink();
  addDownloadButtons();
  addMicButton();
  addSpeakButtons();

  const wanted = new URLSearchParams(location.search).get("docs");
  if (wanted !== null) {
    const start = () => openDocs(wanted);
    if (document.body) start();
    else document.addEventListener("DOMContentLoaded", start);
  }
})();
