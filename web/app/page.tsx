export default function Home() {
  return (
    <div className="max-w-5xl mx-auto px-4 pt-10 pb-6">
      <h1 className="text-2xl font-bold text-white">WNBA Analytics — Web App Scaffold</h1>
      <p className="mt-3 text-sm text-slate-400 leading-relaxed max-w-2xl">
        This is the Phase 0 scaffold from{' '}
        <code className="bg-slate-900 px-1.5 py-0.5 rounded text-slate-300">
          docs/NEXTJS_WEB_APP_PLAN.md
        </code>
        . The Season Standings, Model Variants, Player Projections, Playoff Simulator, and
        Diagnostics pages will replace this once Phase 1&apos;s <code className="bg-slate-900 px-1.5 py-0.5 rounded text-slate-300">export_web_json.R</code>{' '}
        pipeline stage is writing JSON into <code className="bg-slate-900 px-1.5 py-0.5 rounded text-slate-300">public/data/</code>.
      </p>
    </div>
  );
}
