// Ajoute une entree "Documentation" sous "Settings" dans le menu de l'interface web de llama-server,
// et affiche la doc clients en plein ecran par-dessus le chat.
// Injecte dans webui/index.html par tools/build-webui.py, precede de window.__SETUP_LLM_DOCS
// ({ css, pages: [{ id, title, html }] }). La doc est dans index.html parce que llama-server ne sert
// sans mot de passe que les fichiers de son interface integree : un fichier docs/*.html demanderait la cle.
// Le bouton Settings est clone (sans ses gestionnaires d'evenements) ; un MutationObserver le remet en
// place quand l'interface redessine le menu. Lien direct : http://<ip>:8080/?docs ou /?docs=opencode.
(function () {
  const DATA = window.__SETUP_LLM_DOCS;
  const LINK_ID = "setup-llm-docs-link";
  const ROOT_ID = "setup-llm-docs";
  const ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="h-4 w-4">' +
    '<path d="M2 4h6a4 4 0 0 1 4 4v12a3 3 0 0 0-3-3H2z"/><path d="M22 4h-6a4 4 0 0 0-4 4v12a3 3 0 0 1 3-3h7z"/></svg>';

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
    const page = DATA.pages.find((p) => p.id === id) || DATA.pages[0];
    const main = root.querySelector("main");
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
        `<nav><a href="#" class="back">← Retour au chat</a><div class="label">Documentation</div>${nav}</nav>` +
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

  // --- Entree de menu ----------------------------------------------------------------------------

  // Menu deplie : bouton avec le texte "Settings". Menu replie : icone seule, aria-label="Settings".
  function findSettings() {
    for (const el of document.querySelectorAll("a, button")) {
      if (el.id === LINK_ID || !el.querySelector("svg")) continue;
      const text = el.textContent.trim();
      if (text === "Settings" || (text === "" && el.getAttribute("aria-label") === "Settings")) return el;
    }
    return null;
  }

  function relabel(node) {
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      if (walker.currentNode.nodeValue.trim() === "Settings") {
        walker.currentNode.nodeValue = walker.currentNode.nodeValue.replace("Settings", "Documentation");
      }
    }
    for (const el of [node, ...node.querySelectorAll("[title], [aria-label]")]) {
      if (el.getAttribute("title") === "Settings") el.setAttribute("title", "Documentation");
      if (el.getAttribute("aria-label") === "Settings") el.setAttribute("aria-label", "Documentation");
    }
  }

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
    if (parent && [...parent.children].filter((c) => c.id !== LINK_ID && c.id !== LINK_ID + "-wrap").length === 1) {
      anchor = parent;
    }
    const existing = document.getElementById(LINK_ID + "-wrap") || document.getElementById(LINK_ID);
    // Menu replie ou deplie : l'interface remplace le bouton Settings, le clone doit suivre.
    if (existing && existing.previousElementSibling === anchor) return;
    existing?.remove();
    if (!settings) return;
    const clone = anchor.cloneNode(true);
    const link = anchor === settings ? clone : clone.querySelector("a, button");
    if (clone !== link) clone.id = LINK_ID + "-wrap";
    link.id = LINK_ID;
    for (const attr of ["data-active", "aria-current", "href"]) link.removeAttribute(attr);
    const svg = link.querySelector("svg");
    if (svg) {
      const cls = svg.getAttribute("class");
      svg.outerHTML = ICON;
      if (cls) link.querySelector("svg").setAttribute("class", cls);
    }
    relabel(link);
    link.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      openDocs();
    });
    anchor.insertAdjacentElement("afterend", clone);
  }

  if (!DATA) return;
  new MutationObserver(addLink).observe(document.documentElement, { childList: true, subtree: true });
  addLink();

  const wanted = new URLSearchParams(location.search).get("docs");
  if (wanted !== null) {
    const start = () => openDocs(wanted);
    if (document.body) start();
    else document.addEventListener("DOMContentLoaded", start);
  }
})();
