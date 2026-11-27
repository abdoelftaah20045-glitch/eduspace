// Deki study assistant. Google Gemini free tier first; optional free fallbacks (Groq, OpenRouter) if their
// secrets exist. No imports. Secrets: GEMINI_API_KEY (needed), GROQ_API_KEY and/or OPENROUTER_API_KEY (optional).
// Diagnostic: POST {"diag":true} returns, per model, exactly what works for this key.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, "Content-Type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const BASE = "https://generativelanguage.googleapis.com/v1beta";

// Models that answered 404/403 or 429 with a zero limit are skipped for a while (per running instance).
const badUntil = new Map<string, number>();
const isBad = (m: string) => (badUntil.get(m) ?? 0) > Date.now();
const goodModel = { name: "", at: 0 };

type Probe = { model: string; status: number | string; ok: boolean; note: string; limit0: boolean; retryS?: number };

function classify(status: number, j: any): { limit0: boolean; perDay: boolean; retryS?: number; note: string } {
  const msg = String(j?.error?.message ?? "");
  const raw = JSON.stringify(j?.error ?? {});
  let retryS: number | undefined;
  let perDay = /per ?day|daily/i.test(raw);
  for (const d of j?.error?.details ?? []) {
    const m = String(d?.retryDelay ?? "").match(/(\d+(?:\.\d+)?)s/);
    if (m) retryS = Math.ceil(parseFloat(m[1]));
    for (const v of d?.violations ?? []) if (/PerDay/i.test(String(v?.quotaId ?? ""))) perDay = true;
  }
  const limit0 = status === 429 && /limit:\s*0\b/.test(raw);
  return { limit0, perDay, retryS, note: msg.slice(0, 140) };
}

