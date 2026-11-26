// Deki study assistant (Google Gemini free tier). No imports.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, "Content-Type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const BASE = "https://generativelanguage.googleapis.com/v1beta";

// Newest flash model this key can use, from Google's own list.
async function pickModels(key: string): Promise<string[]> {
  const fixed = ["gemini-3.8-flash", "gemini-flash-latest", "gemini-flash-lite-latest"];
  try {
    const r = await fetch(`${BASE}/models?pageSize=200&key=${key}`, { signal: AbortSignal.timeout(6000) });
    const j = await r.json();
    const ver = (n: string) => parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? "0");
    const listed: string[] = (j?.models ?? [])
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
      .map((m: any) => String(m.name).replace("models/", ""))
      .filter((n: string) => /flash/.test(n) && !/(image|tts|live|audio|embed|robotics|computer|preview|exp)/.test(n))
      .sort((a: string, b: string) => ver(b) - ver(a) || a.length - b.length);
    return [...new Set([...listed.slice(0, 2), ...fixed])];
  } catch (_) {
    return fixed;
  }
}

Deno.serve(async (req: Request) => {
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
      for (let attempt = 0; attempt < 2; attempt++) {
        if (Date.now() - started > 45000) break;
        let r: Response;
        try {
          r = await fetch(`${BASE}/models/${model}:generateContent?key=${key}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              systemInstruction: { parts: [{ text: system }] },
              contents,
              generationConfig: { maxOutputTokens: 1500 },
            }),
            signal: AbortSignal.timeout(18000),
          });
        } catch (e) {
          errs.push(`${model}: ${String(e).slice(0, 60)}`);
          break;
        }
        const j = await r.json();
        const parts = j?.candidates?.[0]?.content?.parts ?? [];
        const text = parts.map((p: any) => p.text ?? "").join("").trim();
        if (text) return json({ text });
        errs.push(`${model}: ${r.status} ${String(j?.error?.message ?? "empty").slice(0, 80)}`);
        if (r.status === 503 && attempt === 0) {
          await sleep(1500);
          continue;
        }
        break;
      }
    }
    return json({ error: "gemini", detail: errs.join(" | ").slice(0, 500) });
  } catch (e) {
    return json({ error: String(e) });
  }
});
