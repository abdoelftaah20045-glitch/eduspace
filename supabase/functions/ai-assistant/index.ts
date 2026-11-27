// Deki study assistant (Google Gemini free tier). No imports.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, "Content-Type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const BASE = "https://generativelanguage.googleapis.com/v1beta";

// Models that answered 403 (no access for this key) or 429 per day are skipped for a while.
const badUntil = new Map<string, number>();
const isBad = (m: string) => (badUntil.get(m) ?? 0) > Date.now();

// Stable 2.5 flash models first (free tier), then newer listed ones. Only names Google lists for this key.
async function pickModels(key: string): Promise<string[]> {
  const fixed = ["gemini-2.5-flash-lite", "gemini-2.5-flash", "gemini-flash-lite-latest", "gemini-flash-latest"];
  try {
    const r = await fetch(`${BASE}/models?pageSize=200&key=${key}`, { signal: AbortSignal.timeout(6000) });
    const j = await r.json();
    const ver = (n: string) => parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
    const listed: string[] = (j?.models ?? [])
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
      .map((m: any) => String(m.name).replace("models/", ""))
      .filter((n: string) => /flash/.test(n) && !/(image|tts|live|audio|embed|robotics|computer|preview|exp)/.test(n));
    const pref = ["gemini-2.5-flash-lite", "gemini-2.5-flash"].filter((n) => listed.includes(n));
    const rest = listed.filter((n) => !pref.includes(n)).sort((a, b) => ver(b) - ver(a) || a.length - b.length);
    const all = [...new Set([...pref, ...rest, ...(listed.length ? [] : fixed)])];
    const ok = all.filter((m) => !isBad(m));
    return (ok.length ? ok : all).slice(0, 5);
  } catch (_) {
    console.error("listModels failed");
    return fixed;
  }
}

console.log("ai-assistant boot ok");

Deno.serve(async (req: Request) => {
  console.log("request", req.method);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return json({ error: "no_key" });
    const body = await req.json();
    const contents = (body.messages ?? []).slice(-10).map((m: any) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: String(m.text ?? "").slice(0, 2000) }],
    }));
    const system =
      `You are Deki, the smart assistant inside the Deki learning app. Reply in the user's language (${body.lang ?? "ar"}; Egyptian Arabic if Arabic), short, clear, friendly. Help with lessons, concepts, summaries, exam and study tips, planning, and using the app. For account, payments or grades, tell them to contact their organization admin. Never invent facts.`;
    const errs: string[] = [];
    const started = Date.now();
    for (const model of (await pickModels(key)).slice(0, 4)) {
      const v = parseFloat((model.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
      // fastest thinking setting per generation; second try without it
      const thinking = v >= 3 ? { thinkingLevel: "low" } : { thinkingBudget: 0 };
      for (let attempt = 0; attempt < 2; attempt++) {
        if (Date.now() - started > 25000) break;
        let r: Response;
        try {
          r = await fetch(`${BASE}/models/${model}:generateContent?key=${key}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              systemInstruction: { parts: [{ text: system }] },
              contents,
              generationConfig: attempt === 0
                ? { maxOutputTokens: 600, thinkingConfig: thinking }
                : { maxOutputTokens: 600 },
            }),
            signal: AbortSignal.timeout(24000),
          });
        } catch (e) {
          console.error("fetch error", model, String(e));
          errs.push(`${model}: ${String(e).slice(0, 60)}`);
          break;
        }
        const j = await r.json();
        const parts = j?.candidates?.[0]?.content?.parts ?? [];
        const text = parts.filter((p: any) => !p.thought).map((p: any) => p.text ?? "").join("").trim();
        if (text) return json({ text });
        errs.push(`${model}: ${r.status} ${String(j?.error?.message ?? "empty").slice(0, 80)}`);
        if (r.status === 403 || r.status === 404) badUntil.set(model, Date.now() + 6 * 3600000);
        if (r.status === 429 && /per ?day|daily/i.test(JSON.stringify(j?.error ?? ""))) badUntil.set(model, Date.now() + 3 * 3600000);
        if (r.status === 400 && attempt === 0) continue; // thinking setting not accepted
        if (r.status === 503 && attempt === 0) {
          await sleep(1200);
          continue;
        }
        break;
      }
    }
    console.error("gemini failed", errs.join(" | "));
    return json({ error: "gemini", detail: errs.join(" | ").slice(0, 500) });
  } catch (e) {
    console.error("handler error", String(e));
    return json({ error: "handler", detail: String(e) });
  }
});