function candidates(listed: any[]): string[] {
  const ver = (n: string) => parseFloat((n.match(/(?:gemini|gemma)-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
  const names: string[] = listed
    .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
    .map((m: any) => String(m.name).replace("models/", ""))
    .filter((n: string) => /(flash|lite|gemma|latest)/.test(n) && !/(image|tts|live|audio|embed|robotics|computer|vision|imagen|veo|aqa)/.test(n));
  // lite and small first (most likely to have free quota), then the rest newest first
  const rank = (n: string) => (/lite|8b/.test(n) ? 0 : /gemma/.test(n) ? 2 : 1);
  return [...new Set(names)].sort((a, b) => rank(a) - rank(b) || ver(b) - ver(a) || a.length - b.length);
}

async function listModels(key: string): Promise<any[]> {
  const out: any[] = [];
  let token = "";
  for (let i = 0; i < 4; i++) {
    const r = await fetch(`${BASE}/models?pageSize=200${token ? `&pageToken=${token}` : ""}&key=${key}`, { signal: AbortSignal.timeout(8000) });
    const j = await r.json();
    out.push(...(j?.models ?? []));
    token = j?.nextPageToken ?? "";
    if (!token) break;
  }
  return out;
}

async function callGemini(key: string, model: string, system: string, contents: any[], maxTokens: number, attempt: number) {
  const gemma = /gemma/.test(model);
  const v = parseFloat((model.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
  const gc: any = { maxOutputTokens: maxTokens };
  if (!gemma && attempt === 0) gc.thinkingConfig = v >= 3 ? { thinkingLevel: "low" } : { thinkingBudget: 0 };
  const body: any = { contents, generationConfig: gc };
  if (gemma) {
    // Gemma models take no system instruction: put it at the start of the first user message.
    const first = contents[0];
    body.contents = [{ role: "user", parts: [{ text: system + "\n\n" + (first?.parts?.[0]?.text ?? "") }] }, ...contents.slice(1)];
  } else {
    body.systemInstruction = { parts: [{ text: system }] };
  }
  const r = await fetch(`${BASE}/models/${model}:generateContent?key=${key}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(24000),
  });
  const j = await r.json();
  const parts = j?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.filter((p: any) => !p.thought).map((p: any) => p.text ?? "").join("").trim();
  return { r, j, text };
}

async function diag(key: string) {
  const out: Probe[] = [];
  let listed: any[] = [];
  try { listed = await listModels(key); } catch (e) {
    return { error: "list_models_failed", detail: String(e).slice(0, 200) };
  }
  const cand = candidates(listed).slice(0, 14);
  const started = Date.now();
  for (const model of cand) {
    if (Date.now() - started > 45000) { out.push({ model, status: "skipped", ok: false, note: "time budget", limit0: false }); continue; }
    try {
      const { r, j, text } = await callGemini(key, model, "Reply with one word.", [{ role: "user", parts: [{ text: "hi" }] }], 8, 1);
      if (text) { out.push({ model, status: r.status, ok: true, note: "works", limit0: false }); if (!goodModel.name) { goodModel.name = model; goodModel.at = Date.now(); } }
      else {
        const c = classify(r.status, j);
        out.push({ model, status: r.status, ok: false, note: c.note, limit0: c.limit0, retryS: c.retryS });
      }
    } catch (e) {
      out.push({ model, status: "error", ok: false, note: String(e).slice(0, 100), limit0: false });
    }
    await sleep(300);
  }
  const working = out.filter((p) => p.ok).map((p) => p.model);
  const allLimit0 = out.length > 0 && out.every((p) => !p.ok && (p.limit0 || p.status === 404 || p.status === 403));
  return {
    diag: true,
    models_listed: listed.length,
    working,
    all_blocked_or_no_quota: allLimit0,
    verdict: working.length
      ? `OK: use ${working[0]}`
      : allLimit0
        ? "No Gemini model is usable for this key (404/403/quota limit 0). The key's Google project has no free quota. Make a new key in a NEW Google AI Studio project, or add a free Groq/OpenRouter key."
        : "No model answered OK right now (rate limited or temporary). Retry in a minute.",
    probes: out,
    fallbacks: { groq: !!Deno.env.get("GROQ_API_KEY"), openrouter: !!Deno.env.get("OPENROUTER_API_KEY") },
  };
}

async function openaiStyle(url: string, key: string, model: string, system: string, msgs: { role: string; text: string }[], extraHeaders: Record<string, string> = {}) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}`, ...extraHeaders },
    body: JSON.stringify({
      model,
      max_tokens: 600,
      messages: [{ role: "system", content: system }, ...msgs.map((m) => ({ role: m.role === "assistant" ? "assistant" : "user", content: m.text }))],
    }),
    signal: AbortSignal.timeout(24000),
  });
  const j = await r.json();
  return { status: r.status, text: String(j?.choices?.[0]?.message?.content ?? "").trim(), err: String(j?.error?.message ?? "").slice(0, 100) };
}

console.log("ai-assistant boot ok");

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    const body = await req.json();
    if (body.diag === true) {
      if (!key) return json({ error: "no_key" });
      return json(await diag(key));
    }
    const msgs: { role: string; text: string }[] = (body.messages ?? []).slice(-10).map((m: any) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      text: String(m.text ?? "").slice(0, 2000),
    }));
    const contents = msgs.map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.text }] }));
    const system =
      `You are Deki, the smart assistant inside the Deki learning app. Reply in the user's language (${body.lang ?? "ar"}; Egyptian Arabic if Arabic), short, clear, friendly. Help with lessons, concepts, summaries, exam and study tips, planning, and using the app. For account, payments or grades, tell them to contact their organization admin. Never invent facts.`;
    const errs: string[] = [];
    const started = Date.now();

    if (key) {
      let models: string[] = [];
      try {
        models = candidates(await listModels(key));
      } catch (_) {
        console.error("listModels failed");
      }
      // last known working model first, skip models known to be blocked
      if (goodModel.name && Date.now() - goodModel.at < 3 * 3600000) models = [goodModel.name, ...models.filter((m) => m !== goodModel.name)];
      const ok = models.filter((m) => !isBad(m));
      for (const model of (ok.length ? ok : models).slice(0, 5)) {
        for (let attempt = 0; attempt < 2; attempt++) {
          if (Date.now() - started > 22000) break;
          let res;
          try {
            res = await callGemini(key, model, system, contents, 600, attempt);
          } catch (e) {
            errs.push(`${model}: ${String(e).slice(0, 50)}`);
            break;
          }
          const { r, j, text } = res;
          if (text) {
            goodModel.name = model; goodModel.at = Date.now();
            return json({ text });
          }
          const c = classify(r.status, j);
          errs.push(`${model}: ${r.status} ${c.note.slice(0, 60)}`);
          if (r.status === 404 || r.status === 403 || c.limit0) { badUntil.set(model, Date.now() + 6 * 3600000); break; }
          if (r.status === 429) { if (c.perDay) badUntil.set(model, Date.now() + 3 * 3600000); break; }
          if (r.status === 400 && attempt === 0) continue; // thinking setting not accepted
          if ((r.status === 503 || r.status === 500) && attempt === 0) { await sleep(1200); continue; }
          break;
        }
      }
    } else {
      errs.push("no GEMINI_API_KEY");
    }

    // Optional free fallbacks, only if their secrets are set.
    const groq = Deno.env.get("GROQ_API_KEY");
    if (groq) {
      try {
        const g = await openaiStyle("https://api.groq.com/openai/v1/chat/completions", groq, "llama-3.3-70b-versatile", system, msgs);
        if (g.text) return json({ text: g.text, provider: "groq" });
        errs.push(`groq: ${g.status} ${g.err}`);
      } catch (e) { errs.push(`groq: ${String(e).slice(0, 50)}`); }
    }
    const orr = Deno.env.get("OPENROUTER_API_KEY");
    if (orr) {
      for (const m of ["meta-llama/llama-3.3-70b-instruct:free", "google/gemma-3-27b-it:free"]) {
        try {
          const g = await openaiStyle("https://openrouter.ai/api/v1/chat/completions", orr, m, system, msgs, { "HTTP-Referer": "https://deki.app", "X-Title": "Deki" });
          if (g.text) return json({ text: g.text, provider: "openrouter" });
          errs.push(`openrouter ${m}: ${g.status} ${g.err}`);
        } catch (e) { errs.push(`openrouter: ${String(e).slice(0, 50)}`); }
      }
    }
    if (!key && !groq && !orr) return json({ error: "no_key" });
    console.error("assistant failed", errs.join(" | "));
    return json({ error: "gemini", detail: errs.join(" | ").slice(0, 500) });
  } catch (e) {
    console.error("handler error", String(e));
    return json({ error: "handler", detail: String(e) });
  }
});
